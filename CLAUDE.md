# CLAUDE.md — Rays Data Platform

Guidance for Claude Code in this repo. The repo owner is new to these tools: explain things in plain language, define jargon on first use, and mark anything inferred from names or partial data as **(guess)**.

## The stack

All facts below are from the Nov 5, 2026 inventory in `docs/current-state/`.

- **Fivetran** — managed data copying. 24 connectors (13 running) land raw data in Snowflake's `FIVETRAN_DATABASE`: MLB ticketing (gcp_tdc_*), Wheelhouse fan data, Salesforce CRM, plus three custom-code connectors the team maintains (Mashgin concessions, ParkHub parking, MLB GUMBO game feed).
- **Partner shares** — E15/Levy (concessions, suites, retail), Eventellect (ticket resale, forecasts), and Nielsen share data directly into Snowflake; scheduled Snowflake jobs copy it into LOAD tables. These jobs currently run from DEV (known issue).
- **Snowflake** — the warehouse. Scheduled tasks and ~78 team-built stored procedures (SQL and Python) handle loads, forecasts, Salesforce pushes, fan-survey AI, and cost controls.
- **Coalesce** — transformation tool that rebuilds STAGE → ODS → DATALAKE → EDW on timers (15-min, 30-min, 2-hour, several daily), in DEV, QA, and PROD. Its code lives in GitHub at `cboone-rays/Coalesce` (confirmed Nov 18, 2026: one YAML file per node/job). Each Coalesce **workspace is its own git branch** (`CB_WORKSPACE` = Chris, `CC_init` = Caroline). See "Pipeline and cost review" below.
- **Webull clean room** — a Snowflake "Data Clean Rooms" (Samooha) app matching Rays fans to Webull customers without sharing raw data. Set up by Snowflake; no internal owner yet. It reads a **DEV** view, so DEV changes affect what the partner sees.
- **Salesforce** — the CRM. Snowflake writes to it (hourly accounts, daily ticket purchases, daily Webull flags, ad hoc B2B lead imports) and reads it back via Fivetran. Writes trigger Salesforce automations — see "Salesforce side effects" below.
- **Tableau Cloud** — dashboards. 78 published data sources query Snowflake live (all via personal logins), 10 read BigQuery directly, 8 read uploaded files, 21 still point at the old SQL Server.
- **Airflow** — something called `AIRFLOW_SVC` queries PROD; owner unknown. Its 4 DAGs (Nov 18, 2026):
  - `voc_hourly_parent` (hourly, active): starts DEV `VOC_HOURLY_RUN` only when new VOC data has landed. It runs about 8 times a day.
  - `voc_hourly_run`: the child DAG it triggers.
  - `coalesce_snowflake_pipeline`: paused since July; it called PROD DAILY.
  - `coalesce_test`: paused.

  Not used as an orchestrator today.
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
- Why does QA refresh on a schedule? Do the clean-room activation tables need 5-minute updates? Who owns the DEV-stored tasks that load PROD data? The full question list with best guesses is in `team_questions.md` (see below).
- What are DataPrism and Evolute (unknown apps inside Salesforce)? What does StellarAlgo export?
- Where does the Mashgin/ParkHub/GUMBO connector code live? Is it in any Git?
- ~~Where is Coalesce's Git repo?~~ Answered: `cboone-rays/Coalesce` on GitHub.
- When does the Microsoft Graph email app secret expire?
- ~~Why does the DEV `VOC_HOURLY_RUN` still run though its schedule is paused?~~ Answered: the Airflow DAG `voc_hourly_parent` starts it through the Coalesce API.
- Which numbers are right where the two inventory files disagree (878 vs ~8,607 total procedures; 14 vs ~37 test copies)?

## Pipeline and cost review (Nov 18–19, 2026)

Read-only review of Coalesce, Fivetran, Airflow and Snowflake billing. Unless marked **(estimate)** or **(guess)**, figures come from Coalesce run logs, Snowflake `ACCOUNT_USAGE` / `ORGANIZATION_USAGE`, Fivetran's API and the Coalesce repo.

