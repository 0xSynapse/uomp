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

1. Install Aegis OS
2. Use `aegis-os memory setup` to import notes, start the local service, and write the client config (no access yet)
3. Make the first request from the client and approve the UOMP consent page
4. Read notes
5. Inspect the audit log and revoke

---

## 1. Prerequisites

You need:

- Aegis OS
- An MCP client: Claude Desktop, Cursor, or OpenCode
- An Obsidian vault or a Markdown directory

During migration, `aegis-os memory` delegates to the UOMP reference CLI, so you also need:

- Node.js **22 or newer**
- `git`

Node/git will not be required after the native cutover.

Check:

```bash
aegis-os --version
node --version
```

---

## 2. Install

```bash
brew install aegis-os
```

Verify:

```bash
aegis-os --version
aegis-os memory --help
```

During migration, `aegis-os memory` calls the `uomp` reference CLI. If `uomp` is not on `PATH`:

```bash
export UOMP_BIN=/path/to/uomp
```

The first `aegis-os memory setup` or `aegis-os memory connect` creates `~/.uomp`, the admin token, and the `sessions/` directory. Run `aegis-os memory init` separately only if you want to prepare the data directory in advance.

---

## 3. See the loop first (optional)

```bash
aegis-os memory demo
```

It runs import → authorize → allowed read → denied read → audit → revoke in a temporary directory.

**It does not touch your real `~/.uomp`.**

If installation or configuration is wrong, run:

```bash
aegis-os memory doctor
```

It checks Node, git, directory permissions, keys, databases, session files, and the local port.

---

## 4. Set up once and start using it

### 4.1 Set up the client

```bash
aegis-os memory setup claude --vault ~/Obsidian/MyVault
```

This command:

- imports the Markdown vault (base tag `notes`; change it with `--vault-tag`)
- starts the local Auth + Guard service in the background (`http://127.0.0.1:9374`)
- merges the UOMP entry into the Claude Desktop config (an existing file is backed up)
- **does not grant any access**

The command exits and leaves the service running in the background. Then **restart Claude Desktop** so it loads the new MCP config.

Cursor and OpenCode use the same command:

```bash
aegis-os memory setup cursor --vault ~/Obsidian/MyVault
aegis-os memory setup opencode --vault ~/Obsidian/MyVault
```

### 4.2 The first request

Open Claude Desktop and ask:

```text
List notes under notes/projects
```

Claude calls UOMP's `list_memory(tag="notes/projects")`. UOMP then:

1. creates a pending consent request
2. opens a local approval page (Linux/macOS also show a desktop notification)
3. shows who is asking, the scope, and the duration
4. continues the same tool call after you click Approve
5. creates a new request on the next call after Deny

If the page does not open, use the terminal fallback:

```bash
aegis-os memory pending
aegis-os memory approve <request-id>
aegis-os memory deny <request-id>
```

When the token expires, the next tool call creates a new request; no need to re-run `setup`.

### 4.3 High-sensitivity data

High-sensitivity tags (for example `portfolio:holdings`, or items imported with `sensitivity: high`) are never selected by default, and cannot be granted by tag alone.

The approval page lists the keys under each high-sensitivity tag and leaves them unchecked. The agent can only read the keys you select.

For scripts, skip the page with `aegis-os memory connect`:

```bash
aegis-os memory connect ./examples/stock-analyst \
  --scope portfolio:holdings \
  --allow-key AAPL MSFT
```

Or explicitly allow every key under a high-sensitivity tag (this prints an override warning):

```bash
aegis-os memory connect ./examples/stock-analyst \
  --scope portfolio:holdings \
  --allow-high portfolio:holdings
```

`aegis-os memory connect` is the advanced pre-authorize path; normal use is `aegis-os memory setup` + the approval page.

### 4.4 Sync notes later

Run the import command again:

