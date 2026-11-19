-- 02 — E15/Levy and Eventellect loads: move from DEV to PROD
-- DRAFT FOR REVIEW. Do not run without approval. Placeholders: see 00_placeholders.md.
--
-- TODAY (from the procedure code, pulled Nov 19, 2026)
-- Six tasks in TBRDP_DW_DEV.IM_RPT each call a near-identical DEV procedure that:
--   1. truncates and reloads the DEV LOAD table from the partner share;
--   2. truncates the QA LOAD table and copies DEV's copy into it;
--   3. truncates the PROD LOAD table and copies DEV's copy into it.
-- So PROD's data takes a path of share → DEV → PROD. The task settings say "target: TBRDP_DW_DEV",
-- but the PROD and QA targets are hard-coded inside each procedure.
-- Weak spots: each TRUNCATE + INSERT pair is two separate steps, so PROD's table is empty while it reloads. If the
-- INSERT fails, PROD stays empty and nothing alerts. Owners: 4 run as TBRDP_DW_DEV_COALESCE_ROLE, 2 as ACCOUNTADMIN.
--
--   Task (DEV)                                         Schedule                    Share source → PROD target
--   E15_LEVY_CONCESSIONS_DATA_INGESTION_PROC_CALL      0 */12 * * * UTC            SHR_E15_RAYS.CONCESSIONS.SHR_LEVY_CONCESSIONS_RAYS → LOAD.E15_LEVY_CONCESSIONS_LOAD
--   E15_LEVY_SUITES_DATA_INGESTION_PROC_CALL           0 */12 * * * UTC            SHR_E15_RAYS.SUITES.SHR_LEVY_SUITES_RAYS → LOAD.E15_LEVY_SUITES_LOAD
--   E15_RETAIL_TRANSACTIONS_DATA_INGESTION_PROC_CALL   0 */12 * * * UTC            SHR_E15_RAYS.RETAIL.SHR_RETAIL_CLOUD_TRANSACTIONS_RAYS → LOAD.E15_RETAIL_TRANSACTIONS_LOAD
--   E15_RETAIL_INVENTORY_DATA_INGESTION_PROC_CALL      0 */12 * * * UTC            SHR_E15_RAYS.RETAIL.SHR_RETAIL_CLOUD_INVENTORY_RAYS → LOAD.E15_RETAIL_INVENTORY_LOAD
--   EVENTELLECT_DATA_INGESTION_PROC_CALL               0 */2 * * * UTC             EVENTELLECT__….SEMANTIC_SHARED.TAMPA_BAY_RAYS_INVENTORY_VW → LOAD.EVENTELLECT_TICKET_TRANSACTIONS_LOAD
--   EVENTELLECT_FORECAST_INGESTION_PROC_CALL           30 10 * * * America/New_York EVENTELLECT__…SEMANTIC_SHARED.TAMPA_BAY_RAYS_UNIFIED_FORECAST_VW → LOAD.EVENTELLECT_FORECAST_LOAD
--   (E15_LEVY_PREMIUM_DATA_INGESTION_PROC_CALL exists too but hasn't run in 3+ days, and the table hasn't changed in 267 days:
--    it's suspended. Not moved; see the cleanup item "fix or retire E15_LEVY_PREMIUM_LOAD".)
--
-- TARGET
-- One generic PROD procedure that loads share → PROD directly, in a single atomic statement (INSERT OVERWRITE),
-- so PROD is never empty halfway through a load. There's no DEV or QA copy: DEV and QA will get these tables from the
-- PROD clone (DEV/QA workflow item). QA's LOAD copies go stale in the meantime. Nobody reads QA (query H, Nov 18).
-- PROD table names are unchanged, so no Coalesce change is needed.
-- Same schedules as today.

------------------------------------------------------------------------------------------------
-- Step A — grants the PROD service role needs (Snowflake admin)
------------------------------------------------------------------------------------------------
-- GRANT IMPORTED PRIVILEGES ON DATABASE SHR_E15_RAYS TO ROLE <PROD_SERVICE_ROLE>;
-- GRANT IMPORTED PRIVILEGES ON DATABASE EVENTELLECT__TAMPA_BAY_RAYS_PARTNER_DATA_SHARE TO ROLE <PROD_SERVICE_ROLE>;
-- GRANT USAGE ON WAREHOUSE TBRDP_DW_PROD_XS_WH TO ROLE <PROD_SERVICE_ROLE>;
-- GRANT INSERT, DELETE, SELECT ON ALL TABLES IN SCHEMA TBRDP_DW_PROD.LOAD TO ROLE <PROD_SERVICE_ROLE>;  -- or just the 6 tables
-- GRANT CREATE PROCEDURE, CREATE TASK ON SCHEMA TBRDP_DW_PROD.LOAD TO ROLE <PROD_SERVICE_ROLE>;
-- GRANT EXECUTE TASK ON ACCOUNT TO ROLE <PROD_SERVICE_ROLE>;

------------------------------------------------------------------------------------------------
-- Step B — create the procedure and the tasks (they're created SUSPENDED; Snowflake's default)
------------------------------------------------------------------------------------------------
USE ROLE <PROD_SERVICE_ROLE>;

CREATE OR REPLACE PROCEDURE TBRDP_DW_PROD.LOAD.COPY_SHARE_TO_LOAD(SOURCE_TABLE VARCHAR, TARGET_TABLE VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Full reload of a PROD LOAD table from a partner share. Atomic: the target is never left empty.'
AS
$$
BEGIN
    -- Guard: only ever write into PROD LOAD.
    IF (NOT STARTSWITH(UPPER(:TARGET_TABLE), 'TBRDP_DW_PROD.LOAD.')) THEN
        RAISE STATEMENT_ERROR;
    END IF;

    INSERT OVERWRITE INTO IDENTIFIER(:TARGET_TABLE)
    SELECT * FROM IDENTIFIER(:SOURCE_TABLE);

    RETURN 'Loaded ' || SQLROWCOUNT || ' rows into ' || :TARGET_TABLE;
END;
$$;
-- Note: SELECT * means a new column in the share breaks the load. That's the same as today, and now it alerts.

CREATE OR REPLACE TASK TBRDP_DW_PROD.LOAD.E15_LEVY_CONCESSIONS_LOAD_TASK
    WAREHOUSE = TBRDP_DW_PROD_XS_WH
    SCHEDULE = 'USING CRON 0 */12 * * * UTC'
    ERROR_INTEGRATION = <TASK_FAILURE_INTEGRATION>
    COMMENT = 'E15/Levy concessions share → PROD LOAD. Every 12 h, same as the DEV task it replaces. Owner: <TBD>.'
AS CALL TBRDP_DW_PROD.LOAD.COPY_SHARE_TO_LOAD('SHR_E15_RAYS.CONCESSIONS.SHR_LEVY_CONCESSIONS_RAYS', 'TBRDP_DW_PROD.LOAD.E15_LEVY_CONCESSIONS_LOAD');

CREATE OR REPLACE TASK TBRDP_DW_PROD.LOAD.E15_LEVY_SUITES_LOAD_TASK
    WAREHOUSE = TBRDP_DW_PROD_XS_WH
    SCHEDULE = 'USING CRON 0 */12 * * * UTC'
    ERROR_INTEGRATION = <TASK_FAILURE_INTEGRATION>
    COMMENT = 'E15/Levy suites share → PROD LOAD. Every 12 h, same as the DEV task it replaces. Owner: <TBD>.'
AS CALL TBRDP_DW_PROD.LOAD.COPY_SHARE_TO_LOAD('SHR_E15_RAYS.SUITES.SHR_LEVY_SUITES_RAYS', 'TBRDP_DW_PROD.LOAD.E15_LEVY_SUITES_LOAD');

CREATE OR REPLACE TASK TBRDP_DW_PROD.LOAD.E15_RETAIL_TRANSACTIONS_LOAD_TASK
    WAREHOUSE = TBRDP_DW_PROD_XS_WH
    SCHEDULE = 'USING CRON 0 */12 * * * UTC'
    ERROR_INTEGRATION = <TASK_FAILURE_INTEGRATION>
    COMMENT = 'E15 retail transactions share → PROD LOAD. Every 12 h, same as the DEV task it replaces. Owner: <TBD>.'
AS CALL TBRDP_DW_PROD.LOAD.COPY_SHARE_TO_LOAD('SHR_E15_RAYS.RETAIL.SHR_RETAIL_CLOUD_TRANSACTIONS_RAYS', 'TBRDP_DW_PROD.LOAD.E15_RETAIL_TRANSACTIONS_LOAD');

CREATE OR REPLACE TASK TBRDP_DW_PROD.LOAD.E15_RETAIL_INVENTORY_LOAD_TASK
    WAREHOUSE = TBRDP_DW_PROD_XS_WH
    SCHEDULE = 'USING CRON 0 */12 * * * UTC'
    ERROR_INTEGRATION = <TASK_FAILURE_INTEGRATION>
    COMMENT = 'E15 retail inventory share → PROD LOAD. Every 12 h, same as the DEV task it replaces. Owner: <TBD>.'
AS CALL TBRDP_DW_PROD.LOAD.COPY_SHARE_TO_LOAD('SHR_E15_RAYS.RETAIL.SHR_RETAIL_CLOUD_INVENTORY_RAYS', 'TBRDP_DW_PROD.LOAD.E15_RETAIL_INVENTORY_LOAD');

CREATE OR REPLACE TASK TBRDP_DW_PROD.LOAD.EVENTELLECT_TICKET_TRANSACTIONS_LOAD_TASK
    WAREHOUSE = TBRDP_DW_PROD_XS_WH
    SCHEDULE = 'USING CRON 0 */2 * * * UTC'
    ERROR_INTEGRATION = <TASK_FAILURE_INTEGRATION>
    COMMENT = 'Eventellect inventory share → PROD LOAD. Every 2 h, same as the DEV task it replaces. Owner: <TBD>.'
AS CALL TBRDP_DW_PROD.LOAD.COPY_SHARE_TO_LOAD('EVENTELLECT__TAMPA_BAY_RAYS_PARTNER_DATA_SHARE.SEMANTIC_SHARED.TAMPA_BAY_RAYS_INVENTORY_VW', 'TBRDP_DW_PROD.LOAD.EVENTELLECT_TICKET_TRANSACTIONS_LOAD');

CREATE OR REPLACE TASK TBRDP_DW_PROD.LOAD.EVENTELLECT_FORECAST_LOAD_TASK
    WAREHOUSE = TBRDP_DW_PROD_XS_WH
    SCHEDULE = 'USING CRON 30 10 * * * America/New_York'
    ERROR_INTEGRATION = <TASK_FAILURE_INTEGRATION>
    COMMENT = 'Eventellect forecast share → PROD LOAD. Daily 10:30 ET, before the ~10:36 ticket forecast. Owner: <TBD>.'
AS CALL TBRDP_DW_PROD.LOAD.COPY_SHARE_TO_LOAD('EVENTELLECT__TAMPA_BAY_RAYS_PARTNER_DATA_SHARE.SEMANTIC_SHARED.TAMPA_BAY_RAYS_UNIFIED_FORECAST_VW', 'TBRDP_DW_PROD.LOAD.EVENTELLECT_FORECAST_LOAD');

------------------------------------------------------------------------------------------------
-- Step C — test one load by hand, then switch over (pick a time away from :00)
------------------------------------------------------------------------------------------------
-- Before: record row counts (read-only).
-- SELECT 'CONCESSIONS', COUNT(*) FROM TBRDP_DW_PROD.LOAD.E15_LEVY_CONCESSIONS_LOAD UNION ALL ... ;

-- 1. Run one new task once and compare its row count with the share's.
-- EXECUTE TASK TBRDP_DW_PROD.LOAD.EVENTELLECT_FORECAST_LOAD_TASK;

-- 2. Switch: suspend the old DEV task, resume the new PROD task. Do it per pair, or all at once.
--    Overlap is harmless here: both jobs fully reload the same data. But don't leave both running.
-- ALTER TASK TBRDP_DW_DEV.IM_RPT.E15_LEVY_CONCESSIONS_DATA_INGESTION_PROC_CALL SUSPEND;
-- ALTER TASK TBRDP_DW_PROD.LOAD.E15_LEVY_CONCESSIONS_LOAD_TASK RESUME;
-- ... same for the other five ...

-- 3. Watch: the next scheduled run of each new task, then PROD's 2 Hour and Post Game Coalesce jobs, which read these tables.

-- Roll back: suspend the PROD task and resume the DEV task. Nothing else changes.
-- After about 2 weeks with no problems, and with the owner's OK: drop the DEV tasks and procedures.
