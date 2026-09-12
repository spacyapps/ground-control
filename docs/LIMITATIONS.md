# Known Limitations

What we know is true, what we only *believe* is true, and how to find out. Kept
separate from SPEC.md so the spec can describe the design while this stays
honest about the gaps.

Every claim here is dated. When something is verified, move it up and say how.

---

## opencode — supported since 2026-08-19

Measured against 1.17.8, end to end, on a real session. opencode has **no hook
commands**: nothing in its configuration runs a script on an event. It has
plugins, so the integration is `Scripts/opencode-plugin.ts`, installed into
`~/.config/opencode/plugin/` with one line merged into its config.

**Off by default, and a switch of its own** in the Hooks menu — it writes a file
into somebody's opencode config, which is a bigger imposition than a hook
registration and should be asked for rather than assumed.

**Its rows turn red**, which makes it the second agent after Claude Code that can
raise the alarm at all. `permission.asked` fires while the agent waits, and
carries what it wants to do:

```
permission.asked    "List files with details in current directory"
permission.replied  "Done"
```

`question.asked` is forwarded too — "which database?" rather than "may I run
this". Measured live 2026-09-11, opencode 1.18.27 against a local model
(Qwen3.5, via `mlx_lm.server`): the row correctly went red and needy, but the
message read the generic "Needs your input" instead of the real question —
the field this looked for, `properties.question`, does not exist. The actual
text is one level deeper: `properties.questions[0].question` (an array — a
turn can ask more than one at once), with `.header` as a shorter fallback.
Fixed the same day; both fields are now tried.

**The other half of "two different ways", now confirmed for opencode too.**
The same live test also produced a question asked in plain prose ("17, 42,
89 — which one would you like to pick?") rather than through the question
tool. No event distinguishes that from a genuinely finished turn — the row
read green, "Done", while it sat waiting. This was predicted by analogy to
Grok's identical gap but never actually observed until now; nothing to fix,
since there is genuinely no event on the wire that tells the two apart.

**What is not covered.** Only the four lifecycle events are forwarded; opencode
emits well over a hundred per turn and the rest is noise. A session started
before the plugin was installed reports nothing until it restarts, as with any
agent.

**One trap for anyone changing the plugin.** A plugin's shell has no writable
stdin — `BunShell`'s is readonly, so `$\`cmd\`.stdin(json)` hangs rather than
failing. Pipe the JSON instead. And headless `opencode run` blocks on a
permission prompt rather than declining it, so a probe that triggers one never
exits.

## Grok asks two different ways, and only one of them reaches us — 2026-08-19

Grok can raise the alarm. It was under-claimed here until a live session was
watched in `normal` mode, which produced the **first `Notification` this project
has ever recorded from Grok**:

```
event=notification  notification_type=elicitation_dialog  needs_action=true
message="Approve input (test) — enter 1, 2, or 3."
cwd=/Users/you/github/my-themes
```

The row went red and carried **the question itself**, not a generic phrase. That
is better than Claude Code manages: Claude asks through an `AskUserQuestion`
*tool*, so its row reads "Working… (AskUserQuestion)" and never turns red.

`elicitation_dialog` **is not in Grok's own documentation**, which lists
`idle_prompt`, `permission_prompt` and `task_complete`. It worked on first
contact because `cc-notify` treats *every* notification type as an alarm except
the single one it excludes by name. Defaulting to red and naming the exception
is why an undocumented type cost nothing. A whitelist would have dropped it
silently, and nobody would have known.

**The half that does not work, and cannot be fixed here.** Grok also asks
questions in plain prose and ends the turn. Two minutes before the probe above,
in the same session:

```
event=stop  state=done  needs_action=false
message="Avatars look settled. Next is the manifest."
```

Green, "done", while it sat waiting to be answered. `Stop` fires identically
whether a turn ended in a finished task or a question, and no other event
distinguishes them — so which behaviour you get depends on whether the model
reaches for the elicitation tool or just types. Nothing in the emitter can
recover the difference.

| Grok asks by | Row shows | Alarm |
|---|---|---|
| elicitation dialog (`normal` mode) | the question text | **yes, red** |
| prose at the end of a turn | "done" | no — indistinguishable from finishing |

**This one is not silenced by `auto`, and that makes Grok unusual.** An earlier
draft of this section claimed it was, reasoning from a log with no notifications
in it — the precise mistake §1 warns about, made while writing up §1.

The mechanism is different from a permission prompt. `ask_user_question` is a
**tool** (`[toolset.ask_user_question]`, with its own timeout setting), and
Grok's question card is a separate UI from its permission dialog. Permission
modes govern whether *tool calls* need approving; they do not stop the agent
choosing to ask you something. So `auto` reduces permission prompts and leaves
elicitation alone.

That makes Grok the **only** agent here that can turn a row red on a machine
running auto-approve — Claude's `permission_prompt` and opencode's
`permission.asked` are both gates, and both go quiet in `auto`. Worth knowing on
this machine specifically, where everything is set to auto and the alarm has
otherwise never been seen in ordinary use.

The empty log before 2026-08-19 is therefore evidence of nothing at all: Grok
simply had not chosen to ask.

**A question fires two events, and neither one ends.** `PreToolUse` carries the
question text, then `Notification` raises the alarm about a second later. An
earlier draft here said `ask_user_question` never reached us through
`PreToolUse` — that was read off an aggregate taken before any question had been
asked, and it is wrong.

What genuinely has no event is **the answer**. Replying emits nothing: no
`Stop`, no second notification, no prompt. The row therefore stayed red from the
question until the agent's next tool call — measured at **147 seconds** on
2026-08-20, the whole of it spent thinking, with the panel demanding attention
that had already been given.

Fixed by registering `PostToolUse` with a matcher for the question tools alone
(`ask_user_question|AskUserQuestion`). A completed tool always means work
resumed, so the mapping is unconditional; the matcher is what keeps it from
firing after every tool and repeating `PreToolUse` at twice the writes. It is
the only registration in the installer that carries a matcher, and a test pins
that.

## Grok's `spawn_subagent` fires no hook — grouped by reading its own files instead, 2026-09-10

`SubagentStart`/`SubagentStop` were believed to cover Grok's subagents — see
the correction above. What a live test actually found, spawning real
subagents against `~/github/lunararray`:

Each subagent is its own **fully independent top-level Grok session** — own
`session_id`, its own `Repo: /path` opener, its own `PreToolUse` stream, its
own row in the panel, and it self-deletes on completion the same as any
session's `SessionEnd`. Nothing links it to its parent in any hook payload
`cc-notify` ever sees.

The real link exists anyway, one layer outside any hook: Grok writes
`<parent_session_dir>/subagents/<child_session_id>/meta.json` for itself —
~1KB, not the parent's 500KB+ transcript, carrying `parent_session_id`,
`child_session_id`, the task's `description`, `status` (`"running"` at spawn,
confirmed live — not only once finished — then `"completed"`), and timing.
It survives after the child's own hook-driven row self-deletes, so a
finished subagent is still discoverable here even once its flat row is gone.

