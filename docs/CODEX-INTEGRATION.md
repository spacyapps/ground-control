# OpenAI Codex — integration notes

Everything learned probing OpenAI's **Codex CLI** on 2026-09-11, so the next
look is a read, not another evening. Built and shipped the same day —
`Sources/GroundControl/Monitoring/CodexWatcher.swift`.

---

## Verdict

**What shipped tonight** (`CodexWatcher`) gives Ground Control **working /
done**, real cwd, real thread names, but never red — a file-reading producer,
no hook, no config written into Codex at all, same posture as
`GrokBotWatcher`. Unlike Grok Bot, Codex threads are **not** grouped under one
parent; each is its own independent CLI session, the same as Claude Code or
Grok CLI's own rows.

**What was believed impossible turned out not to be.** Codex's real "needs
you" moment — a command needing escalated permission — genuinely writes
nothing to any file while it waits (confirmed live, a real approval prompt
frozen on screen the whole time its transcript's size and mtime sat
unchanged). That part still holds. But **hooks are real and do fire** —
confirmed live the same evening, after the file-based investigation above was
already written up as the final word. The alarm is reachable after all, just
not through the file `CodexWatcher` reads. See "Hooks, resolved" below.

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

Codex's own multi-agent tool ("create N sub agents...") is **not** the same
shape as Grok's `spawn_subagent`, confirmed live 2026-09-11: it never creates
a separate top-level thread at all. It runs as `SubAgentActivity`/
`CollabAgentToolCall` items — `kind: started/interacted/completed`, a
`"wait"` tool call while the parent blocks — logged **inline in the parent's
own rollout file**, with no `session_index.jsonl` entry or rollout of their
own. So `CodexWatcher` needs no special handling for this at all: the parent
row correctly reads `working` for the whole exchange and `done` with the real
summary once it ends, because from the file's perspective it always was one
continuous turn. A genuinely different mechanism from Grok's, worth not
confusing the two by name alone.

---

## Hooks, resolved

`codex features list` shows `hooks` as **`stable`**, on by default — not the
`experimental, needs a flag` state an earlier pass assumed from Codex's public
docs (that note was wrong; fixed in `docs/LIMITATIONS.md`). Its app-server
schema (`codex app-server generate-json-schema`, no login needed) gives the
**real, confirmed** event vocabulary:

```
"enum": ["preToolUse", "permissionRequest", "postToolUse", "preCompact",
         "postCompact", "sessionStart", "sessionEnd", "userPromptSubmit",
         "subagentStart", "subagentStop", "stop", "interrupt"]
```

That's the wire casing (camelCase — same dialect as Grok and Cursor, not
Claude's snake_case) and two events neither Claude nor Grok has:
`permissionRequest`, `interrupt`.

**The TOML registration syntax — not in OpenAI's public docs, found in the
open-source Rust instead.** `codex-rs/config/src/hook_config.rs` and its test
suite (`hooks_tests.rs`) give the real, `serde`/`toml`-verified shape — not
guessed, read straight from the struct definitions and a passing unit test:

```toml
[[hooks.Stop]]

[[hooks.Stop.hooks]]
type = "command"
command = "echo fired >> /tmp/marker"
```

Two things the flat-string guess below got wrong: **event names in TOML are
PascalCase** (`Stop`, `SessionStart`, `PermissionRequest` — matching Claude's
own convention; the codebase even has a Claude/Cursor hooks *migration* tool),
not the wire protocol's camelCase. And a handler is a structured array of
`MatcherGroup`s (`matcher: Option<String>` + `hooks: Vec<HookHandlerConfig>`),
tagged by `type` (`command`/`mcp_tool`/`prompt`/`agent`) — never a bare
string. `HooksToml`'s events are `#[serde(flatten)]`, so they sit directly
under `[hooks.<EventName>]` in `config.toml`, confirmed against
`config_toml.rs`'s own field: `pub hooks: Option<HooksToml>`.

