-- 04 — WeBull overlap push to Salesforce: move the procedure from DEV to PROD
-- DRAFT FOR REVIEW. Do not run without approval. Placeholders: see 00_placeholders.md.
-- Generated from current/TBRDP_DW_DEV.IM_RPT.PUSH_WEBULL_OVERLAP_TO_SALESFORCE_PROD.py (the DEV procedure as of Nov 19, 2026). The only edits are marked "# CHANGED (PROD move)".
--
-- TODAY: PROD task TBRDP_DW_PROD.LOAD.TRIGGER_WEBULL_OVERLAP_PUSH (daily 6:00 ET, ACCOUNTADMIN, DEV warehouse)
--        calls TBRDP_DW_DEV.IM_RPT.PUSH_WEBULL_OVERLAP_TO_SALESFORCE_PROD(). That procedure:
--   1. logs in to Salesforce with the secret 'sf_creds' using the username-password grant;
--   2. reads new rows from the stream TBRDP_DW_PROD.LOAD.ACTIVATION_SUMMARY_STREAM (fed by script 01's task);
--   3. matches them to Salesforce accounts through the **DEV** view TBRDP_DW_DEV.IM_RPT.V_SBL_CRM_PERSON_ACCOUNT_DCR;
--   4. PATCHes Account.Webull_User__c / _30__c / _50__c = TRUE. Each save fires the 3 Account Apex triggers.
-- CHANGES: read the PROD copy of the view (it exists: TBRDP_DW_PROD.IM_RPT.V_SBL_CRM_PERSON_ACCOUNT_DCR, last altered
--   Mar 20, 2026), and raise errors instead of returning them as text. Salesforce writes are otherwise identical.
-- BEFORE RUNNING:
--   * Check that the PROD and DEV views give the same matches (read-only):
--       SELECT COUNT(*), COUNT(DISTINCT ACCOUNT_ID_BK) FROM TBRDP_DW_PROD.IM_RPT.V_SBL_CRM_PERSON_ACCOUNT_DCR;  -- vs the DEV view
--   * Secret: this procedure uses the username-password grant. The account-upsert procedure (script 05) says the
--     Salesforce app was switched to an External Client App, which doesn't support that grant. If both use the same
--     secret, this push has been failing silently. Check the 'sf_creds' mapping with DESCRIBE PROCEDURE (needs DEV access).
--   * Stream: only one procedure may read ACTIVATION_SUMMARY_STREAM. Each read moves the stream forward, so once the
--     new procedure runs, the old one must never run again.
--   * Known gap, unchanged here: rows whose PATCH fails aren't retried. The stream has already moved past them.

USE ROLE <PROD_SERVICE_ROLE>;

CREATE OR REPLACE PROCEDURE TBRDP_DW_PROD.LOAD.PUSH_WEBULL_OVERLAP_TO_SALESFORCE()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'main'
EXTERNAL_ACCESS_INTEGRATIONS = (<SF_EXTERNAL_ACCESS_INTEGRATION>)
SECRETS = ('sf_creds' = <SF_SECRET_DB.SCHEMA.NAME>)
EXECUTE AS OWNER
COMMENT = 'Daily WeBull clean-room overlap to Salesforce Account flags. Moved from TBRDP_DW_DEV.IM_RPT.'
AS
$$

import _snowflake
import requests
import json
from collections import defaultdict

def main(session):
    results = {"success": 0, "failed": 0, "errors": []}

    try:
        # ── 1. Authenticate to Salesforce ──────────────────────────────────
        secret_str = _snowflake.get_generic_secret_string('sf_creds')
        creds = json.loads(secret_str)

        SF_LOGIN_URL = 'https://login.salesforce.com'
        payload = {
            'grant_type':    'password',
            'client_id':     creds['client_id'],
            'client_secret': creds['client_secret'],
            'username':      creds['username'],
            'password':      creds['password'] + creds['security_token']
        }

        response = requests.post(f'{SF_LOGIN_URL}/services/oauth2/token', data=payload)
        if response.status_code != 200:
            raise Exception(f"AUTH ERROR: {response.text}")  # CHANGED (PROD move): fail the task so the alert fires

        token_data   = response.json()
        access_token = token_data['access_token']
        instance_url = token_data['instance_url']
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type":  "application/json"
        }

        # ── 2. Consume the stream via DML to advance its offset ─────────────
        # A bare SELECT does NOT advance the stream offset — only DML does.
        # We stage stream rows into a temp table so the offset advances on commit.
        session.sql("""
            CREATE OR REPLACE TEMPORARY TABLE TBRDP_DW_PROD.LOAD.ACTIVATION_STREAM_STAGING AS
            SELECT * FROM TBRDP_DW_PROD.LOAD.ACTIVATION_SUMMARY_STREAM
        """).collect()

        # ── 3. Join staged rows to lookup table ───────────────────────────────
        # USER_ID is a JSON string containing hashed email and DISCOUNT_TYPE
        # The JSON structure is flat (no nested 'ID' key) e.g:
        # {"c.HASHED_EMAIL":"ba58b1cd...","c.DISCOUNT_TYPE":"1",...}
        query = """
            SELECT DISTINCT
                lkp.ACCOUNT_ID_BK                                           AS SALESFORCE_ACCOUNT_ID,
                PARSE_JSON(stg.USER_ID):"c.DISCOUNT_TYPE"::STRING           AS DISCOUNT_TYPE
            FROM TBRDP_DW_PROD.LOAD.ACTIVATION_STREAM_STAGING                stg
            INNER JOIN TBRDP_DW_PROD.IM_RPT.V_SBL_CRM_PERSON_ACCOUNT_DCR   lkp   -- CHANGED (PROD move): was TBRDP_DW_DEV
                ON PARSE_JSON(stg.USER_ID):"p.HASHED_EMAIL"::STRING
                   = lkp.HASHED_EMAIL
            WHERE lkp.ACCOUNT_ID_BK IS NOT NULL
        """

        matched_records = session.sql(query).collect()

        if not matched_records:
            return "No new overlap records in stream. Nothing pushed to Salesforce."

        # ── 4. Group DISCOUNT_TYPEs by Salesforce Account ID ───────────────
        # Since the same account can have multiple discount types we group
        # them first and build a single PATCH payload per account containing
        # ALL matching fields set to TRUE in one API call
        #
        # DISCOUNT_TYPE mapping:
        #   1 → Webull_User__c      = TRUE
        #   2 → Webull_User_30__c   = TRUE
        #   3 → Webull_User_50__c   = TRUE
        #
        # Example for abc123 with types 1 and 2:
        #   PATCH payload → {"Webull_User__c": true, "Webull_User_30__c": true}

        DISCOUNT_TYPE_MAP = {
            '1': 'Webull_User__c',
            '2': 'Webull_User_30__c',
            '3': 'Webull_User_50__c'
        }

        # Build a dict of {account_id: set(discount_types)}
        account_discounts = defaultdict(set)
        for row in matched_records:
            sf_id         = row["SALESFORCE_ACCOUNT_ID"]
            discount_type = str(row["DISCOUNT_TYPE"]).strip() if row["DISCOUNT_TYPE"] else None

            if not sf_id or sf_id.strip() == "":
                results["errors"].append("Skipped: missing SALESFORCE_ACCOUNT_ID")
                results["failed"] += 1
                continue

            if discount_type not in DISCOUNT_TYPE_MAP:
                results["errors"].append({
                    "salesforce_id": sf_id,
                    "error": f"Unknown DISCOUNT_TYPE value: '{discount_type}' — skipped"
                })
                results["failed"] += 1
                continue

            account_discounts[sf_id].add(discount_type)

        # ── 5. PATCH Each Account with a Single Combined Payload ────────────
        # One API call per account regardless of how many discount types it has
        # Only fields matching the account's discount types are set to TRUE
        # All other Salesforce fields are left as-is (not included in payload)
        for sf_id, discount_types in account_discounts.items():

            # Build payload with all matching fields set to TRUE
            patch_payload = {
                DISCOUNT_TYPE_MAP[dt]: True
                for dt in discount_types
                if dt in DISCOUNT_TYPE_MAP
            }

            sf_url = f"{instance_url}/services/data/v56.0/sobjects/Account/{sf_id}"

            patch_response = requests.patch(
                sf_url,
                headers=headers,
                data=json.dumps(patch_payload)
            )

            # Salesforce returns 204 No Content on a successful PATCH
            if patch_response.status_code == 204:
                results["success"] += 1
            else:
                results["failed"] += 1
                results["errors"].append({
                    "salesforce_id": sf_id,
                    "discount_types": list(discount_types),
                    "payload":        patch_payload,
                    "status_code":    patch_response.status_code,
                    "error":          patch_response.text
                })

        # ── 6. Return Summary ──────────────────────────────────────────────
        return json.dumps({
            "message": f"Completed. {results['success']} accounts updated, {results['failed']} failed.",
            "success": results["success"],
            "failed":  results["failed"],
            "errors":  results["errors"]
        }, indent=2)

    except Exception as e:
        raise  # CHANGED (PROD move): was return "FATAL ERROR", which made the task show SUCCEEDED
