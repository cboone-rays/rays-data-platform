# CLAUDE.md — Rays Data Platform

Guidance for Claude Code in this repo. The repo owner is new to these tools: explain things in plain language, define jargon on first use, and mark anything inferred from names or partial data as **(guess)**.

## The stack

All facts below are from the Nov 5, 2026 inventory in `docs/current-state/`.

- **Fivetran** — managed data copying. 24 connectors (13 running) land raw data in Snowflake's `FIVETRAN_DATABASE`: MLB ticketing (gcp_tdc_*), Wheelhouse fan data, Salesforce CRM, plus three custom-code connectors the team maintains (Mashgin concessions, ParkHub parking, MLB GUMBO game feed).
- **Partner shares** — E15/Levy (concessions, suites, retail), Eventellect (ticket resale, forecasts), and Nielsen share data directly into Snowflake; scheduled Snowflake jobs copy it into LOAD tables. These jobs currently run from DEV (known issue).
- **Snowflake** — the warehouse. Scheduled tasks and ~78 team-built stored procedures (SQL and Python) handle loads, forecasts, Salesforce pushes, fan-survey AI, and cost controls.
- **Coalesce** — transformation tool that rebuilds STAGE → ODS → DATALAKE → EDW on timers (15-min, 30-min, 2-hour, several daily), in DEV, QA, and PROD. Its code likely lives in Coalesce's own Git repo **(guess)** — see `coalesce/README.md`.
- **Webull clean room** — a Snowflake "Data Clean Rooms" (Samooha) app matching Rays fans to Webull customers without sharing raw data. Set up by Snowflake; no internal owner yet. It reads a **DEV** view, so DEV changes affect what the partner sees.
- **Salesforce** — the CRM. Snowflake writes to it (hourly accounts, daily ticket purchases, daily Webull flags, ad hoc B2B lead imports) and reads it back via Fivetran. Writes trigger Salesforce automations — see "Salesforce side effects" below.
- **Tableau Cloud** — dashboards. 78 published data sources query Snowflake live (all via personal logins), 10 read BigQuery directly, 8 read uploaded files, 21 still point at the old SQL Server.
- **Airflow** — something called `AIRFLOW_SVC` queries PROD; owner unknown. May become the orchestrator.
- **Old SQL Server** (`sqldwag`) — the previous warehouse, still reading live data from Snowflake PROD via a linked server. Unknown what depends on it.

Flow in one line: sources → Fivetran / shares → Snowflake (LOAD) → Coalesce (STAGE → ODS → DATALAKE → EDW → IM_RPT) → Tableau, Salesforce writes, emails.

## Snowflake layout

- **Databases:** `TBRDP_DW_PROD` (live — reports and Tableau read here), `TBRDP_DW_QA`, `TBRDP_DW_DEV` (test — but currently also runs live jobs: known issue). Plus `FIVETRAN_DATABASE` (raw landed data), `GOVERNANCE` (cost tracking, tags/policies), partner shares (`SHR_E15_RAYS`, `EVENTELLECT__…`, `NIELSEN_…`), and `SAMOOHA…` clean-room databases.
- **Schema build path, in each DW database:**
  `LOAD` (landed files/shares) → `STAGE` (Coalesce working tables, `STG_…`, wiped each run) → `ODS` (one cleaned copy per source table, `ODS_<SOURCE>_…`) → `DATALAKE` (business-ready combined tables, `SBL_…`) → `EDW` (star schema: `DIM_…`, `FACT_…`) → `IM_RPT` (report views, `V_…`, mostly thin wrappers).
- `SANDBOX` schemas are for ad hoc work, but PROD's currently hosts the live B2B lead-import app and ticket-purchase upsert (known issue).

## Key scheduled jobs

- Hourly: Salesforce account upsert (`SALESFORCE_ACCOUNT_UPSERT_PRODUCTION`, runs from DEV as ACCOUNTADMIN).
- Daily: ticket purchases → Salesforce (1 AM), Webull clean-room analysis (4 AM), Webull flags → Salesforce (6 AM), Snowflake spend email (7 AM), ticket sales forecast (~10:36 AM).
- Every 5 minutes: two Webull clean-room result refreshes (PROD + a DEV copy).
- Coalesce: 15-min, 30-min, 2-hour, and daily refreshes in PROD, with QA/DEV copies on similar timers.
- Every 2 hours: Eventellect load; twice daily: E15/Levy loads (all from DEV).

