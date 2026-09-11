# OpenAI Codex — integration notes

Everything learned probing OpenAI's **Codex CLI** on 2026-09-11, so the next
look is a read, not another evening. Built and shipped the same day —
`Sources/GroundControl/Monitoring/CodexWatcher.swift`.

---

## Verdict

Codex gives Ground Control **working / done**, real cwd, real thread names —
but **never red**. Its one real "needs you" moment, a command needing
escalated permission, writes nothing to any file while it waits: confirmed
live, watching a real approval prompt sit on screen while the transcript's
size and mtime stayed frozen the entire time. That signal only exists live,
over Codex's own app-server socket — a materially different integration than
this one, not attempted here.

Shape shipped: `CodexWatcher` reads Codex's own local files directly, no
hook, no config written into Codex at all — same posture as `GrokBotWatcher`.
Unlike Grok Bot, Codex threads are **not** grouped under one parent; each is
its own independent CLI session, the same as Claude Code or Grok CLI's own
rows.

---

## What Codex CLI is

| | |
|---|---|
| Install | `brew install --cask codex` — official cask, "OpenAI's coding agent that runs in your terminal" |
| Version tested | 0.154.0 |
| Auth | `codex login` — ChatGPT account OAuth, or an API key |
| Config | `~/.codex/config.toml` — `model`, `model_reasoning_effort`, per-project `[projects."/path"] trust_level` |
| Local state | mostly **SQLite** (`state_*.sqlite`, `thread_history_*.sqlite`, `queue_*.sqlite`, `goals_*.sqlite`, `memories_*.sqlite`, `logs_*.sqlite`) — a real structural difference from every other CLI examined here, all of which use plain JSON/JSONL |
| Also has | a local **app-server daemon** (`codex app-server`) — a fully typed JSON-RPC protocol, `codex app-server generate-json-schema` dumps it to disk without even logging in |

---

## Hooks — real, stable, syntax still unconfirmed

`codex features list` shows `hooks` as **`stable`**, on by default — not the
`experimental, needs a flag` state an earlier pass assumed from Codex's public
docs (that note was wrong; fixed in `docs/LIMITATIONS.md`). Its schema
(`codex app-server generate-json-schema`) gives the **real, confirmed** event
vocabulary without any live probing at all:

```
"enum": ["preToolUse", "permissionRequest", "postToolUse", "preCompact",
         "postCompact", "sessionStart", "sessionEnd", "userPromptSubmit",
         "subagentStart", "subagentStop", "stop", "interrupt"]
```

CamelCase — same dialect as Grok and Cursor, not Claude's snake_case. Two
events neither Claude nor Grok has: `permissionRequest`, `interrupt`.

**What is still genuinely unknown:** the TOML syntax to actually *register* a
hook command. Checked OpenAI's own `openai/codex` repo directly (`docs/`
folder, `config.md`) — the only mention is one paragraph about admin-managed
`requirements.toml` policy, not the schema a normal user would write. Not
guessed at and not built on — this project's own rule, broken twice already
on Grok, is to measure a real payload before writing an adapter, and there is
no real payload to measure yet.

---

## The local files

Two plain JSONL files carry everything `CodexWatcher` needs, despite all the
SQLite:

### `~/.codex/session_index.jsonl` — the roster

One line per thread, small:

```json
{"id": "01a09262-2343-76d2-b5e2-98f8a810d132", "thread_name": "List files here",
 "updated_at": "2026-09-11T21:32:15.535563Z"}
```

`thread_name` is a real, useful label — pulled from the prompt, not a
folder-name guess.

### `~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-<timestamp>-<id>.jsonl` — the transcript

The index names no path to this file; only the id (a suffix of the filename)
links them, so `CodexWatcher` walks the `sessions/` tree once per reload
looking for a matching name. Bounded by real usage, not enforced — the thing
to revisit if a very long Codex history ever shows up in a profile.

First line is always `session_meta`, carrying `cwd`:

```json
{"type": "session_meta", "payload": {"session_id": "...", "cwd": "/Users/you/repo",
 "model_provider": "openai", "cli_version": "0.154.0", "originator": "codex-tui"}}
```