`GrokSubagentReader` reads it and folds the child under its parent — the same
"N subagents" treatment Claude's real subagents get via `AgentGrouper`, just
sourced from a different kind of file. While the child's own row still
exists, *that* row — not `meta.json` — remains the source of live state and
`needsAction`, since `meta.json` carries no alarm signal at all and Grok is
the one CLI here that alarms independent of `permission_mode: auto`. Full
design: `docs/GROK-SUBAGENT-GROUPING.md`.

| | Live while running | Survives the child's own row vanishing | Alarm-safe |
|---|---|---|---|
| **Grok subagents** | **yes** — child's own row drives state until it self-deletes | **yes** — `meta.json` is the fallback, time-boxed 30 min like Claude's own finished children | **yes** — never trusts `meta.json` alone while a real row exists |

## Claude for Desktop — reports fully, measured 2026-08-22

The desktop app **bundles its own Claude Code** — a 317MB binary at
`~/Library/Application Support/Claude/claude-code/<version>/claude.app` — and
that agent reads `~/.claude/settings.json` and runs our hooks like any other.
One session produced the full sequence:

```
SessionStart · UserPromptSubmit · PreToolUse · Notification · PreToolUse · Stop
```

with `Notification` carrying "Claude needs your permission to use Bash",
`needs_action=true`, and the row going red.

**Its Code tab only.** The desktop app has two surfaces: **Home**, which is
ordinary claude.ai chat rendered in Electron, and **Code**, which is Claude Code
with a GUI instead of a terminal. Only Code spawns a process, so only Code
reports — a Home conversation produces no row and never will. There is nothing
to want there either: a chat window is turn-based and in front of you, so the
state this app exists to surface, an agent blocked in a window you have buried,
cannot occur in it.

**This is the opposite of Xcode's embedded agent**, below, which is also real
Claude Code and reports nothing. The difference is the entrypoint: Xcode drives
it as `sdk-cli`, in-process; the desktop app spawns the ordinary CLI as a child,
so the hook machinery is intact.

**Notable: that notification carried no `notification_type` at all** — an empty
string, not `permission_prompt`. It alarmed anyway, because `interpret()` treats
every type except `idle_prompt` as an alarm. That is the third unanticipated
notification shape this polarity has caught (see also Grok's undocumented
`elicitation_dialog`), and the first with no type to whitelist even if we wanted
to.

**Two caveats.**

- **No tty.** There is no terminal, so there is no tab to jump to; the click
  raises the application instead.
- **The click used to land in Finder**, fixed the same day. `resolve_host_app`
  returned the *first* app in the ancestry, which is that inner
  `claude.app` — a real bundle, and one nobody can switch to. It never runs in
  the foreground, so `isBundleRunning` was false and the destination fell
  through to Finder. The emitter now takes the **topmost** app in the ancestry.
  Terminal, Xcode and VS Code name the same app either way; only this host
  differed. A session that was already open keeps the old value, since the
  emitter carries the last known host forward — start a new one to see it.

## Xcode's Claude Agent — measured 2026-08-19, does not report

Xcode 26 embeds a Claude agent ("Message Claude Agent"). It **is** Claude Code —
not a lookalike — and every ingredient for reporting is present. It still
reports nothing, and nothing on this side can fix that.

What its own environment says, read from inside a live session:

```
CLAUDE_CODE_ENTRYPOINT = sdk-cli
CLAUDECODE             = 1
CLAUDE_CODE_CHILD_SESSION = 1
__CFBundleIdentifier   = com.apple.dt.Xcode
```

- It can see `~/.claude/settings.json`, and counted our 8 `cc-notify`
  registrations in it.
- It can reach `~/.groundcontrol/bin/cc-notify`, executable.
- It runs shell commands happily.

And across the ninety minutes of a real session, **nothing was written** — no
session file, no subagent file, nothing attributed to `com.apple.dt.Xcode`. Only
Terminal.app rows appeared in that window.

So: **the `sdk-cli` entrypoint does not execute hooks.** Hooks are Claude Code's
to run, and this variant does not run them. There is no switch, no plugin and no
registration that changes it, which is what makes it different from the other
two gaps:

| | Has hooks? | Reports? | Answer |
|---|---|---|---|
| Cursor's Composer | yes | not while waiting for you | none available; stated in the UI |
| opencode | no hook commands | yes, via a plugin | plugin shipped, rows turn red |
| **Xcode's Claude Agent** | **yes, and configured** | **no** | **nothing we can do** |

Expect this to hold for **any** editor embedding the Agent SDK rather than
spawning the CLI. The same generalisation the Cursor entry makes about editors'
own chats.

