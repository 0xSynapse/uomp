---
title: 'UOMP SDK/CLI Tutorial'
description: 'Complete guide from zero to deployed'
---

# UOMP SDK/CLI Tutorial

A complete walkthrough: install CLI, import data, authorize Agents, write Agents with the SDK, deploy remote mode, and connect to cloud services.

## Prerequisites

- Node.js >= 22
- pnpm 9 (`corepack enable` or `npm install -g pnpm@9`)
- Clone [uomp-core](https://github.com/0xSynapse/uomp-core)

## 1. Install & Initialize

```bash
pnpm install
pnpm build
pnpm cli init
```

`pnpm cli init` creates the Memory Store, Auth DB, Audit DB, Ed25519 key pair, and `sessions/` directory under `~/.uomp`.

## 2. Import Data

Start with an Obsidian vault or a Markdown folder:

```bash
# Recursive import; skips .obsidian and hidden directories
pnpm cli import ~/Obsidian/MyVault

# Preview without writing
pnpm cli import ~/Obsidian/MyVault --dry-run
```

Directory paths become scopes: `projects/uomp/plan.md` is tagged `notes`, `notes/projects`, and `notes/projects/uomp`. Re-importing upserts by key instead of duplicating items.

CSV and JSON are still supported:

```bash
pnpm cli import ./examples/stock-analyst/sample-risk.json --replace

pnpm cli import ./examples/stock-analyst/sample-holdings.csv \
  --tag portfolio:holdings \
  --sensitivity high \
  --replace
```

## 3. Start Auth + Guard

The simplest path is to let `authorize` start the embedded server: keep that terminal open, then run the agent in another terminal.

If you prefer a separate process:

```bash
# Terminal 1
pnpm cli serve
```

The service listens on `http://127.0.0.1:9374`.

## 4. Authorize an Agent

```bash
pnpm cli authorize ./examples/stock-analyst \
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

## 7. Remote Gateway Mode (Advanced / Preview)

> Gateway is an advanced capability and is not on the core CLI path. The default local workflow does not need it.

One command, no public IP needed:

```bash
uomp gateway start
# ═══ Public Gateway URL ═══
#   https://xxx.trycloudflare.com
```

## 8. Use the DO Cloud Agent

```bash
# Browser
https://uomp-stock-analyst-mvblm.ondigitalocean.app

# API
curl -X POST https://uomp-stock-analyst-mvblm.ondigitalocean.app/analyze \
  -H 'Content-Type: application/json' \
  -d '{"token":"your_token","gateway_url":"your_gateway"}'
```

## 9. Sessions & Audit

```bash
# Active sessions
pnpm cli sessions

# Audit log
pnpm cli audit --limit 20

# Revoke; the default env file is removed too
pnpm cli revoke <session-id>
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
| `pnpm cli init` | Initialize the data directory |
| `pnpm cli import <path>` | Import a Markdown folder or CSV/JSON file |
| `pnpm cli authorize <agent>` | Create a session and write a 0600 env file |
| `pnpm cli serve` | Start Auth + Guard as a standalone process |
| `pnpm cli sessions` | View active sessions |
| `pnpm cli audit --limit 20` | View audit logs |
| `pnpm cli revoke <id>` | Revoke a session and remove its default env file |

Advanced commands are hidden from help but still callable: `memory`, `registry`, `discover`, `connect`, `agent`, `gateway`.