$$;

-- Point the existing PROD task at the PROD procedure. Do it between runs: the task runs at 6:00 ET.
ALTER TASK TBRDP_DW_PROD.LOAD.TRIGGER_WEBULL_OVERLAP_PUSH SUSPEND;
ALTER TASK TBRDP_DW_PROD.LOAD.TRIGGER_WEBULL_OVERLAP_PUSH MODIFY AS CALL TBRDP_DW_PROD.LOAD.PUSH_WEBULL_OVERLAP_TO_SALESFORCE();
ALTER TASK TBRDP_DW_PROD.LOAD.TRIGGER_WEBULL_OVERLAP_PUSH SET
    WAREHOUSE = TBRDP_DW_PROD_XS_WH
    ERROR_INTEGRATION = <TASK_FAILURE_INTEGRATION>
    COMMENT = 'Daily 6:00 ET: push new WeBull clean-room matches to Salesforce Account flags. Owner: <TBD>.';
ALTER TASK TBRDP_DW_PROD.LOAD.TRIGGER_WEBULL_OVERLAP_PUSH RESUME;
-- GRANT OWNERSHIP ON TASK TBRDP_DW_PROD.LOAD.TRIGGER_WEBULL_OVERLAP_PUSH TO ROLE <PROD_SERVICE_ROLE> COPY CURRENT GRANTS;
-- The owner role also needs SELECT on the stream and table, and CREATE TABLE on TBRDP_DW_PROD.LOAD (for the temp staging table).
-- Roll back: MODIFY AS CALL TBRDP_DW_DEV.IM_RPT.PUSH_WEBULL_OVERLAP_TO_SALESFORCE_PROD();
-- Afterwards: DEV PUSH_WEBULL_OVERLAP_TO_SALESFORCE_PROD and the older PUSH_WEBULL_OVERLAP_TO_SALESFORCE are drop candidates (owner OK first).
