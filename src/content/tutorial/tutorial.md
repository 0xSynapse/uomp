---
title: 'UOMP 用户指南'
description: '从安装、导入笔记到在 Claude Desktop / Cursor 中连接、授权读取、审计和撤销'
---

# UOMP 用户指南

这份指南面向第一次使用 UOMP 的真实用户。完成后，你会有一个本地笔记库、一个可撤销的 Agent 会话，以及一份可查看的访问审计。

预计时间：**5–10 分钟**。所有笔记和 Token 都留在你的电脑上。

> **适用环境**：macOS 或 Linux 终端；Claude Desktop、Cursor 或 OpenCode；本地 Obsidian / Markdown 笔记库。Windows 可通过 WSL 或 Git Bash 使用，但尚未完整验证。

---

## 你将完成什么

1. 安装 UOMP
2. 用 `uomp connect` 导入笔记、启动本地服务、授权并写客户端配置
3. 在 Claude Desktop / Cursor / OpenCode 里读取笔记
4. 查看审计，然后撤销

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

## 4. 导入并连接 MCP 客户端

一条命令完成导入、授权和客户端配置：

```bash
uomp connect claude --vault ~/Obsidian/MyVault --scope notes/projects
```

这条命令会：

- 导入 Markdown 笔记库（默认基础 tag 是 `notes`，可用 `--vault-tag` 修改）
- 在后台启动本地 Auth + Guard 服务（`http://127.0.0.1:9374`）
- 创建 30 分钟会话，把 token 写入 `~/.uomp/sessions/claude.env`（权限 `0600`）
- 把 UOMP 条目合并进 Claude Desktop 配置（已有配置会先备份）
- 打印到期时间、续期命令和撤销命令

命令执行完会退出，服务继续在后台运行。用 `uomp status` 查看服务和活跃会话，用 `uomp stop` 停止服务。然后**重启 Claude Desktop**，让它加载新的 MCP 配置。

Cursor / OpenCode 用同样的方式：

```bash
uomp connect cursor --vault ~/Obsidian/MyVault --scope notes/projects
uomp connect opencode --vault ~/Obsidian/MyVault --scope notes/projects
```

说明：

- `--scope notes/projects`：只允许读取这个范围；`notes/journal` 等未授权范围会被拒绝
- 会话默认 30 分钟；可以用 `--duration 15` 调整
- `--print-config` 只打印 JSON，不写客户端配置
- `--skip-config` 只授权，不写客户端配置
- `--foreground` 让 server 留在当前终端，方便看日志

高敏 tag（例如 `portfolio:holdings`，或以 `sensitivity: high` 导入的数据）默认不会被选中。交互运行时先选 tag，再逐个选择 key；脚本里用 `--allow-key <key...>` 或 `--allow-high <tag...>` 显式授权。

如果不想预先授权，可以加 `--on-demand`。第一次工具调用会创建待审批请求，然后在终端运行 `uomp pending` 和 `uomp approve <request-id>`；下一次调用就会拿到 token。

之后想同步最新修改，重新运行 `uomp import ~/Obsidian/MyVault`。导入规则：

- 递归处理 `.md` 文件
- 跳过 `.obsidian`、隐藏目录和 `node_modules`
- 目录路径变成授权范围：
  - `projects/uomp/plan.md` → `notes`、`notes/projects`、`notes/projects/uomp`
- frontmatter 的 `tags`、`title`、`description`、`sensitivity` 会保留
- 重复导入会更新已有笔记，不会重复创建

> 如果你想分开运行 server，或者客户端不在支持列表里，用手动流程：
>
> ```bash
> # 终端 1
> uomp serve
>
> # 终端 2
> uomp authorize --scope notes/projects --output ~/.uomp/mcp-client.env --no-server
> uomp mcp --session ~/.uomp/mcp-client.env --print-config --client claude
> ```
>
> 把输出的 JSON 粘贴到客户端配置。`connect` 支持 Claude Desktop、Cursor、OpenCode；其他客户端用 `--print-config` 手动接入。

---

## 5. 在客户端里验证

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

## 6. 查看审计

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

## 7. 撤销

```bash
uomp revoke sess_...
```

撤销后：

- 下一个请求立即返回 `403`
- 会话对应的 env 文件会被删除（包括 `connect` 生成的 `claude.env`）
- 客户端配置里的 `uomp` 条目会保留；重新 `connect` 即可再次授权，或手动删除该条目
- 自定义 `--output` 且不在 `~/.uomp/sessions` 下的文件不会被自动删除

如果只是关闭 `uomp connect` / `uomp serve` / 执行 `uomp stop`，token 不会立刻失效；一定要用 `uomp revoke` 才能真正收回访问。

如果想连同客户端配置一起移除：

```bash
uomp disconnect claude
```

它会删除 Claude Desktop 配置里的 `uomp` 条目、撤销当前会话，并清理对应的 env 文件。

### 会话过期后

重新执行同一条连接命令即可：

```bash
uomp connect claude --scope notes/projects
```

MCP server 会在每次工具调用前重新读取 env 文件。重新执行 `connect` 会先撤销同一 env 文件里的旧会话，再写入新 token，下一次调用会自动生效，**不需要重启客户端**。

---

## 8. 常见问题

| 问题 | 处理 |
|---|---|
| `uomp: command not found` | 把 `~/.local/bin` 加到 `PATH`，或重新打开终端 |
| `uomp doctor` 提示数据目录不存在 | 运行 `uomp init` |
| 端口 9374 被占用 | 停止占用进程；或 `uomp connect claude --port 9380 --scope notes/projects` |
| 客户端看不到 UOMP 工具 | `uomp status` 确认后台服务在运行；重启客户端；检查配置文件位置；OpenCode 等 `uomp connected` |
| 工具报 `SESSION_NOT_ACTIVE` | 会话过期或被撤销；重新 `uomp connect claude --scope notes/projects` |
| 工具报 `ACCESS_DENIED` | 该 key/tag 不在授权范围；检查 `--scope` 或查看 `uomp audit` |
| 会话 env 权限告警 | `uomp doctor` 会提示；按建议 `chmod 600 ~/.uomp/sessions/*.env` |
| 想清空所有本地数据 | 停止 `uomp connect` / `uomp serve`，删除 `~/.uomp`；这会删除笔记库、密钥和审计 |

### 数据在哪里

```text
~/.uomp/
├── memory.db          # 导入的笔记
├── auth.db            # 会话
├── audit.db           # 审计日志
├── sessions/          # 0600 会话 env 文件
├── server.json        # 后台服务状态
├── server.log         # 后台服务日志
└── .secrets/          # Ed25519 密钥 + 管理员令牌
```

### 如何彻底卸载

```bash
uomp stop || true
pkill -f "uomp serve" || true
rm -rf ~/.uomp
rm -f ~/.local/bin/uomp
```

---

## 9. 安全边界

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

## 10. 进阶

- 想了解协议和 Token 格式：[规范 Draft-00](/spec/)
- 想写自己的 Agent：[README](https://github.com/0xSynapse/uomp-core#readme)
- 想用 TypeScript SDK：[SDK 设计](https://github.com/0xSynapse/uomp-core/tree/main/docs/sdk-design.md)
- 远程 Agent / Gateway 属于高级预览，不是本地流程的必需部分
