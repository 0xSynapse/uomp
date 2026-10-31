---
title: 'UOMP 用户指南'
description: '从安装、导入笔记到在 Claude Desktop / Cursor 中连接、按需审批读取、审计和撤销'
---

# UOMP 用户指南

这份指南面向第一次使用 UOMP 的真实用户。完成后，你会有一个本地笔记库、一个可撤销的 Agent 会话，以及一份可查看的访问审计。

预计时间：**5–10 分钟**。所有笔记和 Token 都留在你的电脑上。

> 安装与产品概览：[Aegis OS 概览](https://heurion.org/aegis-os/) · [Aegis OS 教程](https://heurion.org/aegis-os/tutorial/)

> **适用环境**：macOS 或 Linux 终端；Claude Desktop、Cursor 或 OpenCode；本地 Obsidian / Markdown 笔记库。**不支持 Windows。**

---

## 你将完成什么

1. 安装 Aegis OS
2. 用 `aegis-os memory setup` 导入笔记、启动本地服务并写客户端配置（不授权）
3. 在客户端里发起第一次请求，在本地同意页批准 consent request
4. 读取笔记
5. 查看审计，然后撤销

---

## 1. 准备

需要：

- Aegis OS
- 一个 MCP 客户端：Claude Desktop、Cursor 或 OpenCode
- 一个 Obsidian vault 或普通 Markdown 目录

不需要 Node.js、pnpm 或 `uomp` 二进制。`aegis-os memory` 全部是原生 Rust 命令。

检查：

```bash
aegis-os --version
aegis-os memory --help
```

---

## 2. 安装

```bash
brew tap heurion-org/aegis-os https://github.com/heurion-org/aegis-os.git
brew trust heurion-org/aegis-os
brew install aegis-os
```

确认：

```bash
aegis-os --version
aegis-os doctor
aegis-os memory --help
```

---

## 3. 一次性设置

```bash
aegis-os memory setup claude --vault ~/Obsidian/MyVault
```

这条命令会：

- 导入 Markdown 笔记库（默认基础 tag 是 `notes`，可用 `--tag` 修改）
- 如果本地服务没有运行，在后台启动 `aegis-os memory serve`（默认 `http://127.0.0.1:9374`）
- 写入 `~/.uomp/sessions/claude.env` bridge profile
- 把 `uomp` MCP 条目合并进 Claude Desktop 配置
- **不签发 Token，也不授权任何访问**

命令执行完会退出，服务继续在后台运行。然后**重启 Claude Desktop**，让它加载新的 MCP 配置。

Cursor / OpenCode 用同样的方式：

```bash
aegis-os memory setup cursor --vault ~/Obsidian/MyVault
aegis-os memory setup opencode --vault ~/Obsidian/MyVault
```

默认配置路径：

- Claude Desktop：`~/.config/Claude/claude_desktop_config.json`（macOS 为 `~/Library/Application Support/Claude/`）
- Cursor：`~/.cursor/mcp.json`
- OpenCode：`~/.config/opencode/opencode.json`

用 `--config` 可以写到自定义路径；用 `--listen 127.0.0.1:9380` 可以换端口。

---

## 4. 第一次请求

打开 Claude Desktop，直接问：

```text
列出 notes/projects 下的笔记
```

Claude 会调用 UOMP 的 `list_memory(tag="notes/projects")`。MCP bridge 会：

1. 通过 `UOMP_BRIDGE_FILE` 在本地创建 consent request
2. 自动启动本地 trusted consent UI，并打开浏览器同意页
3. 等待你在页面上批准（默认最多 120 秒）

同意页会显示 Agent、task id（如果有）、session id、过期时间，以及请求的 tag / key。勾选要授予的范围，然后点 **Allow selected**。批准后，**当前工具调用继续执行**；拒绝则返回错误，下一次调用会重新创建请求。

如果浏览器没有自动打开，手动启动：

```bash
aegis-os memory ui
```

CLI 仍然保留为 fallback：

```bash
aegis-os memory pending
aegis-os memory approve <request-id>
aegis-os memory deny <request-id>
```

Agent 不能批准自己的请求；`memory approve`、`memory deny`、`memory ui` 和 `memory connect` 对 Agent 的 shell 是禁止的。

Token 过期或被撤销后，下一次工具调用会自动创建新的 consent request，不需要重新运行 `setup`。

### 高敏数据

高敏 tag（例如 `portfolio:holdings`，或以 `sensitivity: high` 导入的数据）不会被 tag scope 覆盖。Agent 必须按具体 key 发起 `read_memory`，consent request 会带上该 key；同意页会把 key 单独列出，你必须逐 key 勾选，Agent 才能读这一条。

不要用 tag scope 批量放开高敏数据。

---

## 5. 之后同步笔记

重新运行导入命令即可：

```bash
aegis-os memory import ~/Obsidian/MyVault
```

导入规则：

- 递归处理 `.md` 文件
- 跳过 `.obsidian`、隐藏目录和 `node_modules`
- 目录路径变成授权范围：
  - `projects/uomp/plan.md` → `notes`、`notes/projects`、`notes/projects/uomp`
- frontmatter 的 `tags`、`title`、`description`、`sensitivity` 会保留
- 重复导入会更新已有笔记，不会重复创建

---

## 6. 手动流程与预授权

如果客户端不在支持列表里，或者你想分开运行 server：

```bash
# 终端 1
aegis-os memory serve

# 终端 2：写 bridge profile + 自定义客户端配置
aegis-os memory setup my-client --no-server --config /path/to/mcp.json
```

`setup` 写出的配置使用标准 `mcpServers` 结构（OpenCode 使用 `mcp` 结构）。把 `uomp` 条目复制到客户端即可。

脚本需要跳过审批时，用 `connect` 预授权：

```bash
aegis-os memory connect claude --scope notes/projects
```

`connect` 会立即创建并批准一个 30 分钟会话，把 Token 写入 `~/.uomp/sessions/claude.env`，并在客户端配置里使用 `UOMP_TOKEN_FILE`。它适合脚本和 CI；日常使用优先 `setup` + 本地同意页。

---

## 7. 在客户端里验证

在 Claude Desktop / Cursor / OpenCode 里直接说：

```text
列出 notes/projects 下的笔记
```

然后：

```text
在 notes/projects 里搜索 "Ship"，然后读取匹配的那条笔记
```

UOMP 会提供三个工具：

- `list_memory`：列出 key 和元数据，不返回正文
- `search_memory`：在授权 tag 内搜索，不返回正文
- `read_memory`：按 key 读取正文

再试一条未授权的笔记：

```text
读取 note.journal.private
```

应该返回类似：

```text
ACCESS_DENIED: key is outside the token scope
```

这说明范围控制生效了，拒绝也会写进审计。

---

## 8. 在多 Agent 任务中使用 UOMP

Aegis OS 用 Google A2A 组织多 Agent 协作。UOMP consent/session 可以绑定到 A2A task：

```bash
# 1. 创建 A2A task
aegis-os ipc request --to worker --subject "Review auth" --message "Read the auth module"

# 2. 查看 task id
aegis-os a2a board
aegis-os a2a show <task-id>

# 3. 让 MCP bridge 带上 task 上下文（客户端环境变量）
export UOMP_TASK_ID=<task-id>

# 4. 批准后按 task 查看 session
aegis-os memory sessions --task-id <task-id>
```

绑定后：

- `memory pending` 会显示 task id
- consent 批准后 session 继承 task 归属
- task 进入终态时，gateway 会自动撤销绑定 session
- `memory revoke` 会把绑定的 task 转为 `input-required`

完整的 A2A / 多 Agent 流程见 [Aegis OS 教程](https://heurion.org/aegis-os/tutorial/#a2a)。

---

## 9. 查看审计

回到终端：

```bash
aegis-os memory status
aegis-os memory sessions
aegis-os memory sessions --task-id <task-id>
aegis-os memory audit --limit 20
```

`status` 显示本地 store 的条目数和 tag；`sessions` 显示 session 状态；`sessions --task-id` 只看绑定到某个 A2A task 的 session；`audit` 显示最近的 allow/deny 事件，包括 Agent、session、task、资源和原因。

检查服务是否在运行：

```bash
curl -s http://127.0.0.1:9374/health
```

---

## 10. 撤销与停止

查看会话：

```bash
aegis-os memory sessions
```

撤销指定会话：

```bash
aegis-os memory revoke <session-id>
```

撤销后，下一个请求立即返回 `401 SESSION_NOT_ACTIVE`。如果 session 绑定了 A2A task，task 会转为 `input-required`（`a2a board` 标记 `BLOCKED`）。自定义 `--runtime-dir` 时，`memory revoke` 也要传同一个 runtime 目录。

连同客户端配置一起移除：

```bash
aegis-os memory disconnect claude
```

`disconnect` 会删除客户端配置里的 `uomp` 条目、撤销 env 文件里的 session（`connect` 路径），并清理 env 文件。`setup` 路径的 bridge env 没有 session id；用 `memory sessions` + `memory revoke` 撤销对应会话。

停止后台服务：

```bash
aegis-os memory stop
```

`stop` 只停止 server，不会立即撤销已签发的 session；session 仍会在过期时间后失效。要立即收回访问，用 `revoke` 或 `disconnect`。

### 会话过期后

`setup` 模式下，下一次工具调用会自动创建新的 consent request，批准后继续，不需要重新运行 `setup`。

预授权模式（`connect`）重新执行同一条命令即可：

```bash
aegis-os memory connect claude --scope notes/projects
```

MCP server 会在每次工具调用前检查 Token；重新 `connect` 后，下一次调用自动使用新 Token，**不需要重启客户端**。

---

## 11. 常见问题

| 问题 | 处理 |
|---|---|
| 客户端看不到 UOMP 工具 | 检查客户端配置里的 `uomp` 条目；重启客户端；`curl -s http://127.0.0.1:9374/health` 确认服务在运行 |
| 端口 9374 被占用 | `aegis-os memory stop`；或 `aegis-os memory setup claude --listen 127.0.0.1:9380 ...` |
| 工具一直等待审批 | 先看是否已自动打开同意页；没有就运行 `aegis-os memory ui`。CLI fallback：`aegis-os memory pending`，再 `approve` / `deny` |
| `SESSION_NOT_ACTIVE` | 会话过期或被撤销；在客户端重新发起请求，或运行 `aegis-os memory connect claude --scope notes/projects` |
| `ACCESS_DENIED` | 该 key/tag 不在授权范围；检查 consent request 的 scope，或查看 `aegis-os memory audit` |
| 高敏数据读不到 | 高敏 item 必须按 key 请求并单独批准；tag scope 不会覆盖 |
| 自定义 runtime 下 task 没变化 | `a2a` / `memory revoke` 命令补上同一个 `--runtime-dir` |
| 想清空所有本地数据 | 先 `aegis-os memory stop`，再删除 `~/.uomp`。这会删除笔记库、密钥和审计 |
| 在 Windows 上运行 | 不支持 Windows；请使用 macOS 或 Linux |

### 数据在哪里

```text
~/.uomp/
├── memory.db          # 导入的笔记
├── auth.db            # 会话、consent requests、审计
├── sessions/          # 0600 bridge / token env 文件
├── server.pid         # 后台服务 pid
└── .secrets/          # Ed25519 密钥、admin token、bridge token
```

### 如何彻底卸载

```bash
aegis-os memory stop || true
rm -rf ~/.uomp
```

如果安装时写入了客户端配置，再运行 `aegis-os memory disconnect <client>`，或手动删除配置里的 `uomp` 条目。

---

## 12. 安全边界

UOMP 能做到：

- 本地优先，笔记默认不离开你的机器
- 按 tag/key 限定范围
- 高敏 item 只能按 key 授权
- 首次 tool call 创建 consent request，用户在本地 trusted consent UI 批准（CLI 为 fallback）
- 会话过期和立即撤销
- 每一次允许/拒绝都有审计
- bridge profile 不含 Token；预授权 Token 存在 `0600` 文件里，默认不打印 JWT

UOMP 不能防止：

- 同一个 OS 用户下的恶意进程读取 `~/.uomp`
- root / 被攻陷的机器
- 被授权的 Agent 保留它已经读到的内容
- 备份或同步盘把 env 文件带到别处

不要把 `~/.uomp` 提交到 git，也不要把会话 env 文件发到公开渠道。

---

## 13. 进阶

- 想了解协议和 Token 格式：[规范 Draft-00](/spec/)
- Aegis OS 安装与多 Agent 教程：[Aegis OS Tutorial](https://heurion.org/aegis-os/tutorial/)
- 想写自己的 Agent：[Aegis OS UOMP module](https://github.com/heurion-org/aegis-os/tree/main/modules/uomp)
- 想接 MCP 客户端：`aegis-os memory mcp`（见 module README）
- 远程 Agent / Gateway 属于高级预览，不是本地流程的必需部分
