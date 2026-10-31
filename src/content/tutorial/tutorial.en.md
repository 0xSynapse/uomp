---
title: 'UOMP User Guide'
description: 'Install Aegis OS, import notes, connect Claude Desktop / Cursor, approve access on demand, audit, and revoke'
---

# UOMP User Guide

This guide is for a first-time UOMP user. By the end you will have a local notes store, a revocable Agent session, and a readable access audit.

Estimated time: **5–10 minutes**. All notes and tokens stay on your machine.

> Product overview: [Aegis OS overview](https://heurion.org/en/aegis-os/) · [Aegis OS tutorial](https://heurion.org/en/aegis-os/tutorial/)

> **Supported environment:** macOS or Linux terminal; Claude Desktop, Cursor, or OpenCode; a local Obsidian / Markdown vault. **Windows is not supported.**

---

## What you will do

1. Install Aegis OS
2. Run `aegis-os memory setup` to import notes, start the local server, and write the client config (no access granted)
3. Make the first request from the client and approve the consent request in the CLI
4. Read notes
5. Review the audit and revoke access

---

## 1. Requirements

You need:

- Aegis OS
- An MCP client: Claude Desktop, Cursor, or OpenCode
- An Obsidian vault or a plain Markdown directory

Node.js, pnpm, and the `uomp` binary are **not** required. Every `aegis-os memory` command is native Rust.

Check:

```bash
aegis-os --version
aegis-os memory --help
```

---

## 2. Install

```bash
brew tap heurion-org/aegis-os https://github.com/heurion-org/aegis-os.git
brew trust heurion-org/aegis-os
brew install aegis-os
```

Verify:

```bash
aegis-os --version
aegis-os doctor
aegis-os memory --help
```

---

## 3. One-time setup

```bash
aegis-os memory setup claude --vault ~/Obsidian/MyVault
```

This command:

- imports the Markdown vault (base tag `notes` by default; use `--tag` to change it)
- starts `aegis-os memory serve` in the background if it is not already running (default `http://127.0.0.1:9374`)
- writes the `~/.uomp/sessions/claude.env` bridge profile
- merges a `uomp` MCP entry into the Claude Desktop config
- **issues no token and grants no access**

The command exits; the server keeps running. **Restart Claude Desktop** so it loads the new MCP config.

Cursor / OpenCode work the same way:

```bash
aegis-os memory setup cursor --vault ~/Obsidian/MyVault
aegis-os memory setup opencode --vault ~/Obsidian/MyVault
```

Default config paths:

- Claude Desktop: `~/.config/Claude/claude_desktop_config.json` (`~/Library/Application Support/Claude/` on macOS)
- Cursor: `~/.cursor/mcp.json`
- OpenCode: `~/.config/opencode/opencode.json`

Use `--config` for a custom path, or `--listen 127.0.0.1:9380` to change the port.

---

## 4. First request

Open Claude Desktop and ask:

```text
List the notes under notes/projects
```

Claude calls UOMP's `list_memory(tag="notes/projects")`. The MCP bridge will:

1. create a consent request through `UOMP_BRIDGE_FILE`
2. print the request id and approval command to stderr
3. wait for your approval (120 seconds by default)

In a terminal:

```bash
aegis-os memory pending
aegis-os memory approve <request-id>
```

`pending` shows the request id, Agent, session id, and expiry. After approval the **current tool call continues**; a denial returns an error and the next call creates a new request.

```bash
aegis-os memory deny <request-id>
```

The browser consent page is deferred; CLI approval is the native path for now. An Agent cannot approve its own request.

After the token expires or is revoked, the next tool call creates a new consent request; you do not need to rerun `setup`.

### High-sensitivity data

High-sensitivity tags (for example `portfolio:holdings`, or items imported with `sensitivity: high`) are not covered by a tag scope. The Agent must call `read_memory` for a specific key; the consent request carries that key, and you approve it in `pending`.

Do not grant high-sensitivity data with a blanket tag scope.

---

## 5. Re-import notes

Run the import command again:

```bash
aegis-os memory import ~/Obsidian/MyVault
```

Import rules:

- recursive `.md` files
- skips `.obsidian`, hidden directories, and `node_modules`
- directory paths become scopes:
  - `projects/uomp/plan.md` → `notes`, `notes/projects`, `notes/projects/uomp`
- frontmatter `tags`, `title`, `description`, and `sensitivity` are preserved
- re-importing updates existing notes instead of duplicating them

---

## 6. Manual flow and pre-authorization

If your client is not in the supported list, or you want to run the server separately:

```bash
# terminal 1
aegis-os memory serve

# terminal 2: write a bridge profile + custom client config
aegis-os memory setup my-client --no-server --config /path/to/mcp.json
```

`setup` writes a standard `mcpServers` structure (OpenCode uses `mcp`). Copy the `uomp` entry into your client.

For scripts that need to skip approval, use `connect`:

```bash
aegis-os memory connect claude --scope notes/projects
```

`connect` immediately creates and approves a 30-minute session, writes the token to `~/.uomp/sessions/claude.env`, and configures the client with `UOMP_TOKEN_FILE`. It is intended for scripts and CI; prefer `setup` + CLI approval for daily use.

---

## 7. Verify in the client

In Claude Desktop / Cursor / OpenCode, ask:

```text
List the notes under notes/projects
```

Then:

```text
Search notes/projects for "Ship" and read the matching note
```

UOMP exposes three tools:

- `list_memory`: lists keys and metadata, no body
- `search_memory`: searches inside an authorized tag, no body
- `read_memory`: reads one body by key

Try an unauthorized note:

```text
Read note.journal.private
```

You should see something like:

```text
ACCESS_DENIED: key is outside the token scope
```

This proves scope enforcement is working, and the denial is audited.

---

## 8. UOMP in multi-agent A2A tasks

Aegis OS uses Google A2A for multi-agent collaboration. A UOMP consent/session can be bound to an A2A task:

```bash
# 1. Create an A2A task
aegis-os ipc request --to worker --subject "Review auth" --message "Read the auth module"

# 2. Read the task id
aegis-os a2a board
aegis-os a2a show <task-id>

# 3. Give the MCP bridge task context (client environment)
export UOMP_TASK_ID=<task-id>

# 4. After approval, inspect sessions by task
aegis-os memory sessions --task-id <task-id>
```

When bound:

- `memory pending` shows the task id
- the approved session inherits the task ownership
- a terminal task makes the gateway revoke its sessions
- `memory revoke` moves the bound task to `input-required`

See the [Aegis OS tutorial](https://heurion.org/en/aegis-os/tutorial/#a2a) for the full A2A flow.

---

## 9. Review the audit

Back in the terminal:

```bash
aegis-os memory status
aegis-os memory sessions
aegis-os memory sessions --task-id <task-id>
aegis-os memory audit --limit 20
```

`status` shows the local store count and tags; `sessions` shows session state; `sessions --task-id` shows only sessions bound to one A2A task; `audit` shows recent allow/deny events with Agent, session, task, resource, and reason.

Check that the server is running:

```bash
curl -s http://127.0.0.1:9374/health
```

---

## 10. Revoke and stop

List sessions:

```bash
aegis-os memory sessions
```

Revoke one session:

```bash
aegis-os memory revoke <session-id>
```

The next request immediately returns `401 SESSION_NOT_ACTIVE`. If the session is bound to an A2A task, the task moves to `input-required` (marked `BLOCKED` on `a2a board`). If you use a custom `--runtime-dir`, pass the same runtime directory to `memory revoke`.

Remove the client config as well:

```bash
aegis-os memory disconnect claude
```

`disconnect` removes the `uomp` entry from the client config, revokes the session in the env file (the `connect` path), and deletes the env file. A `setup` bridge env has no session id; use `memory sessions` + `memory revoke` for that session.

Stop the background server:

```bash
aegis-os memory stop
```

`stop` only stops the server; it does not immediately revoke issued sessions. Sessions still expire at their expiry time. Use `revoke` or `disconnect` to remove access immediately.

### After a session expires

In `setup` mode, the next tool call creates a new consent request; approve it and continue without rerunning `setup`.

For the pre-authorized path (`connect`), rerun the same command:

```bash
aegis-os memory connect claude --scope notes/projects
```

The MCP server checks the token before each tool call, so the next call uses the new token **without restarting the client**.

---

## 11. Troubleshooting

| Problem | Fix |
|---|---|
| Client does not show UOMP tools | Check the `uomp` entry in the client config; restart the client; confirm the server with `curl -s http://127.0.0.1:9374/health` |
| Port 9374 is in use | `aegis-os memory stop`; or `aegis-os memory setup claude --listen 127.0.0.1:9380 ...` |
| Tool waits for approval forever | In another terminal run `aegis-os memory pending`, then `approve` / `deny` |
| `SESSION_NOT_ACTIVE` | Session expired or was revoked; make a new request, or run `aegis-os memory connect claude --scope notes/projects` |
| `ACCESS_DENIED` | The key/tag is outside the granted scope; inspect the consent request scope or `aegis-os memory audit` |
| High-sensitivity data is unreadable | High-sensitivity items require a per-key request and approval; a tag scope does not cover them |
| Task does not change with a custom runtime | Pass the same `--runtime-dir` to `a2a` / `memory revoke` |
| Reset all local data | `aegis-os memory stop`, then delete `~/.uomp`. This removes notes, keys, and audit |
| Run on Windows | Not supported; use macOS or Linux |

### Where data lives

```text
~/.uomp/
├── memory.db          # imported notes
├── auth.db            # sessions, consent requests, audit
├── sessions/          # 0600 bridge / token env files
├── server.pid         # background server pid
└── .secrets/          # Ed25519 keys, admin token, bridge token
```

### Full uninstall

```bash
aegis-os memory stop || true
rm -rf ~/.uomp
```

If setup wrote a client config, run `aegis-os memory disconnect <client>` or remove the `uomp` entry manually.

---

## 12. Security boundary

UOMP provides:

- local-first storage; notes do not leave your machine by default
- tag/key scope limits
- high-sensitivity items require explicit key approval
- the first tool call creates a consent request; the user approves it in the local CLI
- session expiry and immediate revocation
- an audit record for every allow/deny decision
- the bridge profile holds no token; pre-authorized tokens live in `0600` files, with no JWT printed by default

UOMP does not protect against:

- a malicious process running as the same OS user that can read `~/.uomp`
- root or a compromised machine
- an authorized agent retaining content it has already read
- backups or sync tools copying the env file elsewhere

Do not commit `~/.uomp` to git, and do not share session env files publicly.

---

## 13. Advanced

- Protocol and token format: [Draft-00 specification](/en/spec/)
- Aegis OS install and multi-agent tutorial: [Aegis OS Tutorial](https://heurion.org/en/aegis-os/tutorial/)
- Build your own agent: [Aegis OS UOMP module](https://github.com/heurion-org/aegis-os/tree/main/modules/uomp)
- MCP clients: `aegis-os memory mcp` (see the module README)
- Remote agents / Gateway are advanced preview features, not required for the local workflow
