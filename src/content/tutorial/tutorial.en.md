---
title: 'UOMP User Guide'
description: 'Install UOMP, import notes, authorize Claude Desktop / Cursor, audit reads, and revoke access'
---

# UOMP User Guide

This guide is for a first-time UOMP user. By the end, you will have a local note store, a revocable agent session, and an audit log you can inspect.

Time: **10–15 minutes**. Your notes and tokens stay on your machine.

> **Tested on**: macOS and Linux terminals; Claude Desktop, Cursor, or OpenCode; a local Obsidian / Markdown vault. Windows may work through WSL or Git Bash, but is not fully validated.

---

## What you will do

1. Install UOMP
2. Import an Obsidian / Markdown vault
3. Start the local Auth + Guard service
4. Grant an MCP client a 30-minute, scoped session
5. Read notes from Claude Desktop / Cursor / OpenCode
6. Inspect the audit log and revoke

---

## 1. Prerequisites

You need:

- Node.js **22 or newer**
- `git`
- An MCP client: Claude Desktop, Cursor, or OpenCode
- An Obsidian vault or a Markdown directory

Check Node:

```bash
node --version
```

Upgrade Node.js if it is below v22.

---

## 2. Install

In a terminal:

```bash
curl -fsSL https://www.uomp.org/install.sh | bash
```

The installer:

- clones UOMP into `~/.uomp/cli`
- builds the CLI
- links `uomp` into `~/.local/bin`

If `uomp` is not on your `PATH`, the script prints the line to add, for example:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Open a new terminal and verify:

```bash
uomp --version
```

Initialize the local data directory:

```bash
uomp init
```

This creates `~/.uomp`, the admin token, and the `sessions/` directory. Databases and the Ed25519 key are created on the first import or authorization.

---

## 3. See the loop first (optional)

```bash
uomp demo
```

It runs import → authorize → allowed read → denied read → audit → revoke in a temporary directory.

**It does not touch your real `~/.uomp`.**

If installation or configuration is wrong, run:

```bash
uomp doctor
```

It checks Node, git, directory permissions, keys, databases, session files, and the local port.

---

## 4. Import notes

Import an Obsidian vault or a Markdown directory:

```bash
uomp import ~/Obsidian/MyVault
```

Preview without writing:

```bash
uomp import ~/Obsidian/MyVault --dry-run
```

Import rules:

- recursively processes `.md` files
- skips `.obsidian`, hidden directories, and `node_modules`
- directory paths become scopes:
  - `projects/uomp/plan.md` → `notes`, `notes/projects`, `notes/projects/uomp`
- frontmatter `tags`, `title`, `description`, and `sensitivity` are preserved
- re-importing updates existing notes instead of duplicating them

To sync later, run the same `uomp import` command again.

---

## 5. Start the local service

MCP clients need a local service that stays running. Open **Terminal 1**:

```bash
uomp serve
```

It listens on:

```text
http://127.0.0.1:9374
```

Keep this terminal open. `Ctrl+C` stops the service, but **stopping the service does not revoke issued sessions**. Use `uomp revoke` for that.

---

## 6. Authorize an MCP client

Open **Terminal 2**:

```bash
uomp authorize \
  --scope notes/projects \
  --output ~/.uomp/mcp-client.env \
  --no-server
```

What this does:

- `--scope notes/projects` allows only this scope; `notes/journal` and other scopes are denied
- `--output` writes the token to a stable env file that can be overwritten on re-authorization
- `--no-server` uses the service already running in Terminal 1
- the JWT is not printed to the terminal by default
- the session lasts 30 minutes by default; use `--duration 15` to change it

On success, the CLI prints the session ID, scope, and env path:

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

If you are authorizing a specific agent package, pass its path after `uomp authorize`. With no path, UOMP uses the built-in generic MCP client manifest.

---

## 7. Configure your MCP client

### Claude Desktop

```bash
uomp mcp --session ~/.uomp/mcp-client.env --print-config --client claude
```

Paste the JSON from stdout into Claude Desktop's `claude_desktop_config.json`. The CLI prints the config path on stderr.

### Cursor

```bash
uomp mcp --session ~/.uomp/mcp-client.env --print-config --client cursor
```

Paste the output into `.cursor/mcp.json` in your project, or `~/.cursor/mcp.json` globally.

### OpenCode

