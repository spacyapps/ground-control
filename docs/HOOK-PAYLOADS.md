# Hook payloads — measured, not assumed

Captured live from **Claude Code 2.1.226** on macOS by registering a probe
script on every event and dumping raw stdin. Everything here is observed
output, not documentation reading. Re-run the probe when the CLI updates.

## How to re-capture

```bash
#!/bin/bash
# probe.sh — register on each event, then read /tmp/hookdump/*.txt
mkdir -p /tmp/hookdump
{ echo "=== $(date) ==="; cat; echo; } >> "/tmp/hookdump/${1:-unknown}.txt"
exit 0
```

Register it in `~/.claude/settings.json` the same way `install-hooks.sh` does,
trigger each event, then read the files.

---

## Common to every event

| Field | Example |
|---|---|
| `session_id` | `0ff3699a-597f-44c2-8a5f-3665332bc659` |
| `transcript_path` | `~/.claude/projects/<slug>/<session_id>.jsonl` |
| `cwd` | `/Users/waltermak/github/avaterm` |
| `permission_mode` | `auto` |
| `hook_event_name` | `PreToolUse` |

`session_id` is stable for the life of a session and unique across sessions.
**It is the row key and the filename.**

## Per event

### `UserPromptSubmit`
```json
{"prompt": "here's my short reply test", "session_title": "avaterm",
 "prompt_id": "cd938804-..."}
```
`session_title` is the **only** place the session's display name appears, so it
must be latched and reused on later events.

### `PreToolUse`
```json
{"tool_name": "Bash", "tool_use_id": "toolu_01KJ8...",
 "tool_input": {"command": "...", "description": "Trigger PreToolUse and check for dumps"}}
```
No message text. `tool_input.description` (Bash) or `file_path` (Read/Write)
gives a far better row line than the bare tool name.

### `Notification`
```json
{"message": "Claude is waiting for your input", "notification_type": "idle_prompt"}
```
Has real message text. `notification_type` distinguishes *why* Claude wants
you. **Only `idle_prompt` has been observed** — captured under
`permission_mode: auto`, where permission requests do not fire. The
permission-request variant is unconfirmed.

### `Stop`
```json
{"last_assistant_message": "Got it. Real payload...", "stop_hook_active": false,
 "background_tasks": [], "session_crons": []}
```
`last_assistant_message` is the **full** text of Claude's turn, markdown and
all. Condense to one line for a row.

### `SubagentStop`
```json
{"agent_id": "aa80dfa51feeff3bc", "agent_type": "",
 "agent_transcript_path": "~/.claude/projects/<slug>/<session_id>/subagents/agent-<id>.jsonl",
 "last_assistant_message": "..."}
```
`agent_id` is the stable per-subagent identifier that SPEC §4 Option B needs.

**Caveat that matters:** Claude Code fires `SubagentStop` for its own internal
agents too, not only ones you spawned. Both captures had `agent_type: ""`, and
one carried text that was never part of the visible conversation. Rendering
every `SubagentStop` as a child row produces phantom rows. Filtering rule is
unresolved — see SPEC §10.

---

## Two findings that changed the design

**1. `tty` is not in any payload, and `tty` fails inside a hook.**
Hooks run with stdin bound to the payload pipe, so `tty` returns `not a tty`
(exit 1). The scaffold's original `cc-notify` fell through to `KEY="unknown"`,
which would have collapsed every session into one file.

The tty is recoverable by walking up the process tree — the `claude` process
holds it:

```
pid=64499 tty=??       comm=/bin/bash     <- the hook
pid=61828 tty=ttys008  comm=claude        <- here
pid=61311 tty=ttys008  comm=-zsh
pid=61310 tty=ttys008  comm=login
```

Session identity now comes from `session_id`; tty is only the jump-to-tab
target. If the walk fails you lose the jump on that row, not the row.

**2. `session_title` is often not the folder name — and is usually better.**
Measured across five live sessions:

```
SAME  name='mediaSeedTree'   basename(cwd)='mediaSeedTree'
SAME  name='ironman'         basename(cwd)='ironman'
SAME  name='avaterm'         basename(cwd)='avaterm'
DIFF  name='spacyapps'       basename(cwd)='fluffy-carnival'
DIFF  name='secretstuff'     basename(cwd)='iOS8_miVault'
```

Prefer `session_title`, fall back to `basename(cwd)`.

---

## Undocumented side channel (do not build on)

`~/.claude/sessions/<pid>.json` holds live per-session state:

```json
{"pid": 61828, "sessionId": "0ff3699a-...", "cwd": "...", "name": "avaterm",
 "status": "busy", "version": "2.1.226", "updatedAt": 1786345055344}
```

`status` updates in real time and `name` is the same title the hook reports.
Useful as a cross-check or a recovery path for sessions that started before the
hooks were installed — but it is internal CLI state with no stability promise.
Hooks remain the supported interface.

---

## Grok (`grok` CLI, 2026-08-11)

**Grok reads `~/.claude/settings.json` on purpose** — documented Claude Code
compatibility, alongside `~/.cursor/hooks.json`. So installing Ground Control's
hooks wires up both CLIs at once, and `/hooks` inside Grok lists them under
`Custom: ~/.claude`.

The events are the same; only the spelling differs.

| Claude Code | Grok |
|---|---|
| `hook_event_name: "Stop"` | `hookEventName: "stop"` |
| `session_id` | `sessionId` |
| `last_assistant_message` | `lastAssistantMessage` |
| `transcript_path` | `transcriptPath` |
| `permission_mode` | `permissionMode` |
| `cwd`, `prompt` | same |
| *(none — we use the clock)* | `timestamp` (ISO 8601) |
| `session_title` | *(absent — falls back to the folder)* |

Grok also sends `workspaceRoot`, and wraps prompts in `<user_query>` tags,
which `cc-notify` strips.

That is why `cc-notify` reads both dialects rather than shipping one script per
CLI: `get(payload, "session_id", "sessionId")`. A CLI following either
convention works with no changes at all.

### Two events Claude Code does not have

```json
{"hookEventName":"session_end","sessionId":"019fee7c-…","reason":"shutdown",
 "cwd":"…","timestamp":"2026-08-11T01:42:26.433155+00:00"}
```

- **`SessionEnd`** — a session that says goodbye should not wait out the 24h
  purge. `cc-notify` deletes the session file and its `agents/` children, and
  the file ⇔ row invariant makes the row disappear.
- **`SubagentStart`** — carries an `agent_id` *before* the work happens, so
  Grok subagents can appear as children while running. Claude Code only
  announces the stop, which is why SPEC §10 lists live tracking as unresolved
  there.

Grok additionally offers `PostToolUse`, `PostToolUseFailure`, `PermissionDenied`,
`StopFailure`, `PreCompact` and `PostCompact`. `PermissionDenied` is the most
interesting unused one: it would be a genuine blocking alarm, which the Claude
side still lacks.