Claude Code running in Xcode's *terminal* is unaffected and fully supported, as
in every other editor.

## Grok Bot — supported as a group, measured 2026-08-28

xAI's "Grok Bot" desktop app (`/Applications/Grok Bot.app`, Electron, v0.30.0)
appears in the panel as one collapsible group, a row per bot, and a decision
card waiting on your answer turns that bot and the group red. What it does not
yet distinguish is working from done — that section is why.

Grok Bot is a **Cursor fork** — `cursor-machine-id`, a bundled `cursor-proclist`
native module, `api2.cursor.sh`, `anysphere.cursor-mcp`, and `~/.cursor/` as its
config root all sit in the bundle. Its agents run on an xAI **cloud desktop**,
not on this machine; a local `sand-local-exec-daemon` ("serving local exec over
the gateway") bridges back only when the agent runs a command *here*, and only
after an in-app approval plus a macOS TCC prompt.

**Hooks are not the route.** The bundle carries Cursor's entire hooks engine —
`dist/local-exec-daemon/main.cjs` has the full event vocabulary (`stop`,
`afterAgentResponse`, `beforeSubmitPrompt`, `preToolUse`, `sessionStart` …) and
an explicit Claude-Code compatibility map (`PreToolUse → preToolUse`,
`Stop → stop`). `Scripts/probe-cursor-hooks.sh` was installed into
`~/.cursor/hooks.json` (all 18 events) and Grok Bot restarted. Across four turns
— plain chat, an inline decision card, and a local `ls ~/Desktop` that passed
through both the app's approval prompt and macOS TCC — **nothing was written to
the probe log.** Grok Bot never consults a local `hooks.json`; the engine is
dormant code, driven only by cloud-pushed `HooksConfigInfo`. Local commands go
through its own `~/.grokbot/local-tool-approvals.json` grant ledger instead,
which is written *after* approval, not while waiting.

**The only local signal is an undocumented cache.** Grok Bot mirrors state to
plaintext JSON blobs under
`~/Library/Application Support/Grok Bot/sand-client-persistence/` (base32-encoded
slice names). The useful one is `…roster.last-roster` — one row per bot,
rewritten every turn:

| field | carries |
|---|---|
| `name` | the bot's display name — a clean row label, no empty-`cwd` guessing |
| `avatarColor` / `avatarShape` | the sidebar avatar |
| `updatedAt` / `lastActivityAt` | a heartbeat — advances each time the bot emits anything, including interim "on it…" notes mid-turn. Moving recently ≈ active; quiet ≈ **done *or* deferred**, and the file can't tell you which (see below) |
| `hasUnread` / `unreadCount` | focus-driven: increments on a bot message while its window is unfocused, clears to 0 on view. Not a reliable "you haven't seen this" flag |
| `lastEntry.sessionPreview.kind` | small state machine: `"widget_options"` while a decision card is pending → `"widget_answered"` the moment it is tapped → back to `"text"`/absent on the next reply. The `"widget_options"` value as the *current* roster state is the usable "needs you" signal |
| `awaitingUserResponse` | **stayed `null` through every test**, including both approval prompts — see below |
| `isGroup` / `memberIds` | channels vs solo bots |

A watcher on that one folder is what drives the group: a row per bot, and the
red alarm when `sessionPreview.kind == "widget_options"` — an unanswered
decision card. It does **not** try to tell working from done, and it does
**not** see "blocked on a permission prompt or CAPTCHA".

**"Done" is not knowable.** A long turn watched live posted two interim notes
("On it…", "This one's a longer pull, I'll come back with a cited table…"), each
a complete transcript entry — then went **completely silent for 3 min 49 sec**,
no write of any kind, before the cited table arrived under a *new* `requestId`.
The cloud agent had ended the first request and resumed later as a fresh one.
For those ~4 minutes the file was byte-identical to a finished turn. A GC row for
a Grok Bot would have read "quiet / done" the whole time it was working.

The format is an internal cache with no stability promise; the roster schema is
already at version 3, and entries carry no `isStreaming` — the cache stores
finalised messages, not token streams.

**Why `awaitingUserResponse` stays null.** The demo decision card carried
`dismissOnMoveOn: true`, and the agent's cloud turn had already *finished* when
it posted the card — the bot is idle, the card just sits in the UI, and tapping
it starts a fresh turn. `awaitingUserResponse` marks an agent that is genuinely
paused mid-turn and cannot proceed (a login wall or CAPTCHA on the cloud desktop
— xAI's docs call this "Computer View State"). Asked directly, the bot said it
does not flip that bit itself, the app does, and *"widgets look like they land in
`lastEntry` and may never set `awaitingUserResponse`"* — the model describing its
own app, so informed but not authoritative. That case was never triggered here,
so what a true hard block writes to the roster is **unconfirmed** — it may set
this field, or it may surface only through an OS notification.

The usable "card is waiting" signal is therefore `lastEntry.sessionPreview.kind
== "widget_options"` being the *current* value: it appeared when the bot asked
and flipped back to `"text"` the moment the card was answered.

The cache is the local, unauthenticated twin of Grok Bot's own
`aiserver.v1.WatchGrokBotTranscripts` gRPC method — same data, from a file
instead of a cloud stream that would need its auth and protobuf reverse-
engineered.

**What shipped:** `GrokBotWatcher` reads that folder and emits one group;
`SessionAggregator` merges it beside the hook-driven rows. A pending card raises
the alarm like any other blocked session. Full design: `docs/GROK-BOT-GROUPING.md`.

| | Turns red when it needs you | Tells working from done |
|---|---|---|
| Cursor's Composer | no — no hook while it waits | n/a |
| **Grok Bot** | **yes — the decision card** | not yet; the cloud agent can go silent mid-task |

## Verified (measured, not assumed)

| Thing | How it was proven | When |
|---|---|---|
| Claude Code hook payload fields | probe script dumping raw stdin, all 5 events | 2026-08-10 |
| tty recovery via process-tree walk | printed the walk; `claude` holds the tty | 2026-08-10 |
| Terminal.app jump-to-tab | clicked a row, landed on the right tab | 2026-08-10 |
| Grok hook payloads | probe in `~/.grok/hooks/`, 4 events captured | 2026-08-11 |
| Grok reads `~/.claude/settings.json` | `/hooks` shows `Custom: ~/.claude (9 hooks)` | 2026-08-11 |
| Grok `SessionEnd` removes a row | replayed the real payload; file deleted | 2026-08-11 |
| Grok turns a row red | live `normal`-mode session; `elicitation_dialog` carried the question text | 2026-08-19 |
| Grok prose questions read as "done" | same session: a question ended the turn as a plain `Stop` | 2026-08-19 |
| Claude for Desktop reports and alarms | live session; permission notification turned the row red | 2026-08-22 |
| Its Home tab reports nothing | a chat there produced no row; only the Code tab spawns a process | 2026-08-22 |
| Four hosts told apart in one panel | Terminal, Cursor, VS Code and Claude for Desktop on screen together, each row naming its host | 2026-08-22 |
| Cursor's two agents differ, side by side | Claude Code in its terminal went red while Composer sat "done" in the same panel | 2026-08-22 |
| Real subagents carry `agent_type` | spawned two Explore agents; both `type="Explore"` while every internal one was `""` | 2026-08-11 |
| Grok's `spawn_subagent` fires no `SubagentStart`/`SubagentStop` | two real subagents spawned, watched end to end on disk; neither event ever appeared | 2026-09-10 |
| Grok's real subagent link lives in `subagents/<id>/meta.json` | read live against 5 real subagents across 3 separate test runs, all correct | 2026-09-10 |
| Grok subagent grouping, end to end in the app | built, signed, launched; two live children plus one recovered-after-self-delete child all showed correctly nested under one parent row on screen | 2026-09-10 |
| Background images render | a real theme with a starfield frame, on screen — and it was broken three ways until it was tried | 2026-08-11 |
| Nine-slice cap insets | the frame holds its corners while the panel resizes | 2026-08-11 |
| Jumping to a host app | VS Code session with no tty at all; clicking raised the editor | 2026-08-12 |
| **The red alarm, end to end** | a blocked session turned the row red, the click landed on its tab, and the alarm cleared — watched, not derived | 2026-08-12 |
| opencode plugin API and events | probe plugin logged a real turn; 4 of >100 events matter | 2026-08-19 |
| **opencode's alarm, end to end** | row turned red carrying "List files with details in current directory", and cleared on reply | 2026-08-19 |
| **opencode + a fully local model — a new tested combo** | opencode 1.18.27, Qwen3.5-9B-OptiQ-4bit served locally via `mlx_lm.server`, no cloud API in the loop at all; both question styles produced correct GC behaviour (one needing the fix below) | 2026-09-11 |
| opencode's `question.asked` fires and carries the real question | live against the combo above; found the field was nested one level deeper than assumed, fixed | 2026-09-11 |
| opencode's prose-question gap, same as Grok's | same live test: a question asked in prose read "Done", green, while waiting on an answer | 2026-09-11 |
| Codex's `hooks` feature is stable, not experimental | `codex features list` — `stable`, `true`, contradicting the 2026-08-11 guess | 2026-09-11 |
| Codex's real event casing/names | dumped straight from `codex app-server generate-json-schema`, no login needed | 2026-09-11 |
| Codex's basic chat has no structured question tool | asked twice, differently phrased; both times it said outright it cannot render a picker | 2026-09-11 |
| Codex's approval gate writes nothing to any file while pending | a real `curl` approval prompt sat on screen; the transcript's size and mtime were frozen the entire time, and no approval-shaped event exists anywhere in its whole history | 2026-09-11 |
| Codex rows in the real app | built, tested, launched; real cwd/thread name/working-done state read correctly from live disk data | 2026-09-11 |
| A flat-string `[hooks]` TOML shape does nothing | `stop = "echo fired >> marker"` in `config.toml`, a real turn run end to end — no error from `doctor` or `exec`, marker never appeared | 2026-09-11 |
| **Codex hooks are real and do fire** | the verified `[[hooks.Stop]]` shape, run *interactively* (not `exec`): a real trust prompt appeared, was accepted, the marker file appeared, and `config.toml` grew a genuine `trusted_hash` entry | 2026-09-11 |
| `session_index.jsonl`'s `updated_at` is unreliable mid-turn | ran Codex's multi-agent tool twice in one thread; `updated_at` sat frozen 25+ minutes and two `task_complete`s while the transcript kept growing correctly — fixed by reading the transcript's own last-line timestamp instead | 2026-09-11 |
| A new turn was misread as the *previous* turn's stale `done` | asked a status question (real `task_complete`), then immediately asked for sub-agents; the row kept the status question's answer as "done" while the terminal read `Working (19s)` — the backward scan found the old `task_complete` first. Fixed: only the file's true last line may report `done` | 2026-09-11 |
| opencode respects `XDG_CONFIG_HOME` | probed in a scratch config; the user's own was never touched | 2026-08-19 |
| A plugin's shell has no writable stdin | `.stdin(json)` hung twice for five minutes; piping works | 2026-08-19 |
| Only `session.created` carries the directory | later events gave an id alone, and rows arrived named `/` | 2026-08-19 |
| Xcode's Claude Agent never reports | 90 minutes of a live session wrote nothing; `sdk-cli` entrypoint | 2026-08-19 |
| opencode uninstall is clean | plugin file, config entry and rows all gone; model and permission settings untouched | 2026-08-19 |
| **Gatekeeper stays silent on another Mac** | 0.6.0 AirDropped to a second machine — quarantine flag set, opened without a warning | 2026-08-19 |
| Install/uninstall touch only our own entries | scripts run against a sandboxed `HOME`, foreign hooks survive | 2026-08-18 |
| Uninstall clears any older install's path | a registration under `~/bin` is still recognised as ours | 2026-08-18 |
| Cap insets measured from artwork | agreed with both shipped frames independently (100, 129) | 2026-08-18 |
| iTerm2 jump-to-pane | three sessions in two panes and a tab; every row landed on its own | 2026-08-12 |
| Cursor as a host app | Claude Code in Cursor's terminal: the row appeared, went red for a permission prompt, and clicking it raised Cursor | 2026-08-14 |
| Cursor's **own** agent | probed a live Composer turn, then ran two: rows appeared, named after the workspace, attributed to `/Applications/Cursor.app` with no tty | 2026-08-14 |
| Nine-slice orientation | red-top/blue-bottom test image drawn through the real overlay view; the caps were swapping | 2026-08-14 |

---

## Unverified assumptions

### 1. The red alarm — **triggered and confirmed 2026-08-12**

`idle_prompt` notifications are deliberately skipped (SPEC §3) because they mean
"Claude finished, your turn", not "Claude is blocked". This entry used to say
that `idle_prompt` was the only `notification_type` ever seen, and that the
alarm path was therefore correct-by-construction and unproven.

It is proven now. The reason it stayed unproven for so long is worth keeping:
`~/.claude/settings.json` on this machine carries `permissions.defaultMode:
"auto"` and `skipAutoPermissionPrompt: true`, so Claude never asks and the path
never runs. The first attempt at this test failed for exactly that reason — the
session read the file without a murmur.

Running one session with `claude --permission-mode manual` and asking it for a
file outside its working directory produced:

```
event=Notification  notification_type=permission_prompt  needs_action=true
message="Claude needs your permission"
host_app=/System/Applications/Utilities/Terminal.app  tty=/dev/ttys009
```

and replaying that line through the app's own model gives `isActionable=true`,
`state=needsInput`, `needsAction=true` — the red dot.

The whole flow was then watched rather than derived: the row went red while the
session sat blocked, clicking it brought Terminal forward **on that session's
tab**, and the alarm cleared on arrival. That last part is the rule that a click
only silences an alarm if it went somewhere — acknowledgement lives in memory
and never on disk, so it could only ever be confirmed by looking.

One honesty remains. Anyone running in `auto` mode — this machine's default —
will essentially never see an alarm, so the feature is largely untested by its
own author in ordinary use. A machine with prompting left on is the better test
bed.

Grok's `PermissionDenied` remains a candidate trigger, still unmeasured — but
Grok is no longer alarm-less: see "Grok asks two different ways" above, where
`elicitation_dialog` turned a row red in `normal` mode on 2026-08-19.

### 2. Internal-agent filtering — **now verified** (2026-08-11)

`AgentGrouper` hides children whose `agent_type` is empty. Two deliberately
spawned subagents both reported `agent_type: "Explore"` and appeared as
children, while every internal agent on disk reported `""` and was hidden —
their messages being echoes of the user's own prompts ("commit", "rename it to
ground-control"), which is exactly what made them misleading on screen.

Still a heuristic rather than a guarantee: a real subagent *could* report no
type. `defaults write GroundControl showsInternalAgents -bool YES`, or the
checkbox in Settings → Advanced, brings them back.

### 3. Background images — **verified 2026-08-11, and this entry was earned**

They render correctly now. Worth recording *how* this was found, because it is
the clearest case in the project of tests proving nothing.

Nine-slice resolution, cap insets, modes and caching were all unit-tested and
green. The first real theme with a background — a starfield frame — showed
nothing at all, and three separate faults had to be fixed before a single pixel
appeared:

1. `SessionListView` painted an opaque `windowBackground` over the image.
2. Rows filled with the default compositing operation, which replaces rather
   than blends, so any alpha a theme set on `rowBackground` was silently
   painted solid.
3. A framed background was structurally impossible: rows span the full width,
   so they sat exactly where the border art lives. That needed a new concept,
   `layout.contentInset`.

None of those were reachable by a unit test. Every one of them was a
"the pixels never arrive" fault, and the only instrument that finds those is a
person looking at the screen.

*Lesson for the rest of this file:* an entry saying "tested but never seen"
should be read as **not working until proven otherwise**.

### 3a. Rendering offscreen — most of the instrument the lesson above asked for

`bitmapImageRepForCachingDisplay` + `cacheDisplay` renders a view without a
window, and reading the pixels back turns "look at it" into an assertion. It
found, in one session: every image in the theme preview drawn upside down (a
flipped view; `NSImage.draw` ignores that unless passed `respectFlipped`), rows
printed across a skin's frame because the inset was scaled by the artwork
instead of the panel, and how much of a keyed image the de-spill actually
touches — 0.46%, which settled an argument that would otherwise have been taste.

**What it does not capture: anything the layer draws.** Corner radius, masked
corners, layer background colours. A probe drawing a red square with a corner
radius came back fully transparent, and a panel rendered byte-identical with
`maskedCorners` set either way. So `layout.contentCornerRadius` is the one piece
of this work verified only on screen, by Walter, and it is marked as such in the
code.

### 3b. Jumping to a non-terminal host — **measured 2026-08-12**

`host_app` / `host_id` are verified for **Terminal.app** and for **VS Code**,
the latter on a real Claude Code session in the integrated terminal after
installing VS Code for the purpose: the row appeared, was attributed to
`Visual Studio Code.app`, and clicking it raised VS Code. All three states were
visible in the panel at once — a VS Code session, a Terminal session, and an
older session carrying no host at all, which fell back to Finder exactly as it
always did.

The chain, printed from a shell inside VS Code:

```
/bin/bash                                              ttys010
  /bin/zsh                                             ttys010
    …/Code Helper.app/Contents/MacOS/Code Helper       ??
      …/Visual Studio Code.app/Contents/MacOS/Code     ??
```

and what the emitter made of it:

```
tty       '/dev/ttys010'
host_app  '/Applications/Visual Studio Code.app'
host_id   'com.microsoft.VSCode'
```

Three things this proves rather than assumes. VS Code's integrated terminal does
hold a real controlling tty, so `resolve_tty()` was never the problem. The walk
does reach the application. And **the nested-helper trap is real, not
theoretical** — the first bundled ancestor is `Code Helper.app`, whose bundle id
is the shared `com.github.Electron.helper`, so taking the nearest `.app` would
have raised whichever Electron app macOS felt like.

`$TMPDIR` also matched the app's exactly, which is the other thing that has to
be true for a row to appear at all.

Activation is **app-level only**. With several editor windows open you get the
last-used one, not the window holding that repo — a deliberate trade against
opening `vscode://file/<cwd>`, which can spawn a new window.

**One bug this caught late, worth keeping.** The first version searched every
running terminal for the tty regardless of host, so a VS Code session with
Terminal.app open claimed a Terminal tab, failed to find it, and then raised
Terminal — the wrong app, confidently, which is worse than the Finder it
replaced. A tty belongs to whichever app opened it; the search now runs only
when the host is a terminal we can script.

**Cursor — measured 2026-08-14.** Claude Code running in Cursor's integrated
terminal: the row appeared, went red when the agent asked permission to run a
command, and clicking it brought Cursor forward.

The click is what proves the attribution, more firmly than reading the field
would have. Raising an application is only reachable through the `.application`
destination, which needs `host_id` resolved; had the walk failed, the tty would
have found no scriptable terminal and the row would have fallen through to
Finder. So the outermost-bundle rule holds on a real Cursor install, not just
against the paths inspected when it was written.

Cursor's **own** agent — **supported since 2026-08-14**, and it took a probe
first. `Scripts/probe-cursor-hooks.sh` captured a real Composer turn; the
adapter was written from that, never from the docs.

What the capture settled:

- Payloads are **snake_case**, like Claude's — the docs describe only output
  fields and show no input, so this was a coin flip beforehand.
- Three events (`sessionStart`, `preToolUse`, `stop`) already normalise to our
  spelling once case and underscores are stripped. Only `beforeSubmitPrompt`
  needed an alias, and it carries `prompt` exactly as `UserPromptSubmit` does.
- `cwd` arrives as an **empty string**, with the real path in
  `workspace_roots`. Taken at face value every Cursor row would be named
  `.cursor`, after the directory its hooks run from.
- `cursor_version` is the only field distinguishing it from Claude Code, which
  matters because session ids are unique per tool.

Two live Composer sessions then produced rows named after the workspace,
attributed to `/Applications/Cursor.app` / `com.todesktop.230313mzl4w4u92` with
**no tty** — Composer is not a shell. That is the right shape: the destination
logic sends a host-without-tty row to the application, so clicking raises
Cursor.

**Both Cursor surfaces, in one panel, 2026-08-22.** The distinction stopped
being a claim in two documents and became two rows on screen at once:

```
Cursor -> cursorem        source=claude    needsInput   (red)
Cursor -> it was a tes    source=cursor    done
```

Same host, same editor, two different agents. Claude Code running in Cursor's
integrated terminal alarms exactly like Claude Code anywhere else; Cursor's own
Composer reports its rows and never goes red. Anyone who says "Cursor works" or
"Cursor does not work" is answering a question that has two answers, which is
why the compatibility table lists them as separate products.

**No alarm for Composer — measured, then confirmed against the docs.**

With all eighteen documented agent events registered, an agent visibly blocked
on a "Waiting for approval" card fired *nothing*. The last hooks were
`preToolUse` / `postToolUse` at 12:09:27, then silence for as long as the card
sat there, and the web search it was asking about produced no event at all. So
`preToolUse` fires only for tools Cursor may already run.

Cursor's own documentation lists no waiting-or-blocked event, and the state is
an open feature request. Cursor staff replied there suggesting
`beforeShellExecution` as the closest thing and said they were "tracking this to
gauge interest" — no commitment, no timeline.

`beforeShellExecution` is not that signal on its own. It fired here for a
command that then ran **without** ever prompting (`"sandbox": true`), so it
means "about to run a command", not "waiting for you". Wiring the alarm to it
would turn every shell command red — the same mistake as treating Claude's
`idle_prompt` as an alarm, which made red mean nothing.

**One untested lead.** The captured `beforeShellExecution` carried
`"sandbox": true` and did not prompt. If `sandbox: false` reliably means Cursor
is about to ask, that is a real signal — for shell commands only. It would still
miss web search, MCP tools and file edits, which is what the observed block
actually was.

The other route is inversion: an MCP server exposing an `ask` tool, so the agent
*tells* the monitor it needs a decision rather than the monitor detecting it.
That depends on the agent choosing to call it, and changes how the agent
behaves.

Still unmeasured: Windsurf, Warp, Ghostty and WezTerm.

### 4. iTerm2 jump-to-tab — **verified 2026-08-12, first execution**

This entry said the AppleScript had never run, because iTerm2 was not installed.
It is now, and it worked on the first attempt without a line being changed: the
script has not been touched since it was written on 10 August, two days before
anything executed it.

It was tested harder than it was designed for. Three sessions were opened in
iTerm — two **split panes** and a third tab — each with its own tty:

```
trial     /dev/ttys009   host=/Applications/iTerm.app
empty     /dev/ttys013   host=/Applications/iTerm.app
itermAva  /dev/ttys010   host=/Applications/iTerm.app
```

Clicking each row landed on the correct one, panes included. That matters
because a pane is a *session* in iTerm's scripting model, so `select s` had to
pick the right one within the right tab — a stricter match than Terminal.app can
even express, since it has no panes.

Worth noting what did *not* verify itself here: the script was written by
analogy to the Terminal.app one and reviewed only by reading. It happened to be
right. The surrounding decision — which terminal's script to run at all — was
wrong twice today and needed measuring both times.

---

### 3c. Claude Code's VS Code extension — rows yes, alarms no

Driving Claude Code from the extension's own panel rather than a terminal was
measured on 2026-08-12. The row appears, its name and message update live, and
**clicking it works** — but no alarm ever rises.

Two things are true of such a session:

- **`tty` is `None`.** There is no terminal, so the walk finds no controlling
  one. `host_app` is the only thing identifying the session, which makes this
  the case where jumping by host is not an improvement but the sole reason a
  click goes anywhere. Verified against the live values: the destination
  resolves to `application(com.microsoft.VSCode)`, and the click raises the
  editor.
- **No `Notification` event arrives.** A permission prompt was on screen — the
  extension asking to read a file — while that session's file recorded only
  `PreToolUse` for the very same read, and no notification of any kind. Since
  the alarm is driven entirely by `Notification`, a row in the extension goes
  quiet rather than red when it needs you.

The honest reading is that the extension renders permission prompts in the IDE
without firing the hook the CLI fires. What must **not** be done is to infer the
alarm from `PreToolUse` going quiet: that is indistinguishable from a slow build,
and a monitor that cries wolf is worse than one that stays silent. See the
`idle_prompt` history above for how that was already learned once.

## What is not an agent, as far as this app is concerned

Ground Control is **hook-driven**. Its entire input is what an agent CLI reports
by running `~/.groundcontrol/bin/cc-notify` on its lifecycle events. An assistant that does not
invoke a user-installable hook cannot appear, however busy it is.

**VS Code's own chat (Copilot) does not appear**, and this was tested rather
than assumed: prompting it, including agent mode running shell commands in a
hidden terminal, produced no session file at all. It never calls the emitter,
so nothing is written and no row exists to draw. Claude Code running in the same
editor's integrated terminal appears normally.

Supporting it would need a VS Code extension writing the same JSON lines — the
format is deliberately dumb enough for that. The obstacle is not the writing but
the signal: the reason this app exists is *"blocked, waiting on you"*, and VS
Code's chat API exposes participants you address directly rather than
observation of Copilot's own state. A Copilot row would likely manage *busy* and
*not busy* and never the one that matters.

## Other CLIs

The app is CLI-agnostic: it reads a folder of JSON lines and knows nothing about
any vendor. Only `Scripts/cc-notify` needs to understand a CLI.

Across every agent CLI examined there are exactly **two axes of variation**:
field **casing**, and **event naming**. Nothing else about the design has had to
change.

| CLI | Hooks | Field casing | Event names | Status |
|---|---|---|---|---|
| Claude Code | ✓ | snake_case | canonical | **working** |
| Grok | ✓ — reads `~/.claude/settings.json` | camelCase | same, lowercased | **working** |
| Codex | ✓ `stable`, on by default, **confirmed firing live** | camelCase (wire); TOML config is PascalCase | same idea as Claude's, plus `permissionRequest`/`interrupt` | **rows work; hook alarm confirmed reachable, not yet built** — see below |
| Gemini | ✓ `~/.gemini/settings.json` | snake_case, same names | **its own** | needs aliases |
| Cursor | `~/.cursor/hooks.json`, schema `version: 1` | snake_case | **camelCase** (`sessionStart`, `preToolUse`, `stop`) | **working** — no alarm yet |
| opencode | plugin API (`@opencode-ai/plugin`), `event` hook | n/a — TypeScript | n/a | would need a plugin, not a script |

### Codex — installed, tested, integrated 2026-09-11; hooks confirmed real the same evening

Full record: `docs/CODEX-INTEGRATION.md`. The `2026-08-11` guesses above were
wrong on two counts, now corrected: `hooks` is `stable` and on by default, not
experimental behind a flag; wire casing is camelCase, confirmed straight from
Codex's own JSON-RPC protocol schema (`codex app-server generate-json-schema`
dumps it without even logging in).

Shipped first, reading Codex's own local session files instead
(`CodexWatcher`, same posture as `GrokBotWatcher`): real cwd, real thread
names, working/done — but never red. Confirmed live that Codex's one real
"needs you" moment (a command needing escalated permission) writes nothing to
any file while it waits — that finding still stands.

**Then, later the same evening, the hook path itself got resolved.** The TOML
registration syntax — never in OpenAI's public docs — was found in the
open-source `codex-rs` (`config/src/hook_config.rs` + its test suite): TOML
event names are PascalCase (`Stop`, `PermissionRequest`, matching Claude's
own convention), and a handler is `[[hooks.EventName]]` /
`[[hooks.EventName.hooks]]`, tagged `type = "command"` — never a bare string
(a flat-string guess was tried first and confirmed silently ignored). Tested
with the verified shape non-interactively — still nothing, for a real reason:
hooks need a one-time interactive **trust** prompt Codex only shows in
interactive mode (`--dangerously-bypass-hook-trust` exists for exactly this
gap). Run interactively, the trust prompt appeared, was accepted, and the
hook fired — confirmed on disk, both the test marker and a real
`trusted_hash` Codex wrote into `config.toml`'s own `[hooks.state]`.

So: the alarm is reachable through a real, now-known hook path — building it
(a `cc-notify` dialect for Codex's actual payload shape, `install-hooks.sh`
support) is what's left, not a technical unknown. The app-server socket
remains a viable alternative, just no longer the only option.

**Two more logged as follow-ups, not built:** Codex's own "create N sub
agents" tool doesn't create the per-child file Claude's grouping needs — it
logs entirely inside the parent's own transcript instead, so it can't be
shown as grouped children without a genuinely different parsing path. And a
Codex row always jumps to Finder, never a terminal — `CodexWatcher` has no
live process to find a tty from, unlike a hook, which runs inside the CLI
itself. Both detailed in `docs/CODEX-INTEGRATION.md`'s "Open" section.

### Gemini (researched 2026-08-11, not installed)

Config: `~/.gemini/settings.json` (same shape as Claude's). Input fields are
**snake_case and identical to Claude's** — `session_id`, `cwd`,
`hook_event_name`, `transcript_path`, `timestamp`, `tool_name`, `tool_input`,
`notification_type`, `message`.

Event names differ, so aliases would be needed:

| Gemini | maps to |
|---|---|
| `SessionStart`, `SessionEnd`, `Notification` | **already work unchanged** |
| `BeforeAgent` (`prompt`) | prompt-submit |
| `AfterAgent` (`prompt_response`, *not* `last_assistant_message`) | stop |
| `BeforeTool` (`tool_name`, `tool_input`) | pre-tool-use |

Deliberately **not implemented**: writing an adapter from documentation rather
than measured payloads is exactly what failed with Grok, where the hook fired
for hours into a script that silently dropped every event. Install it, probe it,
then write the code.

*To add a CLI:* register `cc-notify` on its hook events, run the probe in
`docs/HOOK-PAYLOADS.md`, read the real payloads, then extend `get()` and the
event mapping. Nothing in the Swift should need to change.

---

## Design limits (deliberate, not bugs)

- **Live subagent tracking is Grok-only, but not through `SubagentStart`.**
  Claude Code has no start-side event carrying an `agent_id`, so its children
  can only appear once finished. Grok's `spawn_subagent` was believed to fire
  `SubagentStart` for exactly this reason — a live test (2026-09-10) showed it
  fires **neither** `SubagentStart` nor `SubagentStop`, ever. Grok subagents
  are still grouped live, just not through a hook: see
  `docs/GROK-SUBAGENT-GROUPING.md`.
- **Rows outlive their sessions on Claude.** Claude never says a session ended,
  so mtime and the 24h purge are the entire lifecycle. Grok's `SessionEnd`
  removes rows immediately; Claude rows linger until purge.
- **No session titles outside Claude.** `session_title` is Claude-only; other
  CLIs fall back to the folder name.
- **Per-project theming is out** for v1 (SPEC §6), by choice.
- **The app never reads `~/.claude/` or any CLI's state.** Everything arrives
  through the JSON lines. A CLI update can only ever break the script.
- **The panel and other apps' full-screen spaces.** With **Always on top on** the
  panel floats over another app's full-screen space — that is the switch's
  purpose. With it **off** the panel is absent from full-screen spaces and
  reappears when you leave. There is no public API to detect another app's
  full-screen state, so this is WindowServer-driven via `.fullScreenNone` /
  withholding `.fullScreenAuxiliary`, not something the app decides frame by
  frame. `.fullScreenNone` keeping a `.canJoinAllSpaces` window off a full-screen
  space is community-standard and Apple-DTS-suggested, but not a written API
  contract — re-verify on a macOS bump. Toggling "always on top" off *while
  already inside* another app's full-screen space may not evict the panel until
  the next Space change.
- **Z-order flash on Space entry** (while `.canJoinAllSpaces` is in use):
  arriving on a new Space with "Show on all Spaces" on, the panel can render
  behind an overlapping window for a frame or two before returning to its level.
  A WindowServer transition artefact, accepted. Only affects the Always-on-top +
  all-Spaces user.

---

## Operational risks

- **The Developer ID private key exists in one place**: the login keychain on
  Walter's MacBook Air. It is not backed up yet. Lose it and Ground Control can
  never be signed as the same developer again — every existing user gets a
  security warning on the next update, because the identity changed. Export a
  `.p12` (Xcode → Settings → Accounts → Manage Certificates → right-click →
  Export) and keep it off the repo; `.gitignore` blocks `*.p12`.
  Certificate: `Walter Mak (XHRF4FQMBA)`, G2, expires 12 Aug 2031.
- **Bump `CFBundleShortVersionString`** in `Packaging/Info.plist` before each
  release; it names the dmg, so shipping twice at the same version silently
  overwrites the previous file.

## Not yet built

- **Avatar keying.** `removeBackground` exists only on window and background
  art. `Theme.Avatar.Asset` is a bare URL, so an avatar arriving with a flat
  green backdrop stays green — it needs real alpha. Backgrounds get keyed per
  frame, avatars not at all.
- Row background images (`rowBackground` as an asset) — only window, title bar
  and footer accept art.
- Matrix personality beyond colour and words: cell shape (blocks / dots /
  pills), cell density, per-theme pattern choice, custom at-rest art, and an
  off switch. Colour and `matrix.messages` are themeable today; none of the
  rest is.
- `PostToolUse` / `PermissionDenied` handling, which Grok and Codex both offer.
- A despeckle pass for keyed GIFs. Colour quantisation dithers an outline into
  stray opaque pixels — 2,189 of them in the unicorn frame, ~1% of its opaque
  area — which read as a speckled fringe. A PNG avoids it at the source.

## Silence is the failure mode here

Three of this project's worst bugs were invisible rather than broken, which is
why the newer parts report rather than cope:

- Hooks must never interrupt an agent, so `cc-notify` exits 0 on everything.
  "Wrong field name" and "nothing happened" look identical. This is why Grok
  support was silently dead until someone went looking.
- A manifest that would not parse fell back to the built-in theme without a
  word, so Settings named the chosen theme in the picker while describing the
  built-in one beside it. A stale build reading a newer manifest looked exactly
  like a typo. Both now surface through `Theme.warnings`.
- An overlay skin whose middle is solid covers the whole panel: no error, no
  partial render, an app that is simply not on screen. `SkinCheck` measures the
  middle and demotes such a skin to a background rather than letting it hide
  everything.
