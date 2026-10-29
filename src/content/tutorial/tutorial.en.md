---
title: 'UOMP SDK/CLI Tutorial'
description: 'Complete guide from zero to deployed'
---

# UOMP SDK/CLI Tutorial

A complete walkthrough: install CLI, import data, authorize Agents, write Agents with the SDK, deploy remote mode, and connect to cloud services.

## Prerequisites

- Node.js >= 22
- git
- Optional: pnpm 9 (only for running from source)

## 1. Install & Initialize

```bash
curl -fsSL https://www.uomp.org/install.sh | bash
uomp init
```

The installer clones UOMP into `~/.uomp/cli`, builds the CLI, and links it to `~/.local/bin/uomp`.

From a source checkout:

```bash
git clone https://github.com/0xSynapse/uomp-core.git
cd uomp-core
pnpm install
pnpm build
pnpm cli init
```

Then replace `uomp` with `pnpm cli` throughout this tutorial.

`uomp init` creates the Memory Store, Auth DB, Audit DB, Ed25519 key pair, and `sessions/` directory under `~/.uomp`.

## 2. Import Data

Start with an Obsidian vault or a Markdown folder:

```bash
# Recursive import; skips .obsidian and hidden directories
uomp import ~/Obsidian/MyVault

# Preview without writing
uomp import ~/Obsidian/MyVault --dry-run
```

Directory paths become scopes: `projects/uomp/plan.md` is tagged `notes`, `notes/projects`, and `notes/projects/uomp`. Re-importing upserts by key instead of duplicating items.

CSV and JSON are still supported:

```bash
uomp import ./examples/stock-analyst/sample-risk.json --replace

uomp import ./examples/stock-analyst/sample-holdings.csv \
  --tag portfolio:holdings \
  --sensitivity high \
  --replace
```

## 3. Start Auth + Guard

The simplest path is to let `authorize` start the embedded server: keep that terminal open, then run the agent in another terminal.

If you prefer a separate process:

```bash
# Terminal 1
uomp serve
```

The service listens on `http://127.0.0.1:9374`.

## 4. Authorize an Agent

```bash
uomp authorize ./examples/stock-analyst \
  --scope portfolio:holdings profile:risk
```

The CLI creates a session and writes the token to `~/.uomp/sessions/<sessionId>.env` with mode `0600`. Output looks like:

```text
Session granted: sess_...
  Agent     Stock Analyst (stock-analyst)
  Scope     portfolio:holdings, profile:risk
  Expires   2026-10-29 10:30 (30 min)

Env file
  /home/me/.uomp/sessions/sess_....env

Open a new terminal, then:
  source '/home/me/.uomp/sessions/sess_....env'
  node '/path/to/agent/index.js'

Revoke with: uomp revoke sess_...
```

The full JWT is not printed by default. Use `--print-token` when you need to copy it, or `--output` to write the env file somewhere else.

## 5. Write an Agent with the SDK

```ts
import { UompClient } from '@uomp/sdk';

// One line — auto-reads UOM_TOKEN + UOMP_BASE_URL from env
const uomp = UompClient.fromEnv();

const holdings = await uomp.memory.getByTag('portfolio:holdings');
const risk = await uomp.memory.getByTag('profile:risk');

const total = await uomp.aggregate.sum(
  'portfolio:holdings',
  'value.market_value'
);

const payloadId = await uomp.payload.upload(report);
await uomp.session.submitDeletionProof();
const logs = await uomp.audit.query({ limit: 10 });
```

## 6. Run the Agent

In another terminal, source the env file printed by the CLI, then run the agent:

```bash
source ~/.uomp/sessions/<sessionId>.env
node ./examples/stock-analyst/index.js
```

## 7. Connect Claude Desktop / Cursor (Experimental)

The CLI includes a stdio MCP server with `list_memory` and `read_memory`. Create a dedicated session env file:

```bash
uomp authorize ./examples/mcp-client \
  --scope notes/projects \
  --output ~/.uomp/mcp-client.env
```

Generate the client config:

```bash
uomp mcp --session ~/.uomp/mcp-client.env --print-config
```

Paste the output into your client config. It looks like:

```json
{
  "mcpServers": {
    "uomp": {
      "command": "/usr/local/bin/node",
      "args": [
        "/home/me/.uomp/cli/src/packages/cli/dist/cli.js",
        "mcp",
        "--session",
        "/home/me/.uomp/mcp-client.env"
      ]
    }
  }
}
```

Restart the client, then ask it to list notes under `notes/projects` and read one. Every call still goes through Memory Guard; denied reads are returned to the client and written to the audit log.

The env file is read when the MCP server starts. After the session expires or is revoked, re-run `uomp authorize` and restart the MCP server.

## 8. Remote Gateway Mode (Advanced / Preview)

> Gateway is an advanced capability and is not on the core CLI path. The default local workflow does not need it.

One command, no public IP needed:

```bash
uomp gateway start
# ═══ Public Gateway URL ═══
#   https://xxx.trycloudflare.com
```

## 9. Use the DO Cloud Agent

```bash
# Browser
https://uomp-stock-analyst-mvblm.ondigitalocean.app

# API
curl -X POST https://uomp-stock-analyst-mvblm.ondigitalocean.app/analyze \
  -H 'Content-Type: application/json' \
  -d '{"token":"your_token","gateway_url":"your_gateway"}'
```

## 10. Sessions & Audit

```bash
# Active sessions
uomp sessions

# Audit log
uomp audit --limit 20

# Revoke; the default env file is removed too
uomp revoke <session-id>
```

## SDK Quick Reference

| Client | Method | Description |
|--------|--------|-------------|
| `uomp.memory` | `get(key)` | Read single item by key |
| `uomp.memory` | `getByTag(tag)` | Read all items by tag |
| `uomp.memory` | `getByKeys(keys)` | Batch read by keys |
| `uomp.aggregate` | `sum/avg/count/min/max` | Aggregate without raw data |
| `uomp.payload` | `upload(data)` | Upload payload to Gateway |
| `uomp.payload` | `download(id)` | Download payload |
| `uomp.session` | `submitDeletionProof()` | Submit deletion proof |
| `uomp.session` | `refresh(refreshToken)` | Refresh Token |
| `uomp.audit` | `query({limit})` | Query audit logs |

## CLI Quick Reference

Core path:

| Command | Description |
|---------|-------------|
| `uomp init` | Initialize the data directory |
| `uomp import <path>` | Import a Markdown folder or CSV/JSON file |
| `uomp authorize <agent>` | Create a session and write a 0600 env file |
| `uomp serve` | Start Auth + Guard as a standalone process |
| `uomp mcp --session <id>` | Start the stdio MCP server (experimental) |
| `uomp sessions` | View active sessions |
| `uomp audit --limit 20` | View audit logs |
| `uomp revoke <id>` | Revoke a session and remove its default env file |

Advanced commands are hidden from help but still callable: `memory`, `registry`, `discover`, `connect`, `agent`, `gateway`.