```bash
uomp mcp --session ~/.uomp/mcp-client.env --print-config --client opencode
```

Save the output as `opencode.json` in your project. The generated config already includes `codemode: false`, so the UOMP tools are exposed directly.

Restart the client after saving. For OpenCode, wait until `opencode mcp list` shows `uomp connected`.

> MCP support is experimental. OpenCode has been validated; if Claude Desktop or Cursor does not show the tools, see Troubleshooting below.

---

## 8. Verify inside the client

In Claude Desktop / Cursor / OpenCode, ask:

```text
List the notes under notes/projects
```

Then:

```text
Search notes/projects for "Ship" and read the matching note
```

UOMP exposes three tools:

- `list_memory`: keys and metadata, no note content
- `search_memory`: search within an authorized tag, no note content
- `read_memory`: read the content for one key

Now try an unauthorized note:

```text
Read note.journal.private
```

You should get:

```text
ACCESS_DENIED: Key not in authorized scope
```

That proves scope enforcement works, and the denial is written to the audit log.

---

## 9. Inspect the audit log

Back in the terminal:

```bash
uomp sessions
uomp audit --limit 20
```

Last 24 hours:

```bash
uomp audit --since 24h
```

Denied entries only:

```bash
uomp audit --result deny
```

Filter by key:

```bash
uomp audit --key note.projects.plan
```

For scripts or a future UI:

```bash
uomp audit --since 24h --result deny --json
```

Audit entries show time, result, action, agent, target, session, and reason.

---

## 10. Revoke

```bash
uomp revoke sess_...
```

After revocation:

- the next request returns `403` immediately
- the default env file is removed
- a custom `--output` file is not removed automatically

Stopping `uomp serve` does **not** revoke the token. Use `uomp revoke` to actually remove access.

### After the session expires

Run the same authorization command again:

```bash
uomp authorize \
  --scope notes/projects \
  --output ~/.uomp/mcp-client.env \
  --no-server
```

The MCP server re-reads the env file before every tool call. With a fixed `--output` path, the next call picks up the new token **without restarting the client**.

---

## 11. Troubleshooting

| Problem | Fix |
|---|---|
| `uomp: command not found` | Add `~/.local/bin` to `PATH`, or open a new terminal |
| `uomp doctor` says the data directory is missing | Run `uomp init` |
| Port 9374 is occupied | Stop the other process; or use `uomp serve --port 9380` and `uomp authorize --port 9380` |
| The client does not show UOMP tools | Confirm `uomp serve` is running; restart the client; check the config path; for OpenCode wait for `uomp connected` |
| `SESSION_NOT_ACTIVE` | The session expired or was revoked; re-authorize to the same env file |
| `ACCESS_DENIED` | The key/tag is outside the granted scope; check `--scope` or `uomp audit` |
| Env-file permission warning | `uomp doctor` suggests the fix, usually `chmod 600 ~/.uomp/sessions/*.env` |
| Reset all local data | Stop `uomp serve`, then remove `~/.uomp`; this deletes notes, keys, and audit data |

### Where data lives

```text
~/.uomp/
├── memory.db          # imported notes
├── auth.db            # sessions
├── audit.db           # audit log
├── sessions/          # 0600 session env files
└── .secrets/          # Ed25519 key + admin token
```

### Uninstall

```bash
pkill -f "uomp serve" || true
rm -rf ~/.uomp
rm -f ~/.local/bin/uomp
```

---

## 12. Security boundaries

UOMP provides:

- local-first storage; notes stay on your machine by default
- tag/key scope enforcement
- session expiry and immediate revocation
- an audit record for every allow/deny decision
- tokens in `0600` files, with no JWT printed by default

UOMP does not protect against:

- a malicious process running as the same OS user that can read `~/.uomp`
- root or a compromised machine
- an authorized agent retaining content it has already read
- backups or sync tools copying the env file elsewhere

Do not commit `~/.uomp` to git, and do not share session env files publicly.

---

## 13. Advanced

- Protocol and token format: [Draft-00 specification](/en/spec/)
- Build your own agent: [README](https://github.com/0xSynapse/uomp-core#readme)
- TypeScript SDK: [SDK design](https://github.com/0xSynapse/uomp-core/tree/main/docs/sdk-design.en.md)
- Remote agents / Gateway are advanced preview features, not required for the local workflow