**Tested with the exact verified shape — still didn't fire non-interactively.**
The reason is real, not another dead end: the schema also has
`HookStateToml { enabled, trusted_hash }`, and the source has an actual
`startup_hooks_review.rs` — a hook needs a one-time interactive **trust**
step before Codex will run it, the same idea as a workspace-trust prompt.
`codex exec` (non-interactive) never shows it, so a hook configured that way
stays permanently untrusted there — matching `--dangerously-bypass-hook-trust`
existing specifically for automation.

**Confirmed live, same evening.** Ran interactive `codex` (not `exec`) with
the `[[hooks.Stop]]` block above in place — a real trust prompt appeared on
startup ("trust the hooks"), was accepted, and the hook fired: the marker
file appeared, and `config.toml` grew a real trust record —

```toml
[hooks.state."/Users/waltermak/.codex/config.toml:stop:0:0"]
trusted_hash = "sha256:b3849a6bc93ee3ce358bfe954e5367ac14470b8931b390c653059b46444f6b6f"
```

So: **hooks are real, the syntax is known, and the alarm is reachable** —
`permissionRequest` should cover the exact "needs you" moment the file-based
approach can't see. What's left is building it: a `cc-notify` dialect for
Codex's real payload shape (never captured — the test above proved `Stop`
fires, not what its payload looks like), and `install-hooks.sh` writing the
`[[hooks.X]]` blocks plus walking the one-time interactive trust step during
setup. Not attempted tonight; a real next session's work, not a code change
squeezed in at the end of this one.

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

`CodexWatcher` reads the first line for `cwd`; state comes from checking
whether the transcript's **true last line** — not any `task_complete` found
scanning backward — is itself a `task_complete`. Present there means
**done** with the real message; anything else means **working**,
generically. Same whole-file technique `SessionFileParser` already uses for
GC's own files — Codex transcripts grow large (162KB after ten minutes of
testing), so this is genuinely doing real work, not free, but it is the same
trade this codebase already made elsewhere.

**Checking only the last line matters, and got it wrong the first time.**
The shipped version scanned backward for the first `task_complete` it found
and stopped — correct for a thread that has only ever had one turn, wrong the
moment a second one starts. Caught live: asked a status question (a real
`task_complete` landed, a real answer), then immediately asked for two
sub-agents — the row kept reporting `done` with the *status question's*
now-stale answer the entire time the terminal plainly read `Working (19s)`,
because that old `task_complete` was still sitting further back in the file
and the backward scan found it first. Fixed by checking only the file's true
final line: any of the new turn's own lines, however many, of whatever type,
immediately stop the old `task_complete` from being read as current.

**`lastActivity` comes from the transcript's own last line, not the index's
`updated_at` — found live the same evening, after shipping.** Ran the
multi-agent tool twice in the same thread; `session_index.jsonl`'s
`updated_at` sat frozen through both entire turns, 25+ minutes and two
`task_complete`s later, while the transcript kept growing correctly the
whole time. The index field just does not reliably track ongoing activity —
trusting it would have aged a genuinely-active row past
`ElapsedFormatter.staleAfter` (30 minutes) into looking idle. Fixed: every
rollout line carries its own top-level `timestamp`, unrelated to `type`, and
that — the transcript's own last line — is what `lastActivity` reads now.

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

- The hook-based alarm — the mechanism is now confirmed real (above), but
  building it (a `cc-notify` dialect, `install-hooks.sh` writing the TOML and
  walking the trust step) is real work, not attempted tonight.
- A flat-string `[hooks]` shape — ruled out live, 2026-09-11: `stop = "echo
  fired >> marker"` is accepted without error by `codex doctor` or a real
  `codex exec` turn, and is silently ignored, never fires. Not a parse
  error — `doctor` and `exec` alike say nothing is wrong with it. The
  correct shape (above) was found in the Rust source once this one failed.
- The app-server socket — a real, viable *alternative* path (below), but
  hooks turned out to be reachable first, so this wasn't needed tonight.
- The SQLite-backed state (`thread_history`, `queue`, `goals`, `memories`,
  `logs`) — untouched; the plain JSONL files were enough.

