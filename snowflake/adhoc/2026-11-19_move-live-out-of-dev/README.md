# Move live processes out of DEV and QA: draft scripts

This is the Foundations item from the Nov 18–19 review. **Nothing here has been run.** Every script contains `<PLACEHOLDER>` names (see `00_placeholders.md`), so it can't run as written.

The facts below come from `ACCOUNT_USAGE.TASK_VERSIONS`, `ACCOUNT_USAGE.PROCEDURES` and `TASK_HISTORY`, pulled Nov 19, 2026. The current DEV code is saved in `current/` for reference. It contains no credentials: the Salesforce procedures read a Snowflake secret at run time.

## What the code showed (new since Nov 18)

1. **The account upsert reads PROD, not DEV.** It pulls patron changes from `TBRDP_DW_PROD.IM_RPT` views. Its only DEV dependency is the log table it writes to. The "stale DEV data in Salesforce" worry is ruled out.
2. **The WeBull push does read DEV.** It matches accounts through `TBRDP_DW_DEV.IM_RPT.V_SBL_CRM_PERSON_ACCOUNT_DCR`. PROD has the same view, so the fix is a one-word change.
3. **The partner loads go share → DEV → QA → PROD.** Each procedure reloads DEV from the share, then copies DEV's table into QA and PROD. PROD's table is briefly empty during each load, and a failure leaves it empty, with no alert.
4. **The Salesforce procedures never report failure.** They catch every error and return it as text, so `TASK_HISTORY` always shows SUCCEEDED. A broken login, for example, would go unnoticed.
5. **Possible silent WeBull failure.** The upsert's comments say the Salesforce app moved to an "External Client App", which doesn't allow the username-password login. The WeBull push still uses that login. If both read the same secret, the WeBull flags have been failing silently. This needs `DESCRIBE PROCEDURE` with DEV access to check.
6. **Two upsert behaviors to fix later**, separately from the move:
   - The 120-minute look-back on an hourly schedule pushes every change twice, so the Salesforce triggers fire twice.
   - A failed Salesforce search, such as an email containing an apostrophe, falls through to **creating a new Account**. That's a likely source of duplicates **(guess about how often it happens)**.
7. `E15_LEVY_PREMIUM_DATA_INGESTION_PROC_CALL` does exist, but it's suspended. That's why the premium table hasn't changed in 267 days.

## Scripts, in the order to do them

| # | File | Change | Risk |
|---|---|---|---|
| 01 | `01_activation_task_warehouse.sql` | PROD activation task: DEV warehouse → `TBRDP_DW_PROD_XS_WH` | Low: settings only |
| 02 | `02_partner_share_loads.sql` | 6 E15/Eventellect loads → one PROD procedure + 6 PROD tasks, loading share → PROD directly in one atomic step | Low: same data, and overlap is harmless |
| 03 | `03_ai_budget_tasks.sql` | AI budget cap → `GOVERNANCE.AI_BUDGET`, user list in a table, no ACCOUNTADMIN | Low. Also decide whether the cap is needed at ~$2.50/mo. |
| 04 | `04_webull_push.sql` | WeBull procedure → PROD, reading the PROD view, errors raised | Medium: Salesforce writes, and the stream must have one reader only |
| 05 | `05_salesforce_account_upsert.sql` | Account upsert → PROD task on the PROD warehouse, PROD log table, errors raised | Medium–high: hourly Salesforce writes, so it must never run twice |

Each script has its own switch-over and roll-back steps. The pattern is the same throughout: create the new task paused, pause the old one, start the new one, watch the first run, and drop the old one after about 2 weeks with the owner's OK.

## Blocked on

- **Service roles** (`<PROD_SERVICE_ROLE>`, `<ADMIN_SERVICE_ROLE>`) and a **failure-alert integration** (Foundations items).
- **DEV access for our analysis role**, to read the external-access integration and secret names (`DESCRIBE PROCEDURE`) and the log table's columns.
- **Owner answers:** team questions 7, 8 and 10, and the clean-room owner for the 5-minute schedule.
