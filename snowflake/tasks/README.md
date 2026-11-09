# Snowflake tasks

One `.sql` file per scheduled task (`CREATE OR REPLACE TASK ...`). As of Nov 2026 there are ~39 tasks, none of which are in Git yet — add each one's DDL here as it gets touched.

Every new or changed task needs: a schedule, a non-ACCOUNTADMIN owner, a failure alert, and fully qualified object names.
