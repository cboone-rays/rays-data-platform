-- 01 — PROD activation-summary task: move it off the DEV warehouse
-- DRAFT FOR REVIEW. Do not run without approval. Placeholders: see 00_placeholders.md.
--
-- Today: TBRDP_DW_PROD.LOAD.REFRESH_ACTIVATION_SUMMARY_TABLE is a PROD task, owned by ACCOUNTADMIN,
-- running every 5 minutes on TBRDP_DW_DEV_XS_WH. It copies new clean-room activation rows
-- (SAMOOHA_BY_SNOWFLAKE_LOCAL_DB.PUBLIC.PROVIDER_ACTIVATION_SUMMARY) into TBRDP_DW_PROD.LOAD.ACTIVATION_SUMMARY_TABLE.
-- The WeBull push (script 04) reads that table's stream, ACTIVATION_SUMMARY_STREAM.
--
-- The change: warehouse only. The schedule change to hourly is a separate decision (it needs the clean-room
-- owner's OK). It's shown commented out below.
-- Risk: low. The task's SQL is unchanged.

-- A task must be suspended before it can be altered.
ALTER TASK TBRDP_DW_PROD.LOAD.REFRESH_ACTIVATION_SUMMARY_TABLE SUSPEND;

ALTER TASK TBRDP_DW_PROD.LOAD.REFRESH_ACTIVATION_SUMMARY_TABLE SET
    WAREHOUSE = TBRDP_DW_PROD_XS_WH
    ERROR_INTEGRATION = <TASK_FAILURE_INTEGRATION>
    COMMENT = 'Copies new clean-room activations into PROD LOAD for the daily WeBull push. Owner: <TBD>.';
--  SCHEDULE = '60 MINUTE'   -- only after the clean-room owner agrees (saves ~$3.8K–4.5K/yr together with the DEV twin)

ALTER TASK TBRDP_DW_PROD.LOAD.REFRESH_ACTIVATION_SUMMARY_TABLE RESUME;

-- After the service role exists: move ownership off ACCOUNTADMIN.
-- The new owner role needs: USAGE on TBRDP_DW_PROD_XS_WH; SELECT on the Samooha source view; INSERT on the target.
-- GRANT OWNERSHIP ON TASK TBRDP_DW_PROD.LOAD.REFRESH_ACTIVATION_SUMMARY_TABLE TO ROLE <PROD_SERVICE_ROLE> COPY CURRENT GRANTS;

-- Check afterwards (read-only):
-- SELECT scheduled_time, state, error_message FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
-- WHERE database_name = 'TBRDP_DW_PROD' AND name = 'REFRESH_ACTIVATION_SUMMARY_TABLE' ORDER BY scheduled_time DESC LIMIT 5;

-- Separate candidate (not part of this move): the DEV twin TBRDP_DW_DEV.LOAD.REFRESH_ACTIVATION_SUMMARY_TABLE
-- copies CONSUMER_DIRECT_ACTIVATION_SUMMARY into DEV every 5 min. Nothing was seen reading it.
-- Confirm with the clean-room owner, then suspend it.