**Environments and deploys**
- All three environments were on Coalesce commit `24e47b2` as of Nov 18.
- `main` already had a newer commit, `4c6a4d4`, that wasn't deployed.
- Deploys go DEV → QA → PROD within minutes, by one person (on Nov 18, QA to PROD took 29 seconds). There's no review or QA test run.
- Coalesce doesn't support pull requests itself. Merges happen in its Git window, so nothing goes through review on GitHub.
- All three environments read the same raw `FIVETRAN_DATABASE`.

**Coalesce jobs (PROD)**

| Job | ID | Nodes | Status |
|---|---|---:|---|
| 15 MIN | 3 | 355 | live |
| 30 MIN | 6 | 253 | live |
| 2 Hour | 5 | 134 | live |
| DAILY | 2 | 462 | live |
| Post Game | 10 | 111 | live |
| CP Sales | 8 | — | live |
| Asset Inventory | 7 | — | live |
| VOC | 9 | — | paused since Oct 5 (duplicate rows in `SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI`) |
| Hourly | 4 | 456 | QA only |
| AIRFLOW ODS TDC 15 MIN | 11 | — | never runs |

- 15 MIN, 30 MIN and 2 Hour all start at :00. At :00 and :30 more queries wait than run: 307 queued hours vs 272 execution hours per week on `TBRDP_DW_PROD_S_WH`.
- 15 MIN typically takes 5.3 min; the slowest run was 12.9 min.
- **Full rebuilds:** 55 stage nodes reread whole raw tables each run.
  - The biggest repeated rebuilds: seat availability, 33M rows every 30 min; last-listed price, 16M + 14M rows every 15 min; item payment, scan attending patron and suite grid.
  - Post-season tables still rebuild every 15 min in November.
- **Overlap:** 91 tables are built by 2+ jobs, e.g. TICKET in 2 Hour and DAILY, which caused 12 failed runs on Oct 29.
- 402 nodes are in no job.
- The 15 MIN and Hourly selectors reference a missing subgraph, `PRICEBOOK_ENTRY`.
- DAILY still rebuilds tables from paused connectors (`gcp_wheelhouse`, `gcp_wheelhouse_mid`).
- `E15_LEVY_PREMIUM_LOAD` hasn't updated in 267 days.

**DEV and QA**
- **QA** refreshes all day (Hourly job 4 plus the 2 Hour and daily jobs) on the **DEV** warehouse, using the DEV role.
  - That's about $8.6K/yr at the off-season pace.
  - Nobody reads QA except the pipeline and SYNQ (the data-quality monitoring tool).
- **DEV** isn't kept like PROD: none of the core jobs ran there in 56 days. But it **hosts live processes**:
  - The E15/Levy (4 tasks, every 12 h) and Eventellect (every 2 h, daily) load tasks are stored in DEV and run on `TBRDP_DW_DEV_XS_WH`. They **write directly into `TBRDP_DW_PROD.LOAD`**, even though their parameters say DEV. There are no PROD copies of these tasks.
  - The PROD task `TRIGGER_WEBULL_OVERLAP_PUSH` calls a DEV procedure.
  - `SALESFORCE_ACCOUNT_UPSERT_PRODUCTION` runs hourly on `TBRDP_DW_QA_XS_WH`.
  - The PROD and DEV activation-summary tasks run every 5 min on the DEV warehouse. They do about 3 seconds of work each but wake the warehouse 288 times a day (≈ $4.9K/yr).
  - Other DEV tasks: AI budget control (`CREDIT_AI_SERVICE_USAGE_DAILY` hourly, `RESTORE_AI_SERVICES_ACCESS_DAILY`), and turning the VOC Cortex Search service on and off.
- Tableau lists 30 workbooks connected to `TBRDP_DW_DEV`, but only 4 days of DEV reads were seen in 30 days.
- **Every pipeline query in all three environments runs as one person's personal Snowflake login.**

**Fivetran → Coalesce trigger**
- Tested in QA on Nov 18: the job started 4 s after a `gcp_wheelhouse_voc` sync.
- Facts so far:
  - The trigger is free.
  - It fires after every sync, even when no data changed.
  - It fires once per attached connector.
  - It runs under the token owner's login and warehouse.
- Not yet tested: an empty sync, a failed run, a trigger while the job is already running, and the Jobs tab for chaining jobs.
- Plan:
  - VOC first.
  - Then 2 Hour, triggered by `purchase_considerations`, `wallet_transactions`, `parking_parkhub` and `gcp_wheelhouse_fast`. Remove TICKET from 2 Hour first.
  - Then 15 MIN, from `gcp_tdc_fast` only.
  - Then 30 MIN, chained after 15 MIN.
  - Keep the daily jobs on the clock.
