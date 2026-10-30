---
title: 'UOMP 原生实现'
description: 'UOMP 作为 Aegis OS memory module 的原生实现：aos-memory、aos-memory-store、aos-memory-gateway 与 aegis-os memory CLI'
---

# UOMP 原生实现

> **UOMP 是协议，Aegis OS 是原生实现。** UOMP 网站只保留规范、设计说明和路线图；可运行代码在 [heurion-org/aegis-os](https://github.com/heurion-org/aegis-os)。

## 1. 模块结构

| 模块 | 职责 |
|---|---|
| `crates/aos-memory` | scope/lease 映射、deny/field 过滤、高敏 key、远程 token 校验 |
| `crates/aos-memory-store` | UOMP 兼容 SQLite schema、Markdown 导入、CRUD |
| `crates/aos-memory-gateway` | 远程 Agent 入口、EdDSA JWT 验签、TLS/mTLS、限流、审计 |
| `aegis-os memory` | 用户命令入口，迁移期委托给 UOMP reference CLI |
| `aegis-os memory-gateway` | 启动本地 Aegis Memory Gateway |

## 2. 本地流程

```bash
brew install aegis-os

# 一次性设置：导入 + 客户端配置 + 后台服务，不授权
aegis-os memory setup claude --vault ~/Obsidian/MyVault

# 在 Claude / Cursor / OpenCode 里请求读取
# Aegis OS 打开本地审批页；批准后 Agent 继续

aegis-os memory status
aegis-os memory pending
aegis-os memory approve <request-id>
aegis-os memory revoke <session-id>
```

本地路径：

```text
Agent / MCP client
      │  UOMP token
      ▼
Aegis policy + lease
      │
      ▼
aos-memory-store (SQLite + Markdown connector)
      │
      ▼
audit
```

## 3. 远程 Agent

```text
Remote Agent (Aegis Cloud)
      │  TLS 1.3 + mTLS
      ▼
aegis-os memory-gateway
      │  session check + scope + rate limit + audit
      ▼
local Aegis memory store
```

远程接入使用 device flow：

1. Agent 调用 `POST /v1/remote/requests`
2. 用户在本地批准
3. Agent 轮询并一次性领取 remote token
4. token 绑定 audience，过期/撤销后立即失效

## 4. 写入与 Payload

Agent 写入不会直接修改 Memory Store：

```text
PUT /v1/memory/:key
  → write scope check
  → high-sensitivity reject
  → staged_writes
  → user approve
  → apply + audit
```

加密 Payload：

```text
POST /v1/payload
  → encrypted envelope
  → session/agent bound
  → user retrieves and decrypts locally
```

## 5. 数据模型映射

| UOMP | Aegis OS |
|---|---|
| Session | consent envelope + `LeaseGrant` |
| ConsentRequest | `PendingEscalation` |
| CapabilityToken | lease token |
| tag / key | `memory:tag:<tag>` / `memory:key:<key>` |
| `uom.json` | Aegis manifest memory profile |
| Memory Guard | gateway + policy + memory module + recorder |

完整映射见 [UOMP → Aegis OS 记忆同意映射](https://github.com/heurion-org/aegis-os/blob/main/docs/UOMP_MEMORY_CONSENT_MAPPING.md)。

## 6. 迁移状态

- 品牌、规范、首页、文档：完成
- Aegis policy/lease、memory gateway、TLS/mTLS：完成
- staged writes、payload、remote device flow：完成
- 原生 SQLite store 与 Markdown importer：基础完成
- `aegis-os memory` 原生命令：`status` / `import` / `read` / `list` / `search` / `staged` / `payload` / `mcp` 已原生；其余迁移中
- Gateway 完全切到原生 store：进行中
- 统一 Web trusted UI：待完成

## 7. 相关链接

- [协议规范](/spec/)
- [Aegis OS](https://github.com/heurion-org/aegis-os)
- [UOMP module](https://github.com/heurion-org/aegis-os/tree/main/modules/uomp)
- [UOMP → Aegis OS mapping](https://github.com/heurion-org/aegis-os/blob/main/docs/UOMP_MEMORY_CONSENT_MAPPING.md)
- [Reference CLI (migration only)](https://github.com/heurion-org/aegis-os/tree/main/modules/uomp/reference)
