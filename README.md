# rays-data-platform

Data engineering work for the Tampa Bay Rays business data stack: Fivetran → Snowflake → Coalesce → Salesforce / Tableau, plus the Webull clean room and the legacy SQL Server.

This repo is the single home for code, documentation, and decisions across that stack. Start with `CLAUDE.md` (stack overview and working rules) and `docs/current-state/summary.md` (plain-language state of the world as of Nov 5, 2026).

## Layout

| Folder | What's in it |
|---|---|
| `docs/current-state/` | The Nov 2026 process inventory and its summary |
| `docs/future-state/` | Proposals (empty for now) |
| `docs/decisions/` | Short decision records (empty for now) |
| `snowflake/` | Tasks, procedures, roles, and ad hoc SQL |
| `fivetran/custom-connectors/` | Mashgin, ParkHub, GUMBO connector code (placeholder) |
| `salesforce/` | Notes on automations our Snowflake writes set off |
| `tableau/` | Data source and refresh notes |
| `coalesce/` | Pointer to Coalesce's own repo (once confirmed) |

No secrets in Git, ever — see `.gitignore` and the working rules in `CLAUDE.md`.
