---
title: 'UOMP User Guide'
description: 'Install UOMP, import notes, connect Claude Desktop / Cursor, audit reads, and revoke access'
---

# UOMP User Guide

This guide is for a first-time UOMP user. By the end, you will have a local note store, a revocable agent session, and an audit log you can inspect.

Time: **5–10 minutes**. Your notes and tokens stay on your machine.

> **Tested on**: macOS and Linux terminals; Claude Desktop, Cursor, or OpenCode; a local Obsidian / Markdown vault. **Windows is not supported.**

---

## What you will do

1. Install UOMP
2. Use `uomp connect` to import notes, start the local service, authorize, and write the client config (or use on-demand consent)
3. Read notes from Claude Desktop / Cursor / OpenCode
4. Inspect the audit log and revoke

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

## 4. Import and connect an MCP client

### 4.1 One-command setup

```bash
uomp connect claude --vault ~/Obsidian/MyVault --scope notes/projects
```

This command:

- imports the Markdown vault (base tag `notes`; change it with `--vault-tag`)
- starts the local Auth + Guard service in the background (`http://127.0.0.1:9374`)
- creates a 30-minute session and writes the token to `~/.uomp/sessions/claude.env` (`0600`)
- merges the UOMP entry into the Claude Desktop config (an existing file is backed up)
- prints the expiry, renew command, and revoke command

The command exits and leaves the service running in the background. Use `uomp status` to inspect the server and active sessions, and `uomp stop` to stop it. Then **restart Claude Desktop** so it loads the new MCP config.

Cursor and OpenCode use the same command:

```bash
uomp connect cursor --vault ~/Obsidian/MyVault --scope notes/projects
uomp connect opencode --vault ~/Obsidian/MyVault --scope notes/projects
```

Common options:

- `--scope notes/projects` allows only this scope; `notes/journal` and other scopes are denied
- `--duration 15` changes the session length; the default is 30 minutes
- `--print-config` prints the JSON without writing the client config
- `--skip-config` grants the session without writing the client config
- `--foreground` keeps the server in this terminal so you can see its logs

### 4.2 High-sensitivity data

High-sensitivity tags (for example `portfolio:holdings`, or items imported with `sensitivity: high`) are never selected by default, and cannot be granted by tag alone.

In an interactive run (without `--scope`), UOMP lists the tags and then the keys under each high-sensitivity tag. Using the stock-analyst example (import its sample data first):

```bash
uomp connect ./examples/stock-analyst
```

In scripts, grant individual keys explicitly:

```bash
uomp connect ./examples/stock-analyst \
  --scope portfolio:holdings \
  --allow-key AAPL MSFT
```

Or explicitly allow every key under a high-sensitivity tag (this prints an override warning):

```bash
uomp connect ./examples/stock-analyst \
  --scope portfolio:holdings \
  --allow-high portfolio:holdings
```

Prefer `--allow-key` over `--allow-high`, and prefer the interactive picker over both.

### 4.3 On-demand consent (optional)

To defer authorization until the first tool call, add `--on-demand`:

```bash
uomp connect claude --vault ~/Obsidian/MyVault --scope notes/projects --on-demand
```

No session is created immediately. The first tool call:

1. creates a pending consent request
2. opens a local approval page (Linux/macOS also show a desktop notification)
3. continues the same tool call after you click Approve
4. creates a new request on the next call after Deny

If the page does not open, use the terminal fallback:

```bash
uomp pending
uomp approve <request-id>
uomp deny <request-id>
```

`--no-open` disables auto-open, `--no-notify` disables notifications, and `--consent-timeout 120` changes the wait time. When an on-demand token expires, the next tool call creates a new request.

### 4.4 Sync notes later

Run the import command again:

```bash
uomp import ~/Obsidian/MyVault
```

Import rules:

- recursively processes `.md` files
- skips `.obsidian`, hidden directories, and `node_modules`
- directory paths become scopes:
  - `projects/uomp/plan.md` → `notes`, `notes/projects`, `notes/projects/uomp`
- frontmatter `tags`, `title`, `description`, and `sensitivity` are preserved
- re-importing updates existing notes instead of duplicating them

