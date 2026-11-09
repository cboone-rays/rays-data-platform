# Salesforce

Notes on the automations inside Salesforce that fire when Snowflake writes to it. Snowflake is not just reporting on Salesforce — it writes back, and those writes set things off.

Known side effects of our writes (from the Nov 2026 inventory):

- **Hourly account upsert** → 3 Apex triggers run on every Account save (`AccountBefore`, `LogAccountChange`, `dlrs_AccountTrigger`); 7 Flows run only when specific fields change. `LogAccountChange` may be writing a log row per account per hour.
- **Daily ticket purchase upsert** → the DLRS rollup trigger fires per record.
- **B2B lead import** → may fire Contact, Lead, and Opportunity automations (2 Flows + 2 triggers on Contact; 9 Flows + 5 triggers on Opportunity).

Full list: "Salesforce detail" tab of `docs/current-state/current_state_processes.xlsx`. Before adding or widening any write to Salesforce, check that tab and confirm with the Salesforce admin.
