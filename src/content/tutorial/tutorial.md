---
title: 'UOMP SDK/CLI 教程'
description: '从零到部署的完整指南'
---

# UOMP SDK/CLI 教程

本教程带你走完 UOMP 的完整流程：从安装 CLI、导入数据、授权 Agent，到使用 SDK 编写 Agent、部署远程模式、连接 DO 云服务。

## 前置条件

- Node.js >= 22
- pnpm 9（`corepack enable` 或 `npm install -g pnpm@9`）
- 已克隆 [uomp-core](https://github.com/0xSynapse/uomp-core) 仓库

## 1. 安装与初始化

```bash
pnpm install
pnpm build
pnpm cli init
```

`pnpm cli init` 会在 `~/.uomp` 创建 Memory Store、Auth DB、Audit DB、Ed25519 密钥对和 `sessions/` 目录。

## 2. 导入私有数据

推荐先导入一个 Obsidian 笔记库或 Markdown 目录：

```bash
# 递归导入，跳过 .obsidian 和隐藏目录
pnpm cli import ~/Obsidian/MyVault

# 只看会导入什么，不写库
pnpm cli import ~/Obsidian/MyVault --dry-run
```

路径会变成授权范围：`projects/uomp/plan.md` 带有 `notes`、`notes/projects`、`notes/projects/uomp` 三个 tag。重新导入会按 key 更新，不会重复写入。

也支持 CSV 和 JSON：

```bash
pnpm cli import ./examples/stock-analyst/sample-risk.json --replace

pnpm cli import ./examples/stock-analyst/sample-holdings.csv \
  --tag portfolio:holdings \
  --sensitivity high \
  --replace
```

## 3. 启动 Auth + Guard

最简单的方式是让 `authorize` 启动内嵌 server：保持那个终端打开，然后在另一个终端运行 Agent。

如果你想分开运行：

```bash
# 终端 1
pnpm cli serve
```

服务监听 `http://127.0.0.1:9374`。

## 4. 授权 Agent

```bash
pnpm cli authorize ./examples/stock-analyst \
  --scope portfolio:holdings profile:risk
```

CLI 会创建会话，并把 token 写入 `~/.uomp/sessions/<sessionId>.env`（权限 `0600`）。输出类似：

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

默认不打印完整 JWT。需要手动复制 token 时加 `--print-token`；需要写到自定义路径时加 `--output`。

## 5. 使用 SDK 编写 Agent

在新 SDK 中，`UompClient` 提供一站式访问：

```ts
import { UompClient } from '@uomp/sdk';

// 自动从环境变量 UOM_TOKEN + UOMP_BASE_URL 初始化
const uomp = UompClient.fromEnv();

// 读取记忆
const holdings = await uomp.memory.getByTag('portfolio:holdings');
const risk = await uomp.memory.getByTag('profile:risk');

// 聚合查询（不暴露原始数据）
const totalValue = await uomp.aggregate.sum(
  'portfolio:holdings',
  'value.market_value'
);

// 上传分析报告
const payloadId = await uomp.payload.upload(report);

// 提交删除证明
await uomp.session.submitDeletionProof();

// 查询审计日志
const logs = await uomp.audit.query({ limit: 10 });
```

## 6. 运行 Agent

在另一个终端 source CLI 打印的 env 文件，然后运行 Agent：

```bash
source ~/.uomp/sessions/<sessionId>.env
node ./examples/stock-analyst/index.js
```

输出：

```
Stock Analyst v1.0 启动
持仓: 10 个标的
收到 10/10 条行情
报告: output/stock-analysis-xxx.(json|md|html)
P&L: +72.94% | Sharpe: 1.24 | Signals: 8
```

## 7. 远程 Gateway 模式（高级 / 预览）

> Gateway 是高级能力，不在 CLI 核心路径上。默认的本地流程不需要它。

一条命令启动，无需公网 IP：

```bash
# 一条命令启动 Gateway + Cloudflare Tunnel
uomp gateway start

# 输出：
# ═══ Public Gateway URL ═══
#   https://xxx.trycloudflare.com
# export UOMP_BASE_URL="https://xxx.trycloudflare.com"
```

授权远程 Agent：

```bash
# audience 指向 Gateway 的公网地址
pnpm cli authorize ./examples/stock-analyst \
  --scope portfolio:holdings profile:risk \
  --output /tmp/uomp-remote.env

source /tmp/uomp-remote.env
node ./examples/stock-analyst/index.js
```

## 8. 使用 DO 云 Agent

```bash
# 浏览器访问
https://uomp-stock-analyst-mvblm.ondigitalocean.app

# 或 API 调用
curl -X POST https://uomp-stock-analyst-mvblm.ondigitalocean.app/analyze \
  -H 'Content-Type: application/json' \
  -d '{"token":"你的UOM_TOKEN","gateway_url":"你的Gateway公网地址"}'
```

## 9. 查看会话与审计

```bash
# 查看活跃会话
pnpm cli sessions

# 查看审计日志
pnpm cli audit --limit 20

# 撤销会话；默认 env 文件也会被删除
pnpm cli revoke <session-id>
```

## 10. Gateway 管理（高级 / 预览）

```bash
# 启动 Gateway（含 Tunnel）
uomp gateway start

# 仅 Gateway，不暴露公网
uomp gateway start --no-tunnel

# 查看 Gateway 状态
uomp gateway status
```

## SDK 子客户端速查

| 子客户端 | 方法 | 说明 |
|----------|------|------|
| `uomp.memory` | `get(key)` | 按 Key 读取单条记忆 |
| `uomp.memory` | `getByTag(tag)` | 按 Tag 读取所有记忆 |
| `uomp.memory` | `getByKeys(keys)` | 批量按 Key 读取 |
| `uomp.aggregate` | `sum/avg/count/min/max` | 聚合查询（不暴露原始数据） |
| `uomp.payload` | `upload(data)` | 上传 Payload 到 Gateway |
| `uomp.payload` | `download(id)` | 下载 Payload |
| `uomp.session` | `submitDeletionProof()` | 提交数据删除证明 |
| `uomp.session` | `refresh(refreshToken)` | 刷新 Token |
| `uomp.audit` | `query({limit})` | 查询审计日志 |

## CLI 命令速查

核心路径：

| 命令 | 说明 |
|------|------|
| `pnpm cli init` | 初始化 UOMP 数据目录 |
| `pnpm cli import <path>` | 导入 Markdown 目录或 CSV/JSON 文件 |
| `pnpm cli authorize <agent>` | 创建会话，写入 0600 env 文件 |
| `pnpm cli serve` | 单独启动 Auth + Guard server |
| `pnpm cli sessions` | 查看活跃会话 |
| `pnpm cli audit --limit 20` | 查看审计日志 |
| `pnpm cli revoke <id>` | 撤销会话并删除默认 env 文件 |

高级命令默认从帮助中隐藏，但仍可调用：`memory`、`registry`、`discover`、`connect`、`agent`、`gateway`。
