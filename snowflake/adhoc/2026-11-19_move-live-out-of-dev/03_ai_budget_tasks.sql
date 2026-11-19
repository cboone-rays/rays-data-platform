-- 03 — AI budget control: move out of DEV into GOVERNANCE
-- DRAFT FOR REVIEW. Do not run without approval. Placeholders: see 00_placeholders.md.
--
-- TODAY (from the code)
--   TBRDP_DW_DEV.LOAD.CREDIT_AI_SERVICE_USAGE_DAILY      hourly, as ACCOUNTADMIN, on the DEV warehouse
--       Sums today's AI credits from SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY. If over 50 credits,
--       it calls DISABLE_AI_SERVICES_OVER_BUDGET().
--   TBRDP_DW_DEV.LOAD.DISABLE_AI_SERVICES_OVER_BUDGET()  revokes role TBRDP_DW_PROD_CORTEX_USER from 3 named users
--   TBRDP_DW_DEV.LOAD.RESTORE_AI_SERVICES_ACCESS_DAILY   00:05 UTC daily; calls ENABLE_AI_SERVICES_BUDGET_RESET(),
--       which grants the role back to the same 3 users.
--
-- Things to know before moving it:
--   * The usage numbers lag. ACCOUNT_USAGE runs up to ~3 hours behind, and METERING_DAILY_HISTORY is a daily
--     rollup. So the cap trips late, if at all **(guess about how much late)**. AI spend is ~$2.50/month, so it
--     has never come close to 50 credits (~$150/day).
--   * The user list is hard-coded. Anyone given the role later isn't covered. RESTORE also *grants* the role every
--     night, so removing someone's access by hand gets undone at 00:05 UTC. The target version below keeps the
--     same 3 users, so behavior is identical, and the user list moves into a table.
--   * GRANT/REVOKE ROLE needs MANAGE GRANTS or ownership of the role. That's why it was built as ACCOUNTADMIN.
--     The target uses a dedicated admin role instead (rule 2: no ACCOUNTADMIN in new code).
--   * Simpler alternative worth considering: a Snowflake budget or resource monitor. Decide with the owner.
--     If the cap isn't needed at ~$2.50/mo, just suspend both tasks.

USE ROLE <ADMIN_SERVICE_ROLE>;

CREATE SCHEMA IF NOT EXISTS GOVERNANCE.AI_BUDGET COMMENT = 'Account-wide AI spending cap (moved from TBRDP_DW_DEV.LOAD).';

CREATE TABLE IF NOT EXISTS GOVERNANCE.AI_BUDGET.CAPPED_USERS (USER_NAME VARCHAR NOT NULL)
    COMMENT = 'Users whose TBRDP_DW_PROD_CORTEX_USER role is switched off when the daily AI cap is hit.';
-- INSERT INTO GOVERNANCE.AI_BUDGET.CAPPED_USERS VALUES ('YTAKETANI@RAYSBASEBALL.COM'), ('JDOMINGUEZ'), ('ABUCHNER@RAYSBASEBALL.COM');

CREATE OR REPLACE PROCEDURE GOVERNANCE.AI_BUDGET.SET_CORTEX_ACCESS(ENABLE BOOLEAN)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    c CURSOR FOR SELECT USER_NAME FROM GOVERNANCE.AI_BUDGET.CAPPED_USERS;
    n INTEGER DEFAULT 0;
    stmt VARCHAR;
BEGIN
    FOR r IN c DO
        stmt := IFF(:ENABLE, 'GRANT ROLE TBRDP_DW_PROD_CORTEX_USER TO USER ', 'REVOKE ROLE TBRDP_DW_PROD_CORTEX_USER FROM USER ')
                || '"' || r.USER_NAME || '"';
        EXECUTE IMMEDIATE :stmt;
        n := n + 1;
    END FOR;
    RETURN IFF(:ENABLE, 'Enabled', 'Disabled') || ' AI access for ' || n || ' users';
END;
$$;

CREATE OR REPLACE TASK GOVERNANCE.AI_BUDGET.CHECK_AI_SPEND_HOURLY
    WAREHOUSE = TBRDP_DW_PROD_XS_WH
    SCHEDULE = '60 MINUTE'
    ERROR_INTEGRATION = <TASK_FAILURE_INTEGRATION>
    COMMENT = 'Hourly: turn off Cortex access for capped users if today''s AI credits > 50. Replaces TBRDP_DW_DEV.LOAD.CREDIT_AI_SERVICE_USAGE_DAILY.'
AS
DECLARE
    daily_credits FLOAT;
BEGIN
    SELECT COALESCE(SUM(CREDITS_USED), 0) INTO :daily_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
    WHERE SERVICE_TYPE IN ('AI_SERVICES', 'AI_FUNCTIONS', 'AI_INFERENCE')
      AND USAGE_DATE = CURRENT_DATE();
    IF (daily_credits > 50) THEN
        CALL GOVERNANCE.AI_BUDGET.SET_CORTEX_ACCESS(FALSE);
    END IF;
END;

CREATE OR REPLACE TASK GOVERNANCE.AI_BUDGET.RESTORE_AI_ACCESS_DAILY
    WAREHOUSE = TBRDP_DW_PROD_XS_WH
    SCHEDULE = 'USING CRON 5 0 * * * UTC'
    ERROR_INTEGRATION = <TASK_FAILURE_INTEGRATION>
    COMMENT = 'Daily 00:05 UTC: restore Cortex access after the daily cap. Replaces TBRDP_DW_DEV.LOAD.RESTORE_AI_SERVICES_ACCESS_DAILY.'
AS CALL GOVERNANCE.AI_BUDGET.SET_CORTEX_ACCESS(TRUE);

-- Switch over: suspend the DEV pair, then resume the GOVERNANCE pair.
-- ALTER TASK TBRDP_DW_DEV.LOAD.CREDIT_AI_SERVICE_USAGE_DAILY SUSPEND;
-- ALTER TASK TBRDP_DW_DEV.LOAD.RESTORE_AI_SERVICES_ACCESS_DAILY SUSPEND;
-- ALTER TASK GOVERNANCE.AI_BUDGET.CHECK_AI_SPEND_HOURLY RESUME;
-- ALTER TASK GOVERNANCE.AI_BUDGET.RESTORE_AI_ACCESS_DAILY RESUME;