- The benefit is freshness and less queueing, not money.

**Snowflake spend and contract**
- Contract 263641 ran Nov 14, 2025 – Nov 13, 2026: $50K, plus top-ups of $22.5K and $70K, plus $3.5K free.
- The prepaid ran out **Oct 20**. Everything since then is billed at the $3.00 list price; the contract price was $2.82 (6% off).
- Last contract year cost ≈ $149.5K (~54,100 credits).
- The last 30 days were ≈ $9.2K: $6.7K for this account (PEA85016) and $2.4K for `TBR_BBOPS` (baseball ops).
- Cloud services overage (≈ $5.8K/yr) and Trust Center scans (≈ $4.1K/yr) are notable.
- AI functions are negligible (~$2.50/mo). The VOC "CORTEX_AI" node calls no AI function.
- **Avoidable waste (estimate):** ≈ $18K–27K/yr at $3.00. The biggest pieces:
  - pause QA schedules: $7–8K;
  - run the activation tasks hourly: $3.8–4.5K;
  - big rebuilds: $2.6–5.2K;
  - cloud services: $2.3–3.5K;
  - Trust Center: $1–3K.
- **Renewal (Snowflake email, Nov 13):** a $100K annual renewal under the MLB league deal.
  - 20% off ($2.40 per credit), November overage rolled in.
  - Expected 3-year term with credit rollover; signature targeted end of November.
  - Separate business/baseball budgets. Chris and Caroline own the budget-split action item.
- **Renewal sizing (estimate):**
  - League deal ≈ $130K/yr at current usage, or $108K–115K with the fixes.
  - Business side alone ≈ $73K–81K, baseball ≈ $35K.
  - Suggested counter: stay at $100K, but ask for overage or mid-term top-ups at $2.40, rollover in writing, a 3-year price hold, and confirmation of what $100K covers.

**Proposed change workflow**
- Keep personal workspaces. Commit and push in Coalesce.
- A GitHub Action then:
  - auto-opens a pull request;
  - runs an AI review and a QA deploy plus affected-job test;
  - notifies the reviewer in Teams/Slack;
  - auto-merges after one approval;
  - auto-deploys PROD with a service account;
  - confirms the first PROD run.
- About 7 min of people time per change, vs about 10 today with no test or review (estimate).
- Prerequisites:
  - move the Coalesce repo to a GitHub org;
  - Snowflake and Coalesce service accounts (Environment Admin is needed to deploy);
  - a CLI config stored as GitHub secrets (`coa plan` / `coa deploy` / `coa refresh`).

**Analysis files.** These aren't in this repo. They're local, git-excluded files in the Coalesce worktree folder `.claude/worktrees/data-pipeline-coalesce-audit-946ec6/analysis_out/`:

| File | Contents |
|---|---|
| `next_steps.md`, `next_steps_checklist.html` | The ordered to-do list |
| `team_questions.md` | 27 questions, each with a best-guess answer |
| `dev_qa_operating_plan.md` | DEV/QA findings and target setup |
| `fivetran_trigger_plan.md` | Trigger rollout plan |
| `inefficiencies.md`, `node_job_matrix.csv` | PROD pipeline findings |
| `spend_and_savings.html`, `snowflake_yearly_spend.md`, `waste_estimate.md` | Costs and savings |
| `change_process.html` | Today vs proposed workflow, effort timeline, setup walkthrough |
| `current_state.html` | Picture of the pipeline today |

## Repo layout

- `docs/current-state/` — the Nov 2026 inventory (xlsx + html) and `summary.md`
- `docs/future-state/` — proposals; `docs/decisions/` — decision records
- `snowflake/` — `tasks/`, `procedures/`, `roles/`, `adhoc/` (SQL kept for review)
- `fivetran/custom-connectors/` — Mashgin/ParkHub/GUMBO code (placeholder)
- `salesforce/` — write side-effect notes; `tableau/` — data source and refresh notes
- `coalesce/` — pointer to Coalesce's own repo (`cboone-rays/Coalesce`)

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
