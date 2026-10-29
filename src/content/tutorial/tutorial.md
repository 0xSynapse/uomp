---
title: 'UOMP 用户指南'
description: '从安装、导入笔记到在 Claude Desktop / Cursor 中授权读取、审计和撤销'
---

# UOMP 用户指南

这份指南面向第一次使用 UOMP 的真实用户。完成后，你会有一个本地笔记库、一个可撤销的 Agent 会话，以及一份可查看的访问审计。

预计时间：**10–15 分钟**。所有笔记和 Token 都留在你的电脑上。

> **适用环境**：macOS 或 Linux 终端；Claude Desktop、Cursor 或 OpenCode；本地 Obsidian / Markdown 笔记库。Windows 可通过 WSL 或 Git Bash 使用，但尚未完整验证。

---

## 你将完成什么

1. 安装 UOMP
2. 导入 Obsidian / Markdown 笔记
3. 启动本地 Auth + Guard 服务
4. 给 MCP 客户端一个 30 分钟、限定范围的授权
5. 在 Claude Desktop / Cursor / OpenCode 里读取笔记
6. 查看审计，然后撤销

---

## 1. 准备

需要：

- Node.js **22 或更高版本**
- `git`
- 一个 MCP 客户端：Claude Desktop、Cursor 或 OpenCode
- 一个 Obsidian vault 或普通 Markdown 目录

检查 Node：

```bash
node --version
```

如果低于 v22，先升级 Node.js。

---

## 2. 安装

在终端运行：

```bash
curl -fsSL https://www.uomp.org/install.sh | bash
```

安装脚本会：

- 把 UOMP 克隆到 `~/.uomp/cli`
- 构建 CLI
- 把 `uomp` 链接到 `~/.local/bin`

如果 `uomp` 不在 `PATH` 里，脚本会打印需要添加的那一行，例如：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

重新打开终端，确认：

```bash
uomp --version
```

然后初始化本地数据目录：

```bash
uomp init
```

这会创建 `~/.uomp`、管理员令牌和 `sessions/` 目录。数据库和 Ed25519 密钥会在首次导入或授权时创建。

---

## 3. 先看一遍完整闭环（可选）

```bash
uomp demo
```

它会在临时目录里演示：导入 → 授权 → 允许读取 → 拒绝读取 → 审计 → 撤销。

**不会碰你真实的 `~/.uomp`。**

如果安装或环境有问题，运行：

```bash
uomp doctor
```

它会检查 Node、git、目录权限、密钥、数据库、会话文件和端口。

---

## 4. 导入笔记

把一个 Obsidian vault 或 Markdown 目录导入 UOMP：

```bash
uomp import ~/Obsidian/MyVault
```

先预览而不写入：

```bash
uomp import ~/Obsidian/MyVault --dry-run
```

导入规则：

- 递归处理 `.md` 文件
- 跳过 `.obsidian`、隐藏目录和 `node_modules`
- 目录路径变成授权范围：
  - `projects/uomp/plan.md` → `notes`、`notes/projects`、`notes/projects/uomp`
- frontmatter 的 `tags`、`title`、`description`、`sensitivity` 会保留
- 重复导入会更新已有笔记，不会重复创建

之后想同步最新修改，重新运行同一条 `uomp import` 即可。

---

## 5. 启动本地服务

MCP 客户端需要一个一直运行的本地服务。打开**终端 1**：

```bash
uomp serve
```

它会监听：

```text
http://127.0.0.1:9374
```

保持这个终端打开。按 `Ctrl+C` 可以停止服务，但**停止服务不会撤销已经发出的会话**；要立即失效请用 `uomp revoke`。

---

## 6. 授权一个 MCP 客户端

打开**终端 2**：

```bash
uomp authorize \
  --scope notes/projects \
  --output ~/.uomp/mcp-client.env \
  --no-server
```

说明：

- `--scope notes/projects`：只允许读取这个范围；`notes/journal` 等未授权范围会被拒绝
- `--output`：把 Token 写到固定路径，方便重复授权时覆盖
- `--no-server`：服务已经在终端 1 运行
- 默认不会把 JWT 打印到终端
- 会话默认 30 分钟；可以用 `--duration 15` 调整

成功后 CLI 会打印会话 ID、范围和 env 文件路径：

```text
Session granted: sess_...
  Agent     MCP Client (mcp-client)
  Scope     notes/projects
  Expires   2026-10-29 15:30 (30 min)

Env file
  /home/me/.uomp/mcp-client.env

Open a new terminal, then:
  source '/home/me/.uomp/mcp-client.env'

Revoke with: uomp revoke sess_...
```

如果你授权的是一个具体的 Agent 包，把 `uomp authorize` 后面的 `[agent]` 换成 Agent 路径即可；不传路径时使用的是内置的通用 MCP 客户端声明。

---

## 7. 配置你的 MCP 客户端

### Claude Desktop

```bash
uomp mcp --session ~/.uomp/mcp-client.env --print-config --client claude
```

