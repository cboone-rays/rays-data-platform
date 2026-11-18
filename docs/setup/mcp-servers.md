# Fivetran and Coalesce tools for Claude Code

`.mcp.json` at the repo root tells Claude Code how to start two extra tool
servers (MCP servers — small programs that let Claude call another service):

| Name | What it reaches | Key it needs |
|---|---|---|
| `coalesce-transform` | Coalesce's hosted server at `app.coalescesoftware.io`, through the `mcp-remote` bridge | `COALESCE_AUTH` — the full value of the `Authorization` header, exactly as in the Claude desktop app's config (include any `Bearer ` prefix) |
| `fivetran` | Fivetran's API at `api.fivetran.com`, using Fivetran's open-source `fivetran-mcp` | The variable names `fivetran-mcp` reads (copy the names from the `env` section of the desktop app's config) |

The file holds **no keys**. Keys come from environment variables at start-up.

## Cloud sessions (claude.ai/code)

In the cloud environment's settings (environment menu in the session title bar → Edit):

1. **Environment variables:** add `COALESCE_AUTH` and the Fivetran variables.
2. **Network access:** allow `app.coalescesoftware.io` and `api.fivetran.com`;
   keep package managers allowed (the servers download from npm, PyPI and GitHub).
3. Start a new session.

Anyone who can use the environment, and any command run in its sessions, can
read these variables. Use read-only keys.

## Local sessions (Windows)

These two servers are already set up in your own Claude Code user settings
(`C:\Users\<you>\.claude.json`). When a local session asks whether to enable the
servers from this repo's `.mcp.json`, **decline** — the user-level ones already
work, and this file's version is written for the cloud (Linux) machine.

## Known follow-ups

- Both servers download their latest version each time they start (`npx -y`,
  `uvx --from git+…`). Pin versions once things are stable.
