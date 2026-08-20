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
this" — though nothing has been seen to fire it yet: a model that asks in prose
never reaches it.

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
cwd=/Users/waltermak/Documents/Projects/GroundControlThemes
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
| Real subagents carry `agent_type` | spawned two Explore agents; both `type="Explore"` while every internal one was `""` | 2026-08-11 |
| Background images render | a real theme with a starfield frame, on screen — and it was broken three ways until it was tried | 2026-08-11 |
| Nine-slice cap insets | the frame holds its corners while the panel resizes | 2026-08-11 |
| Jumping to a host app | VS Code session with no tty at all; clicking raised the editor | 2026-08-12 |
| **The red alarm, end to end** | a blocked session turned the row red, the click landed on its tab, and the alarm cleared — watched, not derived | 2026-08-12 |
| opencode plugin API and events | probe plugin logged a real turn; 4 of >100 events matter | 2026-08-19 |
| **opencode's alarm, end to end** | row turned red carrying "List files with details in current directory", and cleared on reply | 2026-08-19 |
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
avaterm"), which is exactly what made them misleading on screen.

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
| Codex | ✓ experimental, `[features] codex_hooks = true` | unconfirmed | same as Claude | untested, likely works |
| Gemini | ✓ `~/.gemini/settings.json` | snake_case, same names | **its own** | needs aliases |
| Cursor | `~/.cursor/hooks.json`, schema `version: 1` | snake_case | **camelCase** (`sessionStart`, `preToolUse`, `stop`) | **working** — no alarm yet |
| opencode | plugin API (`@opencode-ai/plugin`), `event` hook | n/a — TypeScript | n/a | would need a plugin, not a script |

### Codex (researched 2026-08-11, not installed)

Config: `~/.codex/hooks.json` or inline `[hooks]` in `~/.codex/config.toml`;
project-level equivalents require trust. Needs `[features] codex_hooks = true`.

Event names reportedly match Claude's: `SessionStart`, `UserPromptSubmit`,
`PreToolUse`, `PostToolUse`, `PermissionRequest`, `SubagentStart`,
`SubagentStop`, `Stop`. Field casing was **not** confirmed — the official docs
do not reproduce the input schema, and the only example shown is hook *output*
(`permissionDecision`, camelCase). Since `cc-notify` reads both dialects, it may
simply work; nobody has tried.

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

- **Live subagent tracking is Grok-only.** Claude Code has no start-side event
  carrying an `agent_id`, so its children can only appear once finished. Grok's
  `SubagentStart` does, and is used.
- **Rows outlive their sessions on Claude.** Claude never says a session ended,
  so mtime and the 24h purge are the entire lifecycle. Grok's `SessionEnd`
  removes rows immediately; Claude rows linger until purge.
- **No session titles outside Claude.** `session_title` is Claude-only; other
  CLIs fall back to the folder name.
- **Per-project theming is out** for v1 (SPEC §6), by choice.
- **The app never reads `~/.claude/` or any CLI's state.** Everything arrives
  through the JSON lines. A CLI update can only ever break the script.

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