```bash
aegis-os memory import ~/Obsidian/MyVault
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
> aegis-os memory serve
>
> # Terminal 2
> aegis-os memory authorize --scope notes/projects --output ~/.uomp/mcp-client.env --no-server
> aegis-os memory mcp --session ~/.uomp/mcp-client.env --print-config --client claude
> ```
>
> Paste the JSON into the client config. `connect` supports Claude Desktop, Cursor, and OpenCode; other clients can use `--print-config`.

---

## 5. Verify inside the client

The first request opens the approval page; approve it to let the same request continue. If you deny it, the tool returns an approval-required message.

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
aegis-os memory status
aegis-os memory sessions
aegis-os memory audit --limit 20
```

Last 24 hours:

```bash
aegis-os memory audit --since 24h
```

Denied entries only:

```bash
aegis-os memory audit --result deny
```

Filter by key:

```bash
aegis-os memory audit --key note.projects.plan
```

For scripts or a future UI:

```bash
aegis-os memory audit --since 24h --result deny --json
```

Audit entries show time, result, action, agent, target, session, and reason.

---

## 7. Revoke

```bash
aegis-os memory revoke sess_...
```

After revocation:

- the next request returns `403` immediately
- the session's env files are removed (including the `claude.env` written by `connect`)
- the `uomp` entry in the client config remains; re-run `connect` to authorize again, or remove it manually
- a custom `--output` file outside `~/.uomp/sessions` is not removed automatically

Stopping `aegis-os memory connect` / `aegis-os memory serve` / `aegis-os memory stop` does **not** revoke the token. Use `aegis-os memory revoke` to actually remove access.

To remove the client config as well:

```bash
aegis-os memory disconnect claude
```

This removes the `uomp` entry from the Claude Desktop config, revokes the current session, and deletes the matching env file.

In `setup` mode there is no active session until the first request is approved; after approval, use `aegis-os memory revoke` or `aegis-os memory disconnect` the same way.

### After the session expires

In `setup` mode, the next tool call creates a new approval request; approve it and the call continues. No need to re-run `setup`.

If you are using the pre-authorize path (`aegis-os memory connect`), run it again:

```bash
aegis-os memory connect claude --scope notes/projects
```

The MCP server re-reads the env file before every tool call. Re-running `connect` revokes the previous session for the same env file, writes a new token, and the next call picks it up **without restarting the client**.

---

## 8. Troubleshooting

| Problem | Fix |
|---|---|
| `uomp: command not found` | Add `~/.local/bin` to `PATH`, or open a new terminal |
| `aegis-os memory doctor` says the data directory is missing | Run `aegis-os memory setup claude ...` or `aegis-os memory init` |
| Port 9374 is occupied | Run `aegis-os memory stop` first; or `aegis-os memory setup claude --port 9380 ...` |
| The client does not show UOMP tools | Use `aegis-os memory status` to confirm the background server is running; restart the client; check the config path; for OpenCode wait for `aegis-os memory connected` |
| The tool says `UOMP approval required` | Open the approval page from the message, or run `aegis-os memory pending` / `aegis-os memory approve <request-id>` |
| `SESSION_NOT_ACTIVE` | The session expired or was revoked; make a new request from the client, or run `aegis-os memory connect claude --scope notes/projects` |
| `ACCESS_DENIED` | The key/tag is outside the granted scope; check the approval page, `--scope`, or `aegis-os memory audit` |
| High-sensitivity data is unreadable | High-sensitivity keys must be granted explicitly; select them on the approval page or use `--allow-key` / `--allow-high` |
| Env-file permission warning | `aegis-os memory doctor` suggests the fix, usually `chmod 600 ~/.uomp/sessions/*.env` |
| Reset all local data | Run `aegis-os memory stop`, then remove `~/.uomp`; use `pkill -f "aegis-os memory serve"` if needed. This deletes notes, keys, and audit data |
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
aegis-os memory stop || true
pkill -f "aegis-os memory serve" || true
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
