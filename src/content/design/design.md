---
title: 'UOMP 实现设计'
description: 'UOMP 参考实现 uomp-mvp 的架构与实现说明：组件职责、部署模式、SDK、远程访问、存储抽象'
---

# UOMP 实现设计

> **实现状态（2026-10）：** 当前主线是本地 CLI + MCP 闭环；Aegis OS 是执行协议的参考运行时。远程 Gateway、Cloud Relay、S3/IPFS 和链上部分是研究或预览能力，不应视为已交付。当前使用方式见 [README](https://github.com/0xSynapse/uomp-core#quick-start) 和 [教程](/tutorial/)。本文档其余部分保留原始实现设计。

UOMP 是开放协议，Aegis OS 是参考运行时；本仓库的 [`uomp-mvp`](https://github.com/0xSynapse/uomp-core) 是参考 CLI 和本地实现。本文档说明它如何将[协议规范](/spec/)落地为可运行的代码。协议到 Aegis OS 的字段映射见 [UOMP → Aegis OS 记忆同意映射](https://github.com/heurion-org/aegis-os/blob/main/docs/UOMP_MEMORY_CONSENT_MAPPING.md)。

---

## 1. 实现概览

`uomp-mvp` 是一个 TypeScript monorepo，核心组件与 Spec 中的角色一一对应：

| 包 / 应用 | 角色 | 职责 |
|-----------|------|------|
| `packages/core` | 共享层 | 类型、常量、工具函数 |
| `packages/store` | Memory Store | 可插拔存储后端（SQLite / Encrypted Object S3 / IPFS） |
| `packages/token` | — | EdDSA JWT 的签发与校验 |
| `packages/auth` | Auth Service | Session 创建/授权/关闭/撤销 |
| `packages/guard` | Memory Guard | Token 校验、Scope 过滤、审计日志 |
| `packages/identity` | Identity Verification | DID/GPG 身份验证框架 |
| `packages/sdk` | Agent SDK | `UompClient`，Node.js 客户端 |
| `packages/cli` | User UI | 用户侧 CLI：导入、授权、`serve`、`mcp`、会话/审计、Gateway/Store 管理 |
| `apps/server` | — | Auth + Guard 组合 HTTP 服务（`127.0.0.1:9374`） |
| `apps/gateway` | — | 用户自托管 Gateway：mTLS + Token 转发 + Cloudflare Tunnel |
| `apps/relay` | Cloud Relay | 无状态公共 Relay（设计阶段）：公钥验签 + 密文转发 |

---

## 2. 架构与部署模式

UOMP 支持三种部署模式，按用户负担从低到高排列：

### 2.1 本地模式（Agent 与 Guard 在同一台机器）

默认、零配置。Agent 直接通过 `http://127.0.0.1:9374` 访问 Memory Guard。

```
┌──────────┐   HTTP   ┌──────────────┐   ┌──────────────┐
│  Agent   │ ───────► │ Memory Guard │──►│ Memory Store │
└──────────┘          └──────────────┘   └──────────────┘
```

启动方式：

```bash
# MCP 客户端（推荐）：一次性设置，不授权
uomp setup claude --vault ~/Obsidian/MyVault

# Agent 在客户端里发起请求，UOMP 打开审批页；终端兜底：
uomp pending
uomp approve <request-id>

# 管理
uomp status
uomp stop
uomp disconnect claude

# 高级：预授权 / 脚本
uomp connect claude --vault ~/Obsidian/MyVault --scope notes/projects

# Agent 包：授权 + 写 env 文件
uomp connect ./my-agent --scope notes/projects --output ~/.uomp/my-agent.env
source ~/.uomp/my-agent.env && node index.js

# 手动 / 不支持的客户端
uomp serve
uomp authorize ./my-agent --scope notes/projects --output ~/.uomp/my-agent.env --no-server
source ~/.uomp/my-agent.env && node index.js
uomp mcp --session ~/.uomp/my-agent.env --print-config
```

> `uomp agent run ./my-agent` 是本地调试 shortcut，命令默认隐藏，仅用于开发测试。

### 2.2 远程模式（Agent 在外部，通过 Gateway 访问）

Agent 运行在云服务（Digital Ocean / VPS / 容器），通过 Gateway 回连用户本地的 Memory Guard。

```
┌──────────────┐   mTLS + Token   ┌──────────────┐   HTTP   ┌──────────────┐
│ Remote Agent │ ────────────────► │   Gateway    │ ───────► │ Memory Guard │
└──────────────┘                  └──────────────┘          └──────────────┘
```

Gateway 提供公网入口。无公网 IP 时使用 Cloudflare Tunnel：

```bash
uomp gateway start
# ═══ Public Gateway URL ═══
#   https://xxx.trycloudflare.com
```

一条命令：Gateway + mTLS 证书 + 公网 Tunnel 全自动。

## 3. SDK

`packages/sdk` 提供 `UompClient` 类，当前面向 Node.js Agent。

### 3.1 Node.js 模式

```ts
import { UompClient } from '@uomp/sdk';

const uomp = UompClient.fromEnv(); // 读取 UOM_TOKEN + UOMP_BASE_URL

await uomp.memory.getByTag('portfolio:holdings');
await uomp.aggregate.sum('portfolio:holdings', 'value.market_value');
await uomp.payload.upload(report);
await uomp.session.finalize(); // 提交删除证明 + 关闭 Session
await uomp.auth.createSession({ agentId, requestedScopes });

// 从 JWT 自动解析
console.log(uomp.tokenInfo.scopes);   // 授权范围
console.log(uomp.tokenInfo.expiresAt); // 过期时间
```

Transport 层自动处理：
- `http://` → 直连 Memory Guard
- `https://` → Gateway mTLS（自动加载 `~/.uomp/.gateway-certs/`）
- 重试 + 退避 + 超时
- 结构化错误码（`UompError`，区分可重试 / 不可重试）

### 3.2 子客户端速查

| 子客户端 | 主要方法 |
|----------|---------|
| `uomp.memory` | `get(key)`, `getByTag(tag)`, `getByKeys(keys)`, `listTags()`, `has(key)`, `set(key, item)`, `delete(key)` |
| `uomp.aggregate` | `sum(tag, field)`, `avg()`, `count()`, `min()`, `max()` |
| `uomp.payload` | `upload(data)`, `download(id)`, `info(id)` |
| `uomp.session` | `submitDeletionProof()`, `finalize()`, `close()`, `trackAccess(key)` |
| `uomp.audit` | `query({ sessionId, limit })`, `getLastAccess()` |
| `uomp.auth` | `createSession()`, `grant()`, `revoke()`, `validate()` |

完整 API 参考见 [`docs/sdk-design.md`](https://github.com/0xSynapse/uomp-core/tree/main/docs/sdk-design.md)。

---

## 4. 远程访问

### 4.1 用户 Gateway

`apps/gateway` 是用户自托管的 Memory Guard 入口：

```bash
uomp gateway start               # Gateway + Cloudflare Tunnel
uomp gateway start --no-tunnel   # 仅 Gateway
```

职责：mTLS 终结、Token 校验（audience + 签名 + 有效期）、Memory/audit 请求转发、Payload 缓存。

### 4.2 Cloud Relay

Cloud Relay 是 Gateway 的无状态公共版本。UOMP 运营一个默认实例，开源代码允许任何人自建。

| | 用户 Gateway | Cloud Relay |
|------|------------|------------|
| 部署 | 用户本地 | 公共云（总是在线） |
| 看到明文 | ✅ | ❌（Guard 内加密后存储） |
| 用户负担 | 安装 + 运行 | 零安装 |
| 适用场景 | 高敏感数据 | 普通使用、公共中继 |

Relay 不存数据、不读明文——只验 Token + 转发密文。

### 4.3 存储抽象

Memory Store 从硬编码 SQLite 改为可插拔接口 `IMemoryStore`：

```
Guard → IMemoryStore ─┬─ SQLiteStore（本地，默认）
                       ├─ EncryptedObjectStore（S3/R2，多设备）
                       └─ IPFSStore（去中心化）
```

- **SQLite**：`~/.uomp/memory.db`，默认，零配置
- **Encrypted Object**：每个 Memory Item 独立 AES-256-GCM 加密，存 S3-compatible 对象存储。多设备共享同一份加密数据
- **IPFS**：内容寻址，去中心化（未来）

加密在 Guard 进程内完成，云后端只存密文。密钥由 Guard 的密钥材料派生。

完整设计文档：[`docs/store-abstraction-design.md`](https://github.com/0xSynapse/uomp-core/tree/main/docs/store-abstraction-design.md)。

---

## 5. 认证与授权实现

### 5.1 Agent 声明（uom.json）

Agent 在 `uom.json` 中声明 `requested_scopes`、`data_retention_policy`、`external_data_sources` 等。CLI 在 `packages/cli/src/utils/manifest.ts` 中解析并转换为内部 `AgentManifest` 类型。

### 5.2 Session 生命周期

```
[created] ──grant──► [active] ──close/timeout/revoke/deletion-proof──► [closed/expired/revoked]
```

`AuthService.grantSession()` 签发 Capability Token，支持 `allowedFields`、`aggregationOnly`、`taskBound` 等约束。

### 5.3 JWT 实现

- 算法：`EdDSA`（曲线 `Ed25519`），使用 `jose` 库
- 内部 payload camelCase，JWT claims snake_case
- Token 包含：`session_id`、`agent_id`、`scopes`、`limits`、`profile`、`audience`、`allowed_fields`、`aggregation_only`、`task_bound`

### 5.4 Guard 鉴权

`MemoryGuard.validateRequest()` 按序校验：签名 → 过期 → 黑名单 → scope → sensitivity。`aggregation_only` Token 拒绝非聚合路径。高敏感数据必须 key 级授权。

---

## 6. 股票分析示例

`examples/stock-analyst/` 是完整的验收示例：

1. `uomp import` 导入持仓 CSV + 风险偏好
2. （可选）用高级命令 `uomp discover` / `uomp inspect` 查看并验证 Agent
3. `uomp connect` 创建会话并写入 env 文件（MCP 客户端会同时写客户端配置）
4. Agent 读取数据 → 拉取行情 → 分析（P&L、Sharpe、Beta、RSI、情景分析）
5. 生成双语报告（JSON + Markdown + HTML）
6. `uomp sessions` / `uomp audit` 审计
7. `uomp revoke` 撤销

完整步骤见 [`examples/stock-analyst/README.md`](https://github.com/0xSynapse/uomp-core/tree/main/examples/stock-analyst/README.md)。

---

## 7. 本地配置文件

```
~/.uomp/
├── agents/               # 已安装的 Agent
├── registry/             # 本地 Registry
├── sessions/             # 0600 会话 env 文件
├── server.json           # 后台服务状态
├── server.log            # 后台服务日志
├── memory.db             # Memory Store（SQLite）
├── auth.db               # Session 与黑名单
├── audit.db              # 审计日志
├── .secrets/             # Ed25519 密钥对 + 管理员令牌
└── .gateway-certs/       # 仅在启用 Gateway 时存在
```

---

## 8. MVP 限制与未来扩展

| 能力 | 状态 | 说明 |
|------|------|------|
| Agent 读取 | ✅ | 按 tag/key/field 授权 |
| Agent 写入 | ❌ | Guard 返回 `503 WRITE_NOT_AVAILABLE` |
| 本地 CLI | ✅ | import / setup / connect / authorize / serve / start / status / stop / disconnect / pending / approve / deny / mcp / sessions / audit / revoke |
| Markdown 导入 | ✅ | Obsidian/Markdown 目录，路径生成范围 |
| MCP | ✅ 实验 | stdio `list_memory` / `search_memory` / `read_memory` |
| 远程 Gateway | ⚠️ 高级/预览 | mTLS + Cloudflare Tunnel |
| 聚合查询 | ✅ | sum/avg/count/min/max，配合 `aggregation_only` |
| 删除证明 | ✅ | Agent 提交签名证明，Session 自动关闭 |
| 字段过滤 | ✅ | Token 指定 `allowed_fields`，Guard 过滤 |
| Store 抽象 | ⚠️ 部分实现 | `IMemoryStore` + SQLite；S3/IPFS 仍在设计 |
| Cloud Relay | ⚠️ 设计/预览 | `apps/relay/` 原型，未进入核心路径 |
| 身份验证 | ⚠️ | DID/GPG 框架存在，验证强度待增强 |

---

## 9. 相关链接

- [协议规范](/spec/)
- [参考实现仓库](https://github.com/0xSynapse/uomp-core)
- [SDK 设计文档](https://github.com/0xSynapse/uomp-core/tree/main/docs/sdk-design.md)
- [Store 抽象化设计](https://github.com/0xSynapse/uomp-core/tree/main/docs/store-abstraction-design.md)
- [股票分析示例](https://github.com/0xSynapse/uomp-core/tree/main/examples/stock-analyst)
