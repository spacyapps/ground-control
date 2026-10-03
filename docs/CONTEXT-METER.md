# Context meter

A small fillable meter under the text of a Claude Code row showing how full that
session's context window is: width is the percentage; a 1px outline, pale green,
and the fill both turn red from 85%.

Claude Code only, and only with the mod below. A row nobody has reported on
draws no bar — absent means unknown, never empty.

## Why a mod

No hook payload carries the figure, and the transcript does not either: it has
token counts but not the window size, which depends on the model and on whether
the 1M-token window is on (`claude-sonnet-5-5` reads the same either way). A
Claude Code mod can ask for the finished percentage with `$.session.usage()`,
the same number the status line shows as `used_percentage`.

## The contract

`cc-notify` accepts one synthetic event, `ContextUsage`:

    {"hook_event_name": "ContextUsage", "session_id": "<id>", "context_percent": 42}

- It is not a hook; Claude Code never fires it. Anything may send it.
- The last line of a session file is the row's whole state, so `cc-notify`
  re-emits the previous line with only `context_percent` changed, keeping its
  `ts` so the elapsed timer does not restart.
- No existing line means no row yet; the event never creates one.
- Ordinary hook events carry the last percentage forward, or the next tool call
  would erase the bar.
- The value is clamped to 0-100; a non-number is ignored.

The app reads it as `SessionEvent.contextPercent` and draws it in
`ContextMeter.draw`, under any theme overlay: a theme whose art
covers the meter hides it.

## The mod

`Mods/context-meter/` — a Claude Code plugin of one hook. After each main-loop
turn it reads `$.session.usage()` and sends the event above through
`~/.groundcontrol/bin/cc-notify`. Subagents are skipped: they share their
parent's window. Every failure is swallowed, so a meter can never get in the
way of a turn. `claude plugin test Mods/context-meter` runs its tests.

The app does not install it, for the same reason it never registers hooks: it
only reads. The built app carries a copy at
`GroundControl.app/Contents/Resources/Mods/context-meter`. To load it for
every session, add one key to the `env` block of `~/.claude/settings.json` and
restart Claude Code:

    "env": { "CLAUDE_CODE_PLUGIN_DIRS": "/path/to/context-meter" }

Absolute path; `~` is allowed. From a checkout, point it at `Mods/context-meter`.
For a single session instead: `claude --plugin-dir <folder>`.

## How the loading route was checked

2026-10-03, against a throwaway plugin that wrote a marker file when it loaded:

| Route | Loaded |
| --- | --- |
| `claude --plugin-dir <folder>` | yes |
| `CLAUDE_CODE_PLUGIN_DIRS` in the process environment | yes |
| `CLAUDE_CODE_PLUGIN_DIRS` in the `env` block of `settings.json` | yes (a separate `CLAUDE_CONFIG_DIR`, and a control without the key did not) |
| a copy in a project's `.claude/skills/<name>` | no (headless `claude -p`) |

The `settings.json` route was then seen working on a real session: the meter
drew on the row after one turn. The `env` block reaches every Claude Code the
user starts, including the desktop app's, which a shell profile would not.

## Not verified

How the percent behaves across a compaction. Whether the app-bundle path keeps
working if the app is moved out of `/Applications` (the line must be edited).