A finished turn's **last** line is `task_complete`, carrying the real final
message and timing:

```json
{"type": "event_msg", "payload": {"type": "task_complete",
 "last_agent_message": "This directory is empty—no files or subdirectories.",
 "started_at": 1789162332, "completed_at": 1789162339, "duration_ms": 7404}}
```

`CodexWatcher` reads the first line for `cwd`, scans from the end for the
last `task_complete` — present means **done** with the real message; absent
means **working**, generically. Same whole-file, scan-from-the-end technique
`SessionFileParser` already uses for GC's own files — Codex transcripts grow
large (162KB after ten minutes of testing), so this is genuinely doing real
work, not free, but it is the same trade this codebase already made
elsewhere.

---

## "Needs you" — confirmed absent from the basic chat, confirmed silent in the file

Two live tests, same session, 2026-09-11:

**1. No structured question tool at all.** Asked Codex directly, twice, in
different phrasings, to present a pickable list. Both times it replied in
plain prose with a manual `a/b/c` or `A/B` list, and when asked outright for
an arrow-key picker, said so itself: *"I can't display an arrow-key picker in
this chat."* Grok and opencode both have a real structured question tool;
this basic `codex` chat mode does not.

**2. The real approval gate is invisible to a file watcher.** Asked Codex to
`curl` an external URL. The sandbox blocked DNS, it retried with
`sandbox_permissions: "require_escalated"`, and a real approval prompt
appeared on screen — numbered options, a written justification, `y`/`p`/`esc`.
While that sat there waiting:

```
$ stat -f '%z bytes, mtime %Sm' rollout-....jsonl
162397 bytes, mtime Sep 11 14:41:39 2026
```

Frozen — checked repeatedly, unchanged the entire time the prompt was up.
Grepping every event type the whole transcript had ever written turned up no
`approval`/`permission_request`/`exec_approval` of any kind. The tool call
itself is logged (`custom_tool_call`, `status: "completed"` — meaning the
model finished *formulating* the call, not that it ran), then nothing, until
the file resumes once a decision is made.

This is a harder version of Grok Bot's "silence looks like done" problem:
Grok Bot at least eventually read as a plausible (if wrong) "done"; here
there is no event to misread at all, just an ordinary-looking quiet file. No
amount of clever field-reading fixes that — the signal is not in the file.
`CodexWatcher` therefore never claims `.needsInput` for Codex; a quiet
transcript stays `.working`, the safe direction, forever if need be, rather
than ever guessing done.

---

## What shipped

`CodexWatcher` (`Monitoring/`) — pure `sessions(fromIndexAt:sessionsRoot:now:)`
mapping, tested in isolation (9 tests: shape, cwd/name/state reading, the
frozen-file-stays-working guarantee, multiple independent threads, the
24h relevance cutoff, malformed input). Wired into `SessionAggregator` as a
third full producer beside `SessionStore` and `GrokBotWatcher` — concatenated
in, `SessionStore`'s file ⇔ row invariant untouched, same as Grok Bot.
`Preferences.showsCodex`, on by default (read-only, costs nothing when Codex
is not installed).

## What did not ship

- Any alarm at all — see above; nothing to build it on yet without the
  app-server socket.
- Hook-based anything — the registration syntax was never found, and this
  project's rule is not to guess one.
- The SQLite-backed state (`thread_history`, `queue`, `goals`, `memories`,
  `logs`) — untouched; the two plain JSONL files were enough.

## Open, for whenever it's picked back up

- **The real fix would be the app-server socket**, not a bigger file reader.
  `codex app-server daemon start` / `--remote ws://…` and a subscription to
  `TurnStartedNotification`/`TurnCompletedNotification`/whatever an approval
  request actually notifies as (the schema has `AskForApproval`,
  `GuardianApprovalReview`, `PermissionsRequestApprovalResponse` — none
  triggered live yet, so their exact shape is still unconfirmed) would be a
  genuinely different, bigger integration: a persistent connection, not a
  poll. Not scoped here.
- **Hook config syntax** — worth a `-c` experiment (`codex -c
  'hooks.stop=...'`) or watching `~/.codex/config.toml` after Codex's own UI
  ever writes a hook block, rather than guessing TOML from nothing.
