# The Rays data stack, in plain language

As of **November 5, 2026**. Sources: `current_state_processes.xlsx` and `rays_data_stack_2.html` in this folder. Anything marked **(guess)** was inferred from names or partial data, not confirmed.

## The stack in one paragraph

Data about tickets, fans, concessions, parking, and sales flows into **Snowflake**, our cloud data warehouse. **Fivetran** (a managed copying service) brings in most of it: MLB ticketing data, Salesforce CRM, Mashgin concessions, ParkHub parking. Partners like E15/Levy and Eventellect share data directly into Snowflake, loaded by scheduled Snowflake jobs. **Coalesce** (a transformation tool) rebuilds the warehouse's cleaned and combined tables on timers all day. **Tableau Cloud** dashboards read the results. Snowflake also writes *back* to **Salesforce** (account updates hourly, ticket purchases daily, Webull flags, lead imports), and each write sets off Salesforce's own automations. A Snowflake "clean room" matches Rays fans with **Webull** customers without either side seeing the other's raw data. An unknown **Airflow** server also queries the warehouse, and the **old SQL Server** (`sqldwag`) still reads live data from it.

In total: **115 automated processes** — 72 running, 11 broken, 28 turned off, 4 not yet mapped.

## The ten problems worth raising first

1. **Nobody is told when a job fails.** Zero Snowflake jobs alert anyone. The data-quality checks have been broken for ~11 months; 7 jobs stopped after errors without anyone noticing. *Fix: days.*
2. **Live work runs in the test area (DEV).** The hourly Salesforce update and all E15/Levy/Eventellect loading run in DEV, where a test change can break live data. *Fix: weeks.*
3. **Salesforce logins are scattered.** Jobs write to Salesforce with 5 different stored logins, one named for a person. *Fix: weeks.*
4. **Most jobs run as the top admin.** 28 of 39 Snowflake jobs run as ACCOUNTADMIN, which can change anything in the account. *Fix: days.*
5. **No single scheduler.** Fivetran, Coalesce, and Snowflake each run on their own clocks — nothing waits for the step before it. Coalesce's overlapping timers write ~900 million rows an hour, mostly full reloads of staging tables. Biggest cost lever in the stack. *Fix: months (an orchestrator + incremental loads).*
6. **Several hand-built paths into Salesforce** (accounts, tickets, Webull flags, leads), each with its own code. *Fix: months (consolidate).*
7. **Broken or abandoned jobs everywhere.** 3 jobs can't run at all, 11 Fivetran connectors are paused (2 never worked), ~14 test/debug copies of code remain (the Stored procedures tab marks ~37 procedures as test or old — the counts disagree). *Fix: days.*
8. **Personal logins run the stack.** ~6.6M Coalesce queries a month under one person's login; all 78 live Tableau-to-Snowflake connections use personal logins. One expired Nov 3 and took down a finance dashboard. *Fix: days (service accounts).*
9. **QA and DEV copy the live schedule**, refreshing on timers nobody needs, including two jobs already paused in PROD. *Fix: days.*
10. **Tableau clutter.** 42 of 128 published data sources unviewed in a year; 28 point at the old SQL Server/KORE; one extract has been stale for 7 months and is still viewed. *Fix: days.*

Also worth knowing: a few stored procedures have **credentials typed directly into their code** (a Salesforce client secret, one person's Salesforce login, a Mashgin API token). Rotating those and moving them into Snowflake secrets is called out in the inventory.

## Still to check (places that may hide more processes)

- **Salesforce:** failing/paused Flow interviews; Apex triggers list; scheduled jobs; which systems log in (Connected Apps OAuth usage).
- **Coalesce:** what each schedule refreshes and who gets alert emails.
- **Tableau:** extract refresh schedules (admin-only — ask the Tableau admin).
- **People:** who runs Airflow (`AIRFLOW_SVC`); what still depends on the old SQL Server (`sqldwag`).
- **Fivetran:** transformations, Activations, notification settings.
- **Snowflake:** everything that connects (sessions by application); pipes/streams/dynamic tables/alerts/Streamlits; external integrations.
- **Partners:** the Eventellect file drop mentioned in Teams; how the Webull clean room works (ask Snowflake — they set it up).
- **Microsoft:** Power Automate flows; expiry date of the email app secret (ask IT).
- **MLB/Google:** who manages the BigQuery data Tableau reads directly.

Note: the xlsx marks the Salesforce Flows and Coalesce schedule checks "DONE Nov 5" in their descriptions but their Status column still says "Not started" — the descriptions appear to be right.