> To run the server separately, or for an unsupported client, use the manual flow:
>
> ```bash
> # Terminal 1
> uomp serve
>
> # Terminal 2
> uomp authorize --scope notes/projects --output ~/.uomp/mcp-client.env --no-server
> uomp mcp --session ~/.uomp/mcp-client.env --print-config --client claude
> ```
>
> Paste the JSON into the client config. `connect` supports Claude Desktop, Cursor, and OpenCode; other clients can use `--print-config`.

---

## 5. Verify inside the client

If you used `--on-demand`, the first request opens the approval page; approve it to let the same request continue. If you deny it, the tool returns an approval-required message.

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

## 6. Inspect the audit log

Back in the terminal:

```bash
uomp status
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

## 7. Revoke

```bash
uomp revoke sess_...
```

After revocation:

- the next request returns `403` immediately
- the session's env files are removed (including the `claude.env` written by `connect`)
- the `uomp` entry in the client config remains; re-run `connect` to authorize again, or remove it manually
- a custom `--output` file outside `~/.uomp/sessions` is not removed automatically

Stopping `uomp connect` / `uomp serve` / `uomp stop` does **not** revoke the token. Use `uomp revoke` to actually remove access.

To remove the client config as well:

```bash
uomp disconnect claude
```

This removes the `uomp` entry from the Claude Desktop config, revokes the current session, and deletes the matching env file.

An on-demand request has no active session until it is approved; after approval, use `uomp revoke` or `uomp disconnect` the same way.

### After the session expires

Run the same connect command again:

```bash
uomp connect claude --scope notes/projects
```

The MCP server re-reads the env file before every tool call. Re-running `connect` revokes the previous session for the same env file, writes a new token, and the next call picks it up **without restarting the client**.

---

## 8. Troubleshooting

| Problem | Fix |
|---|---|
| `uomp: command not found` | Add `~/.local/bin` to `PATH`, or open a new terminal |
| `uomp doctor` says the data directory is missing | Run `uomp init` |
| Port 9374 is occupied | Run `uomp stop` first; or `uomp start --port 9380` + `uomp connect ... --port 9380 --no-server` |
| The client does not show UOMP tools | Use `uomp status` to confirm the background server is running; restart the client; check the config path; for OpenCode wait for `uomp connected` |
| The tool says `UOMP approval required` | Open the approval page from the message, or run `uomp pending` / `uomp approve <request-id>` |
| `SESSION_NOT_ACTIVE` | The session expired or was revoked; run `uomp connect claude --scope notes/projects` again; on-demand mode creates a new request |
| `ACCESS_DENIED` | The key/tag is outside the granted scope; check `--scope` or `uomp audit` |
| High-sensitivity data is unreadable | High-sensitivity keys must be granted explicitly; use the interactive picker or `--allow-key` / `--allow-high` |
| Env-file permission warning | `uomp doctor` suggests the fix, usually `chmod 600 ~/.uomp/sessions/*.env` |
| Reset all local data | Run `uomp stop`, then remove `~/.uomp`; use `pkill -f "uomp serve"` if needed. This deletes notes, keys, and audit data |
| Running on Windows | Windows is not supported; use macOS or Linux |

### Where data lives

```text
~/.uomp/
├── memory.db          # imported notes
├── auth.db            # sessions
├── audit.db           # audit log
├── sessions/          # 0600 session env files
├── server.json        # background server state
├── server.log         # background server log
└── .secrets/          # Ed25519 key + admin token
```

### Uninstall

```bash
uomp stop || true
pkill -f "uomp serve" || true
rm -rf ~/.uomp
rm -f ~/.local/bin/uomp
```

---

## 9. Security boundaries

UOMP provides:

- local-first storage; notes stay on your machine by default
- tag/key scope enforcement
- high-sensitivity tags are off by default; high-sensitivity items require explicit keys
- on-demand approval links carry a one-time secret and stay on loopback
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

## 10. Advanced

- Protocol and token format: [Draft-00 specification](/en/spec/)
- Build your own agent: [README](https://github.com/0xSynapse/uomp-core#readme)
- TypeScript SDK: [SDK design](https://github.com/0xSynapse/uomp-core/tree/main/docs/sdk-design.en.md)
- Remote agents / Gateway are advanced preview features, not required for the local workflow
