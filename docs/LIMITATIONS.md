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

---

## Unverified assumptions

### 1. The red alarm has no confirmed trigger

`idle_prompt` notifications are deliberately skipped (SPEC §3) because they mean
"Claude finished, your turn", not "Claude is blocked". That is right for every
payload we have measured — but `idle_prompt` is the **only** `notification_type`
ever observed, because `permission_mode` is `auto` on this machine and
permission prompts never fire.

So the alarm path is correct-by-construction and **unproven end to end**.

*To verify:* run a session under a stricter permission mode, let Claude ask for
something, capture the payload, confirm its `notification_type` and that the row
goes red. Grok's `PermissionDenied` event is a second candidate trigger.

### 2. Internal-agent filtering — **now verified** (2026-08-11)

`AgentGrouper` hides children whose `agent_type` is empty. Two deliberately
spawned subagents both reported `agent_type: "Explore"` and appeared as
children, while every internal agent on disk reported `""` and was hidden —
their messages being echoes of the user's own prompts ("commit", "rename it to
avaterm"), which is exactly what made them misleading on screen.

Still a heuristic rather than a guarantee: a real subagent *could* report no
type. `defaults write GroundControl showsInternalAgents -bool YES`, or the
checkbox in Settings → Advanced, brings them back.

### 3. Background images have never been rendered

Nine-slice resolution, cap insets, modes and caching are unit-tested, but **no
theme with real background art exists**, so nothing has drawn one on screen.
The cap-inset orientation in particular (which edge is which) is asserted by
tests against my own code, not against a picture.

*To verify:* generate a theme with a `windowBackground` and resize the panel.

### 4. iTerm2 jump-to-tab is written but untested

iTerm2 is not installed here. The script addresses it by bundle id and is only
attempted when running, so a machine without it is unaffected — but the
AppleScript itself has never executed.

---

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

## Not yet built

- Packaging: `build-dmg.sh`, `Info.plist` with `LSUIElement`, menu-bar icon,
  release build. The app currently only runs via `swift run`.
- Row background images (`rowBackground` as an asset) — only window, title bar
  and footer accept art.
- `PostToolUse` / `PermissionDenied` handling, which Grok and Codex both offer.
