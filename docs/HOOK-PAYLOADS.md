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

## opencode — measured 2026-08-19 against 1.17.8

opencode has **no hook commands**. Nothing in its configuration runs a script on
an event the way `~/.claude/settings.json` and `~/.cursor/hooks.json` do. What it
has is plugins: TypeScript loaded into the agent, handed a shell. So the
integration is `Scripts/opencode-plugin.ts`, which does the same job a hook
registration does elsewhere.

Captured by loading a probe plugin that logged every event, with
`XDG_CONFIG_HOME` pointed at a scratch directory so nothing of the user's was
touched. A single turn emits well over a hundred events; all but four are noise
(`catalog.updated` and `plugin.added` dozens of times at startup).

| opencode | ours | carries |
|---|---|---|
| `session.created` | `sessionstart` | `sessionID`, `info.directory`, `info.title` |
| `session.idle` | `stop` | `sessionID` |
| `permission.asked` | `notification` | `sessionID`, `permission`, `metadata.command`, `metadata.description` |
| `permission.replied` | `posttooluse` | `sessionID`, `reply` (`accept` / `reject`) |
| `session.status` (`status.type === "busy"` only) | `posttooluse` | `sessionID`, `status: {type}` |

**`session.created`/`session.idle` do not bracket the work — corrected
2026-08-26.** The original note here said they did and that `session.status`
was therefore unneeded; live testing showed a session sits on whatever the
last event said for the entire reply, with nothing marking the busy middle.
`session.status` is now forwarded, filtered to the busy half only (the idle
half is a between-tool-calls blip, not real completion — `session.idle` still
owns that).

**The status flag is nested one level deeper than it looks.** The payload is
`properties: { sessionID, status: { type: "idle" | "retry" | "busy" } }` —
per `@opencode-ai/sdk`'s own `EventSessionStatus` type — not `properties.type`
directly. The first version of this integration checked `properties.type`,
which is always `undefined`, so the busy filter always failed and no
`session.status` event ever reached `cc-notify`. Confirmed live 2026-08-26.

Also corrected: `permission.replied` does not mean the turn ended — it means
opencode is about to resume, same as a tool call finishing. It used to alias
to `stop` (done); it now aliases to `posttooluse` (working), same as
`session.status` busy. Only `session.idle` means real completion.

### The one that matters

`permission.asked` is the event **Cursor does not have** — it fires while the
agent waits for a human, so an opencode row can turn red where a Composer row
cannot. It arrives with the command in it:

```json
{ "type": "permission.asked",
  "properties": {
    "sessionID": "ses_fe79bbc66ffeBcuSfuQtubmt1E",
    "permission": "bash",
    "patterns": ["echo hello"],
    "metadata": { "command": "echo hello", "description": "Echo hello to terminal" },
    "always": ["echo *"] } }
```

So the row says *"Echo hello to terminal"* rather than "needs your permission".
`permission.replied` clears it.

### How the plugin works

**Why a plugin and not a hook**

| Agent | How it is told to report | Configured in |
|---|---|---|
| Claude Code, Grok | a shell command per event | `~/.claude/settings.json` |
| Cursor | a shell command per event | `~/.cursor/hooks.json` |
| **opencode** | **no shell commands exist** | **a TypeScript plugin** |

**What the installer puts where**

| What | Where | Why |
|---|---|---|
| `opencode-plugin.ts` → `groundcontrol.ts` | `~/.config/opencode/plugin/` | the plugin itself |
| one entry in the `"plugin"` array | `~/.config/opencode/opencode.json` | tells opencode to load it |
| `cc-notify` | `~/.groundcontrol/bin/` | the same emitter every agent uses |

**What it listens for** — eight events; everything else is ignored, and a turn
emits well over a hundred.

| Event | The row | What it says |
|---|---|---|
| `session.created` | appears, idle | the session title |
| `session.idle` | done | — |
| `permission.asked` | **red** | the command, e.g. "List files with details…" |
| `question.asked` | **red** | the question |
| `permission.replied` · `question.replied` · `question.rejected` | working | — |
| `session.status`, busy only | working | — |

**The chain, end to end**

