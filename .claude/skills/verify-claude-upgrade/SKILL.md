---
name: verify-claude-upgrade
description: >-
  Use after Claude Code updates (or when asked "anything to test in the new
  claude?") to check Ground Control still works against it. Runs the payload
  probe, lists the hand-checks the probe cannot do, and records the result in
  docs/LIMITATIONS.md.
---

# Verifying a Claude Code upgrade

Ground Control only ever sees what Claude Code's hooks and transcript files
say. An upgrade can break it silently, so every version gets the same pass.

## 1. Read what changed (2 min)

The last verified version is the newest "Claude Code … keeps the hook contract"
row in `docs/LIMITATIONS.md`. Read the changelog from there to now:

    gh api repos/anthropics/claude-code/contents/CHANGELOG.md \
      -H "Accept: application/vnd.github.raw" | head -150

Look for: hook events or payload fields, `permission_mode` / auto mode,
compaction, session or transcript file format, background (`--bg`) sessions,
agent teams, terminal escape sequences. Cloud, VS Code, Remote Control and
Claude Tag items do not reach GC; skip them.

## 2. Run the probe (1 min, a few cents)

    ./Scripts/probe-claude-hooks.sh

One real `claude -p` turn with an observe-only hook on every event, diffed
against `Scripts/claude-hook-keys.baseline`. `NEW KEYS` is usually harmless
(Claude added a field) but read it; `MISSING` or a vanished event is a break.
The probe leaves the user's own hooks out, so no stray row reaches the panel.

When the diff is understood: `./Scripts/probe-claude-hooks.sh --accept` and
commit the baseline.

Known quirk: headless `-p` sends no `session_title` on `UserPromptSubmit`; the
interactive payload in `HOOK-PAYLOADS.md` does. Absence there is not drift.

## 3. Hand-checks the probe cannot do

Run these in a real interactive `claude` with Ground Control up, and tick only
what you actually saw. Anything skipped goes in the "Not rerun" list.

- [ ] **Red alarm**: ask a question (`AskUserQuestion`) under `auto`; row goes
      red, then clears on the answer.
- [ ] **Interrupted permission prompt**: Esc at a prompt; the row must not stay
      red or working.
- [ ] **Context meter**: fills, then drops after `/compact`, and after an idle
      compaction if the version touched compaction. (A headless version was
      tried on 2.1.306 and dropped: it left a transcript folder per run in
      `~/.claude/projects/`, and a throwaway `CLAUDE_CONFIG_DIR` loses auth.)
- [ ] **Subagent**: a 30s+ subagent shows as a working child row.
- [ ] **Background**: `claude --bg "<prompt>"`; hook env has `CLAUDE_JOB_DIR`,
      still no `CLAUDE_CODE_SESSION_KIND` (the probe's env list shows the same
      for foreground).
- [ ] **SessionEnd**: quit with a background `sleep` running; row file removed.
- [ ] **Terminal.app**: no stray `>0q` / `>4m` / `GOK` printed at startup or
      exit. Vim-mode Esc is still sane.
- [ ] Anything the changelog flagged in step 1.

## 4. Record it

Add one row to the Verified table in `docs/LIMITATIONS.md`:
`Claude Code X.Y.Z keeps the hook contract | what was run, what was seen. **Not
rerun:** … | date`. Put the honest "Not rerun" list in the row; an unchecked
box is information. If a payload field changed, update `HOOK-PAYLOADS.md` too.
