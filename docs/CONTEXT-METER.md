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
`SessionRowView.drawContextBar`, under any theme overlay: a theme whose art
covers the meter hides it.

## The mod

`Mods/context-meter/` — a Claude Code plugin of one hook. After each main-loop
turn it reads `$.session.usage()` and sends the event above through
`~/.groundcontrol/bin/cc-notify`. Subagents are skipped: they share their
parent's window. Every failure is swallowed, so a meter can never get in the
way of a turn. `claude plugin test Mods/context-meter` runs its tests.

The app does not install it, for the same reason it never registers hooks: it
only reads. To load it:

    claude --plugin-dir /path/to/ground-control/Mods/context-meter

For every session, name the folder in `CLAUDE_CODE_PLUGIN_DIRS` in the `env`
block of `~/.claude/settings.json` (an absolute path; `~` is allowed).

## Not verified

Written 2026-10-02. Seen working live on one session: the mod reported, the
number reached the row, and the meter drew at that width. Not yet confirmed:
how the percent behaves across a compaction, and the `CLAUDE_CODE_PLUGIN_DIRS`
route (from the mod API's documentation only).