1. opencode fires an event, in its own process
2. the plugin ignores it unless it is one of the seven
3. it builds one line of JSON — source, event, session id, folder, message, needs_action
4. it pipes that line to `cc-notify`
5. `cc-notify` appends to `${TMPDIR}/groundcontrol/<session-id>.jsonl`
6. Ground Control's folder watcher notices the file changed
7. the row updates — **file exists ⇔ row exists**, exactly as for every other agent

**Two details that are not obvious**

- **It remembers each session's folder.** Only `session.created` carries the
  directory; later events are an id and nothing else. Without the memory, rows
  arrive named `/`.
- **It can never throw.** The send is wrapped and `.nothrow()`, because a
  monitor that breaks the agent it watches is worse than no monitor. A failure
  costs one row.

### Verified end to end

A real turn through the real plugin, on 2026-08-19, produced exactly two rows:

```
session.created    state=idle    Session started
session.idle       state=done    Done
```

with `tty`, `host_app` and `host_id` resolved from the process tree as for any
other agent — so clicking the row jumps to the terminal running opencode.

### Two things that cost time

**A plugin's `$` has no writable stdin.** `BunShell`'s `stdin` is a readonly
stream, so `$\`cmd\`.stdin(json)` hangs rather than failing. Pipe instead:
``$\`echo ${JSON.stringify(payload)} | ${EMITTER}\```, where interpolation
escapes the JSON into a single argument.

**Headless `opencode run` blocks on a permission prompt** rather than declining,
so a probe that triggers one never exits. Run it in the background and read the
log rather than waiting on the process.

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
DIFF  name='notes'           basename(cwd)='ios-vault'
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
`StopFailure`, `PreCompact` and `PostCompact`, none of them wired up.

### `Notification` — and an undocumented type (2026-08-19)

Grok's docs list `idle_prompt`, `permission_prompt` and `task_complete`. A live
`normal`-mode session sent a fourth:

```json
{"hookEventName":"notification","notificationType":"elicitation_dialog",
 "message":"Approve input (test) — enter 1, 2, or 3.",
 "cwd":"/Users/waltermak/Documents/Projects/GroundControlThemes"}
```

`needs_action=true`, `state=needsInput`, and the row carried the question rather
than a generic phrase. Nothing had to change to receive it: `interpret()` alarms
on every notification type **except** `idle_prompt`, named explicitly. Keep that
polarity. A whitelist of known types would have dropped this one in silence,
which is the failure mode this whole file exists to prevent.

Note that `notificationType` is the camelCase spelling; `get()` already reads
both.

A question actually fires **two** events, roughly a second apart:

```
pre_tool_use   working      "How should the frame sit on the panel? Overlay is …"
notification   needsInput   "How should the frame sit on the panel? Overlay is …"
```

**Answering fires none.** That is the asymmetry worth remembering: there is no
"question answered" event anywhere in the vocabulary, so the alarm outlived the
answer until `PostToolUse` was registered for the question tools. See
LIMITATIONS.md; it cost 147 seconds of false red before anyone noticed.

**No event covers the other case.** Grok also asks in prose and ends the turn,
which arrives as an ordinary `stop` — same shape as a finished task, with
nothing to distinguish them.

## Fields the script adds itself

Not every field comes from a payload. These are resolved by `cc-notify`, because
the process tree is visible there and nowhere else:

| Field | How | Absent when |
|---|---|---|
| `tty` | walks up from the hook to the first controlling terminal | no terminal in the ancestry |
| `host_app` | walks up to the first ancestor running from `<app>.app/Contents/MacOS/`, and takes the **outermost** `.app` | tmux, ssh, launchd — nothing in a bundle |
| `host_id` | `__CFBundleIdentifier`, set by LaunchServices and inherited by every child | started outside LaunchServices |

Two measured traps in `host_app`, both of which produce a confidently wrong
answer rather than nothing:

- **Nested bundles.** Electron helpers are app bundles inside the app. Taking
  the last `.app` yields `com.github.Electron.helper`, which every Electron app
  shares — so a click could raise Slack instead of VS Code.
- **Tools inside bundles.** `/usr/bin/python3` with the developer tools resolves
  to `/Applications/Xcode.app/.../Python.app/Contents/MacOS/Python` — the
  emitter's own interpreter. Hence the walk starts at the *parent* process, and
  requires `Contents/MacOS/`.