## Salesforce side effects

Writing to Salesforce is never free. Every Account save fires 3 Apex triggers (`AccountBefore`, `LogAccountChange` — possibly logging every account every hour — and a DLRS rollup); 7 Flows fire only on specific field changes. Ticket-purchase saves fire a rollup trigger. B2B lead imports may fire Contact/Lead/Opportunity automations (9 Flows + 5 triggers on Opportunity alone). Full list: "Salesforce detail" tab in the inventory. Never widen a Salesforce write without checking that tab.

## Top 10 known issues (short form)

1. No failure alerts anywhere; data-quality checks broken ~11 months.
2. Live jobs run in DEV (Salesforce upsert, all E15/Levy/Eventellect loads).
3. Five different Salesforce logins, one named for a person.
4. 28 of 39 Snowflake jobs run as ACCOUNTADMIN.
5. No orchestrator — overlapping timers write ~900M rows/hour, mostly full reloads.
6. Several hand-built paths into Salesforce.
7. Broken/abandoned jobs and test copies everywhere.
8. Personal logins run Coalesce (~6.6M queries/month) and all live Tableau connections.
9. QA/DEV refresh on live-like schedules for no one.
10. Tableau clutter: 42 of 128 sources unviewed in a year, stale extracts.

Details and effort estimates: `docs/current-state/summary.md`.

## Open questions

- Who owns/runs Airflow (`AIRFLOW_SVC`)? What still depends on `sqldwag`?
- What are DataPrism and Evolute (unknown apps inside Salesforce)? What does StellarAlgo export?
- Where does the Mashgin/ParkHub/GUMBO connector code live? Is it in any Git?
- Where is Coalesce's Git repo? **(guess that it exists)**
- When does the Microsoft Graph email app secret expire?
- Why does the DEV `VOC_HOURLY_RUN` still run though its schedule is paused?
- Which numbers are right where the two inventory files disagree (878 vs ~8,607 total procedures; 14 vs ~37 test copies)?

## Repo layout

- `docs/current-state/` — the Nov 2026 inventory (xlsx + html) and `summary.md`
- `docs/future-state/` — proposals; `docs/decisions/` — decision records
- `snowflake/` — `tasks/`, `procedures/`, `roles/`, `adhoc/` (SQL kept for review)
- `fivetran/custom-connectors/` — Mashgin/ParkHub/GUMBO code (placeholder)
- `salesforce/` — write side-effect notes; `tableau/` — data source and refresh notes
- `coalesce/` — pointer to Coalesce's own repo once confirmed

## Conventions for new code

- Build in DEV, verify in QA, promote to PROD. Live jobs, data, and code belong in PROD only.
- Always use fully qualified names (`DATABASE.SCHEMA.OBJECT`). Never reference DEV objects from PROD.
- Every new task gets: a failure alert, a non-ACCOUNTADMIN owner role, a schedule with a reason, and its DDL committed to `snowflake/tasks/`.
- Prefer incremental loads over full reloads.
- Secrets live in Snowflake secrets or environment config — never in code, never in Git.

## Working rules for Claude Code

1. **Read-only by default.** No DDL/DML, no task create/alter/resume/suspend, no Salesforce writes without the repo owner's explicit approval in that conversation. Write proposed SQL to files (e.g. `snowflake/adhoc/`) for review instead of executing it.
2. **Never use ACCOUNTADMIN in new code.** If something seems to need it, stop and say why.
3. **Treat cleanup lists as candidates, not decisions.** "Delete" in the inventory means "confirm with an owner, then delete" — never act on it directly.
4. **Never commit secrets** — no passwords, tokens, keys, or connection strings, even in examples. `.gitignore` is a backstop, not permission.
5. **Explain in plain language.** The owner is new to Snowflake, Fivetran, Coalesce, Salesforce, and Tableau. Say what a thing is before using its jargon.
6. **Mark guesses.** Anything inferred from names or partial data gets an explicit "(guess)".
