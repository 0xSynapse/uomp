---
title: 'UOMP Implementation Design'
description: 'Architecture and implementation notes for the uomp-mvp reference implementation: components, deployment modes, SDK, remote access, store abstraction'
---

# UOMP Implementation Design

> **Implementation status (2026-10):** the current focus is the local CLI + MCP loop. Remote Gateway, Cloud Relay, S3/IPFS, and on-chain sections are research or preview capabilities, not shipped product. For the current workflow, see the [README](https://github.com/0xSynapse/uomp-core#quick-start) and [tutorial](/en/tutorial/). The rest of this document preserves the original implementation design.

This document explains how the UOMP **reference implementation** [`uomp-mvp`](https://github.com/0xSynapse/uomp-core) turns the [protocol specification](/en/spec/) into runnable code.

---

## 1. Implementation Overview

`uomp-mvp` is a TypeScript monorepo. Each package maps to a Spec role:

| Package / App | Role | Responsibility |
|---------------|------|----------------|
| `packages/core` | Shared | Types, constants, utilities |
| `packages/store` | Memory Store | Pluggable storage backends (SQLite / Encrypted Object S3 / IPFS) |
| `packages/token` | — | EdDSA JWT issuance and verification |
| `packages/auth` | Auth Service | Session create/grant/close/revoke |
| `packages/guard` | Memory Guard | Token validation, scope filtering, audit logging |
| `packages/identity` | Identity Verification | DID/GPG verification framework |
| `packages/sdk` | Agent SDK | `UompClient`, Node.js client |
| `packages/cli` | User UI | User CLI: import, authorize, `serve`, `mcp`, sessions/audit, Gateway/Store management |
| `apps/server` | — | Combined Auth + Guard HTTP service (`127.0.0.1:9374`) |
| `apps/gateway` | — | Self-hosted Gateway: mTLS + token forwarding + Cloudflare Tunnel |
| `apps/relay` | Cloud Relay | Stateless public Relay (design phase): pubkey verification + ciphertext forwarding |

---

## 2. Architecture & Deployment Modes

UOMP supports three deployment modes, ordered by user burden (low to high):

### 2.1 Local Mode (Agent + Guard on same machine)

Default, zero-config. Agent connects directly to Memory Guard at `http://127.0.0.1:9374`.

```
┌──────────┐   HTTP   ┌──────────────┐   ┌──────────────┐
│  Agent   │ ───────► │ Memory Guard │──►│ Memory Store │
└──────────┘          └──────────────┘   └──────────────┘
```

```bash
# Terminal 1
uomp serve

# Terminal 2
uomp authorize ./my-agent --scope notes/projects --output ~/.uomp/my-agent.env --no-server
source ~/.uomp/my-agent.env && node index.js

# MCP client config (optional)
uomp mcp --session ~/.uomp/my-agent.env --print-config
```

> `uomp agent run ./my-agent` is a hidden local debugging shortcut. It is for development only.

### 2.2 Remote Mode (Agent external, via Gateway)

Agent runs on cloud (Digital Ocean / VPS / container), connects back through Gateway.

```
┌──────────────┐   mTLS + Token   ┌──────────────┐   HTTP   ┌──────────────┐
│ Remote Agent │ ────────────────► │   Gateway    │ ───────► │ Memory Guard │
└──────────────┘                  └──────────────┘          └──────────────┘
```

One command with Cloudflare Tunnel (no public IP needed):

```bash
uomp gateway start
# ═══ Public Gateway URL ═══
#   https://xxx.trycloudflare.com
```

## 3. SDK

`packages/sdk` provides the `UompClient` class for Node.js Agents.

### 3.1 Node.js Mode

```ts
import { UompClient } from '@uomp/sdk';

const uomp = UompClient.fromEnv(); // reads UOM_TOKEN + UOMP_BASE_URL

await uomp.memory.getByTag('portfolio:holdings');
await uomp.aggregate.sum('portfolio:holdings', 'value.market_value');
await uomp.payload.upload(report);
await uomp.session.finalize(); // deletion proof + close
await uomp.auth.createSession({ agentId, requestedScopes });

console.log(uomp.tokenInfo.scopes);
console.log(uomp.tokenInfo.expiresAt);
```

Transport handles: `http://` → direct, `https://` → mTLS auto-load, retry + backoff + timeout, `UompError`.

### 3.2 Sub-client Quick Reference

| Sub-client | Key Methods |
|------------|-------------|
| `uomp.memory` | `get(key)`, `getByTag(tag)`, `getByKeys(keys)`, `listTags()`, `has(key)`, `set(key, item)`, `delete(key)` |
| `uomp.aggregate` | `sum(tag, field)`, `avg()`, `count()`, `min()`, `max()` |
| `uomp.payload` | `upload(data)`, `download(id)`, `info(id)` |
| `uomp.session` | `submitDeletionProof()`, `finalize()`, `close()`, `trackAccess(key)` |
| `uomp.audit` | `query({ sessionId, limit })`, `getLastAccess()` |
| `uomp.auth` | `createSession()`, `grant()`, `revoke()`, `validate()` |

---

## 4. Remote Access

### 4.1 User Gateway

`apps/gateway` is the user's self-hosted Memory Guard entry point:

```bash
uomp gateway start               # Gateway + Cloudflare Tunnel
uomp gateway start --no-tunnel   # Gateway only
```

Responsibilities: mTLS termination, token validation (audience + signature + expiry), memory/audit forwarding, payload cache.

### 4.2 Cloud Relay

Cloud Relay is a stateless public version of Gateway. UOMP runs a default instance (`relay.uomp.org`); open-source code allows anyone to self-host.

| | User Gateway | Cloud Relay |
|------|------------|------------|
| Deployed | User local | Public cloud (always online) |
| Sees plaintext | ✅ | ❌ (encrypted in Guard before storage) |
| User burden | Install + run | Zero install |
| Use case | High-sensitivity data | General use, Webapp developers |

Relay stores no data and reads no plaintext — it only validates tokens and forwards ciphertext.

### 4.3 Store Abstraction

Memory Store is abstracted behind the `IMemoryStore` interface:

```
Guard → IMemoryStore ─┬─ SQLiteStore (local, default)
                       ├─ EncryptedObjectStore (S3/R2, multi-device)
                       └─ IPFSStore (decentralized)
```

- **SQLite**: `~/.uomp/memory.db`, default, zero-config
- **Encrypted Object**: each Memory Item independently AES-256-GCM encrypted, stored on S3-compatible object storage. Multi-device via shared encrypted data
- **IPFS**: content-addressed, decentralized (future)

Encryption occurs inside the Guard process; cloud backends store only ciphertext. Keys are derived from Guard key material.

Full design doc: [`docs/store-abstraction-design.md`](https://github.com/0xSynapse/uomp-core/tree/main/docs/store-abstraction-design.md).

---

## 5. Auth & Authorization

### 5.1 Agent Manifest (uom.json)

Agents declare `requested_scopes`, `data_retention_policy`, `external_data_sources` in `uom.json`. The CLI parses these in `packages/cli/src/utils/manifest.ts`.

### 5.2 Session Lifecycle

```
[created] ──grant──► [active] ──close/timeout/revoke/deletion-proof──► [closed/expired/revoked]
```

`AuthService.grantSession()` issues Capability Tokens with optional `allowedFields`, `aggregationOnly`, `taskBound` constraints.

### 5.3 JWT Implementation

- Algorithm: `EdDSA` (curve `Ed25519`), using `jose`
- Internal payload camelCase, JWT claims snake_case
- Claims: `session_id`, `agent_id`, `scopes`, `limits`, `profile`, `audience`, `allowed_fields`, `aggregation_only`, `task_bound`

### 5.4 Guard Enforcement

`MemoryGuard.validateRequest()` checks in order: signature → expiry → denylist → scope → sensitivity. `aggregation_only` tokens are rejected on non-aggregation paths. High-sensitivity items require explicit key authorization.

---

## 6. Stock Analyst Example

`examples/stock-analyst/` is the full acceptance example:

1. `uomp import` holdings CSV + risk profile
2. (Optional) use the advanced `uomp discover` / `uomp connect` commands to inspect and verify the Agent
3. `uomp authorize` creates a session and writes the env file
4. Agent reads data → fetches quotes → analyzes (P&L, Sharpe, Beta, RSI, scenarios)
5. Generates bilingual reports (JSON + Markdown + HTML)
6. `uomp sessions` / `uomp audit` for auditing
7. `uomp revoke` to revoke

Full steps: [`examples/stock-analyst/README.md`](https://github.com/0xSynapse/uomp-core/tree/main/examples/stock-analyst/README.md).

---

## 7. Local Config Files

```
~/.uomp/
├── agents/               # Installed agents
├── registry/             # Local registry
├── sessions/             # 0600 session env files
├── memory.db             # Memory Store (SQLite)
├── auth.db               # Sessions and denylist
├── audit.db              # Audit logs
├── .secrets/             # Ed25519 keypair + admin token
└── .gateway-certs/       # Only when the Gateway is enabled
```

---

## 8. MVP Limitations & Future Extensions

| Capability | Status | Notes |
|------------|--------|-------|
| Agent read | ✅ | Authorized by tag/key/field |
| Agent write | ❌ | Guard returns `503 WRITE_NOT_AVAILABLE` |
| Local CLI | ✅ | import / authorize / serve / mcp / sessions / audit / revoke |
| Markdown import | ✅ | Obsidian/Markdown folders with path-derived scopes |
| MCP | ✅ Experimental | stdio `list_memory` / `search_memory` / `read_memory` |
| Remote Gateway | ⚠️ Advanced/preview | mTLS + Cloudflare Tunnel |
| Aggregation | ✅ | sum/avg/count/min/max, paired with `aggregation_only` |
| Deletion proof | ✅ | Agent submits signed proof, session auto-closes |
| Field filtering | ✅ | Token specifies `allowed_fields`, Guard filters |
| Store abstraction | ⚠️ Partial | `IMemoryStore` + SQLite; S3/IPFS still designed |
| Cloud Relay | ⚠️ Designed | `apps/relay/` prototype, not on the core path |
| Identity verification | ⚠️ | DID/GPG framework present, verification to be strengthened |

---

## 9. Related Links

- [Protocol Specification](/en/spec/)
- [Reference Implementation](https://github.com/0xSynapse/uomp-core)
- [SDK Design Document](https://github.com/0xSynapse/uomp-core/tree/main/docs/sdk-design.en.md)
- [Store Abstraction Design](https://github.com/0xSynapse/uomp-core/tree/main/docs/store-abstraction-design.md)
- [Stock Analyst Example](https://github.com/0xSynapse/uomp-core/tree/main/examples/stock-analyst)
