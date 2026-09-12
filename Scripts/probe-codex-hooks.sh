#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Captures what OpenAI's Codex CLI sends to a hook, so an integration can be
# built from measured payloads instead of documentation.
#
#   ./Scripts/probe-codex-hooks.sh              install the probe
#   ./Scripts/probe-codex-hooks.sh --show       print what has been captured
#   ./Scripts/probe-codex-hooks.sh --uninstall  remove it again
#
# Today `CodexWatcher` reads Codex's files after the fact, which cannot see the
# one moment that matters most: Codex writes nothing at all while it waits on
# your approval, so a blocked session never turns red. `permissionRequest` is
# the event that should carry it. Whether it does — and what a Codex payload
# even looks like — is unmeasured, and docs/LIMITATIONS.md records two
# integrations written from documentation that silently did nothing.
#
# The probe only observes: no stdout, so it returns no decision, and exit 0
# always, so it cannot block a turn.
set -euo pipefail

CODEX="$HOME/.codex"
CONFIG="$CODEX/config.toml"
SCRIPT="$CODEX/hooks/gc-probe.sh"
LOG="$CODEX/gc-hook-probe.log"
BEGIN="# >>> ground-control hook probe >>>"
END="# <<< ground-control hook probe <<<"

# Codex's twelve events, **PascalCased** — that is the TOML spelling, taken
# from `codex-rs/config/src/hook_config.rs`, and it differs from the camelCase
# the wire protocol uses (see docs/CODEX-INTEGRATION.md). Every event is
# registered, because the point is to learn which ones fire at all.
#
#   PermissionRequest -> the alarm; the whole reason for this probe
#   Stop / SessionEnd -> a precise end, replacing CodexWatcher's folder guess
#   SubagentStart/Stop -> whether "create N sub agents" is visible from outside
#   PreToolUse etc.   -> whether a row can say more than "Working…"
EVENTS=(
  SessionStart
  SessionEnd
  UserPromptSubmit
  PreToolUse
  PostToolUse
  PermissionRequest
  PreCompact
  PostCompact
  SubagentStart
  SubagentStop
  Stop
  Interrupt
)

case "${1:-install}" in
--show)
  if [ ! -f "$LOG" ]; then
    echo "Nothing captured yet — $LOG does not exist."
    echo "Run an interactive \`codex\` turn first (not \`codex exec\` — an"
    echo "untrusted hook never fires there), ideally one that asks permission."
    exit 0
  fi
  echo "==> $LOG  ($(wc -l < "$LOG" | tr -d ' ') lines)"
  echo "==> events seen:"
  grep -o '^==== [A-Za-z]*' "$LOG" | sort | uniq -c | sed 's/^/    /'
  echo
  cat "$LOG"
  exit 0
  ;;
--uninstall)
  rm -f "$SCRIPT" "$LOG"
  if [ -f "$CONFIG" ]; then
    # Strip only the block between the sentinels, rather than restoring the
    # backup wholesale: accepting the trust prompt makes Codex write a real
    # `[hooks.state]` record into this same file, along with anything else it
    # has learned since. A restore would throw that away too.
    awk -v b="$BEGIN" -v e="$END" '
      $0 == b { skip = 1 } skip != 1 { print } $0 == e { skip = 0 }
    ' "$CONFIG" > "$CONFIG.gc-tmp"
    mv "$CONFIG.gc-tmp" "$CONFIG"
    echo "==> Removed the probe block from $CONFIG"
    echo "    (Your pre-probe copy is still at $CONFIG.gc-backup, if one was made.)"
  fi
  echo "==> Probe removed. Codex reads config.toml at startup, so restart it."
  exit 0
  ;;
esac

if ! command -v codex >/dev/null 2>&1; then
  echo "codex is not on PATH — nothing to probe." >&2
  exit 1
fi

if grep -qF "$BEGIN" "$CONFIG" 2>/dev/null; then
  echo "==> The probe is already in $CONFIG. --uninstall first to reinstall."
  exit 0
fi

mkdir -p "$CODEX/hooks"

# config.toml is a file Walter actually uses — it holds the model choice and
# per-project trust. Never rewrite it; back it up, then append.
if [ -f "$CONFIG" ] && [ ! -f "$CONFIG.gc-backup" ]; then
  cp "$CONFIG" "$CONFIG.gc-backup"
  echo "==> Backed up $CONFIG to $CONFIG.gc-backup"
fi

cat > "$SCRIPT" <<'PROBE'
#!/bin/bash
# Written by Scripts/probe-codex-hooks.sh. Observes and nothing else.
# No stdout, so no permission decision; exit 0 always, so it cannot block.
LOG="$HOME/.codex/gc-hook-probe.log"
{
  printf '==== %s  %s\n' "${1:-unknown}" "$(date +%H:%M:%S)"
  printf '--- argv: %s\n' "$*"
  # Which channel carries the payload is exactly what is unknown, so capture
  # all three. Claude and Cursor both pipe JSON on stdin; Codex may instead
  # pass a file path, or nothing but environment.
  env | grep -i '^CODEX' | sed 's/^/--- env:  /'
  printf '%s\n' '--- stdin:'
  # Guarded: if Codex attaches no pipe, stdin is the terminal, and a bare
  # `cat` would sit there reading Walter's keystrokes and hang the turn.
  if [ -t 0 ]; then printf '(no pipe — stdin is a tty)\n'; else cat; fi
  printf '\n'
} >> "$LOG" 2>/dev/null
exit 0
PROBE
chmod +x "$SCRIPT"

# A handler is a structured MatcherGroup, never a bare string — the flat-string
# shape was ruled out live. The known-good block is `[[hooks.<Event>]]` then
# `[[hooks.<Event>.hooks]]` with `type = "command"`; the command string is
# shell-interpreted (the confirming test used a `>>` redirect inside it), so
# passing the event name as an argument is safe.
{
  printf '\n%s\n' "$BEGIN"
  printf '# Observe-only. Remove with: ./Scripts/probe-codex-hooks.sh --uninstall\n'
  for event in "${EVENTS[@]}"; do
    printf '\n[[hooks.%s]]\n\n[[hooks.%s.hooks]]\ntype = "command"\ncommand = "%s %s"\n' \
      "$event" "$event" "$SCRIPT" "$event"
  done
  printf '%s\n' "$END"
} >> "$CONFIG"

echo "==> Probe installed"
echo "    script: $SCRIPT"
echo "    config: $CONFIG  (${#EVENTS[@]} events appended)"
echo "    log:    $LOG"
echo
echo "Next:"
echo "  1. Start interactive \`codex\` — NOT \`codex exec\`. A hook has to be"
echo "     trusted once before it runs, and only the interactive startup asks."
echo "  2. Accept the trust prompt when it appears."
echo "  3. One turn that reads a file, runs a shell command, AND needs your"
echo "     approval — each reveals a different event."
echo "  4. Exit codex, then: ./Scripts/probe-codex-hooks.sh --show"
echo
echo "An empty log after all that means the hooks were never trusted; check"
echo "$CONFIG for a [hooks.state] block naming a trusted_hash."
