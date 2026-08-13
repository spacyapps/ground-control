# Known Limitations

What we know is true, what we only *believe* is true, and how to find out. Kept
separate from SPEC.md so the spec can describe the design while this stays
honest about the gaps.

Every claim here is dated. When something is verified, move it up and say how.

---

## Verified (measured, not assumed)

| Thing | How it was proven | When |
|---|---|---|
| Claude Code hook payload fields | probe script dumping raw stdin, all 5 events | 2026-08-10 |
| tty recovery via process-tree walk | printed the walk; `claude` holds the tty | 2026-08-10 |
| Terminal.app jump-to-tab | clicked a row, landed on the right tab | 2026-08-10 |
| Grok hook payloads | probe in `~/.grok/hooks/`, 4 events captured | 2026-08-11 |
| Grok reads `~/.claude/settings.json` | `/hooks` shows `Custom: ~/.claude (9 hooks)` | 2026-08-11 |
| Grok `SessionEnd` removes a row | replayed the real payload; file deleted | 2026-08-11 |
| Real subagents carry `agent_type` | spawned two Explore agents; both `type="Explore"` while every internal one was `""` | 2026-08-11 |
| Background images render | a real theme with a starfield frame, on screen — and it was broken three ways until it was tried | 2026-08-11 |
| Nine-slice cap insets | the frame holds its corners while the panel resizes | 2026-08-11 |
| Jumping to a host app | VS Code session with no tty at all; clicking raised the editor | 2026-08-12 |
| **The red alarm, end to end** | a blocked session turned the row red, the click landed on its tab, and the alarm cleared — watched, not derived | 2026-08-12 |

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

Grok's `PermissionDenied` event remains a second candidate trigger, unmeasured.

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

Still unmeasured: Cursor, Windsurf, Warp, Ghostty and WezTerm. All are expected
to work by the same mechanism — Cursor is a VS Code fork with identically
structured helper bundles — but expected is not measured, and this file exists
to keep that distinction.

### 4. iTerm2 jump-to-tab is written but untested

iTerm2 is not installed here. The script addresses it by bundle id and is only
attempted when running, so a machine without it is unaffected — but the
AppleScript itself has never executed.

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
by running `~/bin/cc-notify` on its lifecycle events. An assistant that does not
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
| Cursor | `~/.cursor/hooks.json` exists | unknown | unknown | unexamined |
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
