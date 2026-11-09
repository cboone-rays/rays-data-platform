# Tableau

Notes on Tableau Cloud data sources and refreshes.

What we know (Nov 2026): 128 published data sources — 78 query Snowflake live (all via personal logins; no service account), 10 read BigQuery, 8 read uploaded files, 21 point at the old SQL Server / KORE. ~34 workbook extracts refresh on schedules only admins can see, timed near (not after) Coalesce refreshes. One extract ("Trade Item Notes (Prod)") has been stale since April 2026 and is still viewed.

Document here: which data source feeds which dashboard, refresh schedules once the Tableau admin shares them, and the move to a Snowflake service account for Tableau.
