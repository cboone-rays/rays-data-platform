# Snowflake

SQL for Snowflake objects the team owns, kept in Git so changes are reviewable.

- `tasks/` — scheduled task definitions
- `procedures/` — stored procedure source
- `roles/` — role and grant scripts
- `adhoc/` — one-off investigation / fix scripts (dated)

Convention: DEV → QA → PROD, fully qualified names, no DEV references from PROD, failure alerts and a non-ACCOUNTADMIN owner on every new task. See `CLAUDE.md` at the repo root.
