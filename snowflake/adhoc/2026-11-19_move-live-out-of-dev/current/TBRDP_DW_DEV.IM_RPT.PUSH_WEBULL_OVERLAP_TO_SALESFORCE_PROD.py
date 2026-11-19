
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
            return f"AUTH ERROR: {response.text}"

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
            INNER JOIN TBRDP_DW_DEV.IM_RPT.V_SBL_CRM_PERSON_ACCOUNT_DCR    lkp
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
        return f"FATAL ERROR: {str(e)}"