## Open, for whenever it's picked back up

- **Build the real hook-based alarm.** The mechanism is confirmed (above);
  what's missing is Codex's actual hook *payload* shape — the live test
  proved `Stop` fires, not what its JSON looks like on stdin. Register
  `permissionRequest` + `stop` + `sessionStart`/`sessionEnd`, capture a real
  payload the way every other CLI here was measured (`docs/HOOK-PAYLOADS.md`
  method), then extend `cc-notify` and `install-hooks.sh` to write the
  `[[hooks.X]]` TOML and handle the one-time interactive trust step (which
  a scripted installer cannot click through itself — worth checking whether
  `--dangerously-bypass-hook-trust` or pre-seeding a `trusted_hash` in
  `[hooks.state]` is the sanctioned way to automate that for an installer,
  rather than always requiring one manual interactive run first).
- **The app-server socket** remains the other real option — `codex
  app-server daemon start` / `--remote ws://…`, subscribing to
  `TurnStartedNotification`/`TurnCompletedNotification`/whatever an approval
  request actually notifies as (the schema has `AskForApproval`,
  `GuardianApprovalReview`, `PermissionsRequestApprovalResponse` — none
  triggered live yet). A persistent connection instead of a poll or a hook —
  worth it only if the hook path turns out to have a real gap the socket
  doesn't.
- **Show Codex's own "create N sub agents" tool as grouped children, the way
  Claude's real subagents already show under their parent.** Not built.
  Claude's mechanism relies on a real, structural signal this doesn't have —
  each Claude subagent fires its own hook with a real `agent_id`, and
  `cc-notify` writes it to its own file, `agents/<parent>__<agent_id>.jsonl`,
  which `AgentGrouper` reads. **Codex's collab tool creates no such file at
  all.** Confirmed live 2026-09-11: it never creates a separate thread, a
  `session_index.jsonl` entry, or any file of its own — the whole thing is
  logged as more lines *inside the parent's own transcript*:
  `SubAgentActivity` items (`kind: started/interacted/completed`, an
  `agent_thread_id`, an `agent_path` like `/root/dialogue_one` — a sandboxed
  container path, not a macOS one) and `CollabAgentToolCall` items
  (`tool: "wait"`, blocking the parent turn while they run). Those
  `agent_thread_id`s are ephemeral; nothing else on disk ever references
  them again. So this needs a genuinely different mechanism than
  `AgentGrouper`'s file-per-child pattern: `CodexWatcher` would have to
  actively parse `SubAgentActivity`/`CollabAgentToolCall` lines out of the
  parent's own transcript and synthesize `AgentRow` children from them
  directly — real, scoped work (the exact JSON shape above is already
  measured), just a different code path than everything else here uses.
- **Give a Codex row somewhere to jump to, instead of always Finder.**
  `CodexWatcher` never sets `tty`/`hostApp`/`hostID` — it has no way to,
  since it only reads static files and (unlike a hook, which runs *inside*
  the CLI's own process and can walk straight up from itself) never touches
  a live process at all. With both nil, `TerminalFocuser.destination()` has
  exactly three paths (`docs/ARCHITECTURE.md`) and falls straight to the
  last one: revealing `cwd` in Finder. Confirmed this was never a
  regression — checked the full git history of `CodexWatcher.swift` (three
  commits, all from the same evening) and none of them ever set those
  fields; the destination logic has no fourth, cwd-only path that could
  land on a terminal without one. A real fix would mean `CodexWatcher`
  actively searching the running process list for a live `codex` matching
  the thread's `cwd`, then walking its process tree for the controlling
  tty — the exact technique `cc-notify` already uses, just run from inside
  the app instead of from a hook. That would be the first time GC's own
  Swift code searches for a process on its own initiative — a genuine,
  deliberate exception to "the app reads; it does not probe"
  (`docs/ARCHITECTURE.md`), not a small tweak, and worth deciding on
  explicitly rather than building quietly.