把 stdout 里的 JSON 粘贴到 Claude Desktop 的 `claude_desktop_config.json`。CLI 会在 stderr 提示配置文件位置。

### Cursor

```bash
uomp mcp --session ~/.uomp/mcp-client.env --print-config --client cursor
```

把输出粘贴到项目里的 `.cursor/mcp.json`，或全局的 `~/.cursor/mcp.json`。

### OpenCode

```bash
uomp mcp --session ~/.uomp/mcp-client.env --print-config --client opencode
```

把输出保存到项目里的 `opencode.json`。生成的配置已经包含 `codemode: false`，会直接暴露 UOMP 工具。

配置完成后**重启客户端**（OpenCode 可以运行一次 `opencode mcp list`，等它显示 `uomp connected`）。

> MCP 支持目前是实验能力。OpenCode 已经验证过；Claude Desktop / Cursor 如果看不到工具，按下面的常见问题排查。

---

## 8. 在客户端里验证

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
ACCESS_DENIED: Key not in authorized scope
```

这说明范围控制生效了，拒绝也会写进审计。

---

## 9. 查看审计

回到终端：

```bash
uomp sessions
uomp audit --limit 20
```

只看最近 24 小时：

```bash
uomp audit --since 24h
```

只看拒绝：

```bash
uomp audit --result deny
```

按 key 过滤：

```bash
uomp audit --key note.projects.plan
```

脚本或后续 UI 可以用 JSON：

```bash
uomp audit --since 24h --result deny --json
```

审计会显示时间、结果、操作、Agent、目标、会话和原因。

---

## 10. 撤销

```bash
uomp revoke sess_...
```

撤销后：

- 下一个请求立即返回 `403`
- 默认路径下的 env 文件会被删除
- 自定义 `--output` 文件不会被自动删除，需要自己处理

如果只是关闭 `uomp serve`，token 不会立刻失效；一定要用 `uomp revoke` 才能真正收回访问。

### 会话过期后

重新执行同一条授权命令即可：

```bash
uomp authorize \
  --scope notes/projects \
  --output ~/.uomp/mcp-client.env \
  --no-server
```

MCP server 会在每次工具调用前重新读取 env 文件。使用固定 `--output` 路径时，重新授权后下一次调用会自动生效，**不需要重启客户端**。

---

## 11. 常见问题

| 问题 | 处理 |
|---|---|
| `uomp: command not found` | 把 `~/.local/bin` 加到 `PATH`，或重新打开终端 |
| `uomp doctor` 提示数据目录不存在 | 运行 `uomp init` |
| 端口 9374 被占用 | 停止占用进程；或 `uomp serve --port 9380` + `uomp authorize --port 9380` |
| 客户端看不到 UOMP 工具 | 确认 `uomp serve` 在运行；重启客户端；确认配置文件位置；OpenCode 等 `uomp connected` |
| 工具报 `SESSION_NOT_ACTIVE` | 会话过期或被撤销；重新 `uomp authorize` 到同一个 env 文件 |
| 工具报 `ACCESS_DENIED` | 该 key/tag 不在授权范围；检查 `--scope` 或查看 `uomp audit` |
| 会话 env 权限告警 | `uomp doctor` 会提示；按建议 `chmod 600 ~/.uomp/sessions/*.env` |
| 想清空所有本地数据 | 停止 `uomp serve`，删除 `~/.uomp`；这会删除笔记库、密钥和审计 |

### 数据在哪里

```text
~/.uomp/
├── memory.db          # 导入的笔记
├── auth.db            # 会话
├── audit.db           # 审计日志
├── sessions/          # 0600 会话 env 文件
└── .secrets/          # Ed25519 密钥 + 管理员令牌
```

### 如何彻底卸载

```bash
pkill -f "uomp serve" || true
rm -rf ~/.uomp
rm -f ~/.local/bin/uomp
```

---

## 12. 安全边界

UOMP 能做到：

- 本地优先，笔记默认不离开你的机器
- 按 tag/key 限定范围
- 会话过期和立即撤销
- 每一次允许/拒绝都有审计
- Token 存在 `0600` 文件里，默认不打印 JWT

UOMP 不能防止：

- 同一个 OS 用户下的恶意进程读取 `~/.uomp`
- root / 被攻陷的机器
- 被授权的 Agent 保留它已经读到的内容
- 备份或同步盘把 env 文件带到别处

不要把 `~/.uomp` 提交到 git，也不要把会话 env 文件发到公开渠道。

---

## 13. 进阶

- 想了解协议和 Token 格式：[规范 Draft-00](/spec/)
- 想写自己的 Agent：[README](https://github.com/0xSynapse/uomp-core#readme)
- 想用 TypeScript SDK：[SDK 设计](https://github.com/0xSynapse/uomp-core/tree/main/docs/sdk-design.md)
- 远程 Agent / Gateway 属于高级预览，不是本地流程的必需部分
