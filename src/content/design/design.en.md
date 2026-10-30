---
title: 'UOMP Native Implementation'
description: 'UOMP as the native Aegis OS memory module: aos-memory, aos-memory-store, aos-memory-server, aos-memory-gateway, and the aegis-os memory CLI'
---

# UOMP Native Implementation

> **UOMP is the protocol; Aegis OS is the native implementation.** This website is spec/design only. Runnable code lives in [heurion-org/aegis-os](https://github.com/heurion-org/aegis-os).

## 1. Modules

| Module | Responsibility |
|---|---|
| `crates/aos-memory` | scope/lease mapping, deny/field filtering, high-sensitivity keys, remote token policy |
| `crates/aos-memory-store` | UOMP-compatible SQLite schema, Markdown import, staged writes, payloads |
| `crates/aos-memory-server` | native consent requests, sessions, Ed25519 JWT, revocation, audit |
| `crates/aos-memory-gateway` | remote Agent entry point, EdDSA JWT verification, TLS/mTLS, rate limiting, audit |
| `aegis-os memory` | user-facing command entry; every command is native Rust |
| `aegis-os memory-gateway` | starts the local Aegis Memory Gateway |

## 2. Local flow

```bash
brew install aegis-os

# one-time setup: import + client config + background server, no access granted
aegis-os memory setup claude --vault ~/Obsidian/MyVault

# ask Claude / Cursor / OpenCode for notes
# the first tool call creates a consent request; the agent continues after approval

aegis-os memory pending
aegis-os memory approve <request-id>
aegis-os memory audit
aegis-os memory disconnect claude
```

The browser consent page is deferred; CLI approval is the native path for now. An Agent cannot approve its own request, and high-sensitivity items stay outside Agent scopes.

Local path:

```text
Agent / MCP client
      │  UOMP bridge / token
      ▼
aos-memory-server (consent, session, JWT, audit)
      │  scoped request
      ▼
aos-memory-store (SQLite + Markdown + staged + payload)
```

## 3. Remote Agent

```text
Remote Agent (Aegis Cloud)
      │  TLS 1.3 + mTLS
      ▼
aegis-os memory-gateway
      │  session check + scope + rate limit + audit
      ▼
local Aegis memory store
```

Remote onboarding uses a device flow:

1. Agent calls `POST /v1/remote/requests`
2. The user approves locally
3. The Agent polls and retrieves a one-time remote token
4. The token is bound to an audience and dies on expiry/revocation

## 4. Writes and payloads

Agent writes never modify the Memory Store directly:

```text
PUT /v1/memory/:key
  → write scope check
  → high-sensitivity reject
  → staged_writes
  → user approve
  → apply + audit
```

Encrypted payloads:

```text
POST /v1/payload
  → encrypted envelope
  → session/agent bound
  → user retrieves and decrypts locally
```

## 5. Data model mapping

| UOMP | Aegis OS |
|---|---|
| Session | consent envelope + `LeaseGrant` |
| ConsentRequest | `PendingEscalation` |
| CapabilityToken | lease token |
| tag / key | `memory:tag:<tag>` / `memory:key:<key>` |
| `uom.json` | Aegis manifest memory profile |
| Memory Guard | gateway + policy + memory module + recorder |

Full mapping: [UOMP → Aegis OS memory consent mapping](https://github.com/heurion-org/aegis-os/blob/main/docs/UOMP_MEMORY_CONSENT_MAPPING.md).

## 6. Implementation status

- Brand, spec, homepage, docs: done
- Aegis policy/lease, memory gateway, TLS/mTLS: done
- Staged writes, payloads, remote device flow: done
- Native SQLite store, Markdown importer, staged writes, payloads: done
- Native consent server, sessions, Ed25519 JWT, revocation, audit: done
- `aegis-os memory` native commands: `status` / `import` / `read` / `list` / `search` / `serve` / `setup` / `pending` / `approve` / `deny` / `connect` / `disconnect` / `sessions` / `revoke` / `audit` / `approvals` / `stop` / `staged` / `payload` / `mcp` are all native
- `uomp-core` / `uomp-mvp` reference: archived, no longer vendored or invoked at runtime
- Unified web trusted UI: pending (CLI approval today)

## 7. Links

- [Protocol spec](/en/spec/)
- [Aegis OS](https://github.com/heurion-org/aegis-os)
- [UOMP module](https://github.com/heurion-org/aegis-os/tree/main/modules/uomp)
- [UOMP → Aegis OS mapping](https://github.com/heurion-org/aegis-os/blob/main/docs/UOMP_MEMORY_CONSENT_MAPPING.md)
