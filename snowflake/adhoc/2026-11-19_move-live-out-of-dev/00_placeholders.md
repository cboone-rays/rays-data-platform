# Placeholders used in these scripts

Every script uses `<ANGLE_BRACKET>` placeholders, so none of them runs as written. Replace them once the Foundations items exist.

| Placeholder | What it is | Status |
|---|---|---|
| `<PROD_SERVICE_ROLE>` | Non-ACCOUNTADMIN role that owns PROD tasks and procedures | Doesn't exist yet (Foundations: service logins) |
| `<ADMIN_SERVICE_ROLE>` | Role for account housekeeping (AI budget). It needs `MANAGE GRANTS`, or ownership of `TBRDP_DW_PROD_CORTEX_USER`. | Doesn't exist yet |
| `<TASK_FAILURE_INTEGRATION>` | Notification integration used as each task's `ERROR_INTEGRATION`, so a failed run sends an alert | Doesn't exist yet. Which integration types `ERROR_INTEGRATION` accepts (email vs. webhook vs. cloud queue) needs checking **(guess that email works)** |
| `<SF_EXTERNAL_ACCESS_INTEGRATION>` | Allows the Python procedures to call Salesforce | Exists today on the DEV procedures, but its name isn't visible to our role. Get it from `DESCRIBE PROCEDURE` (needs DEV access). |
| `<SF_SECRET_DB.SCHEMA.NAME>` | The Snowflake secret mapped to `'sf_creds'` | Same as above. **Check whether both Salesforce procedures use the same secret** (see README). |

Warehouse used for everything here: `TBRDP_DW_PROD_XS_WH`. It exists and used 56 credits in the last 30 days.
