#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Captures what Cursor's own agent sends to a hook, so an integration can be
# built from measured payloads instead of documentation.
#
#   ./Scripts/probe-cursor-hooks.sh              install the probe
#   ./Scripts/probe-cursor-hooks.sh --show       print what has been captured
#   ./Scripts/probe-cursor-hooks.sh --uninstall  remove it again
#
# This exists because docs/LIMITATIONS.md records two integrations that were
# written from documentation and silently did nothing. Cursor's hook docs
# describe the *output* fields well and never show an input payload, so the
# field names, the casing, and which event carries a permission prompt are all
# unknown until something writes them down.
#
# The probe only observes. It prints nothing on stdout, so it returns no
# permission decision, and it exits 0 always. Cursor fails open unless a hook
# sets `failClosed`, which this does not — so a broken probe cannot block the
# agent, and neither can a full disk.
set -euo pipefail

CURSOR="$HOME/.cursor"
HOOKS="$CURSOR/hooks.json"
SCRIPT="$CURSOR/hooks/gc-probe.sh"
LOG="$CURSOR/gc-hook-probe.log"

# Cursor's agent events, camelCased — its own spelling, not Claude's. Every one
# that could plausibly carry a session, a prompt, a tool call or a permission
# request, because the point is to find out which does.
EVENTS=(
  sessionStart
  sessionEnd
  beforeSubmitPrompt
  preToolUse
  postToolUse
  postToolUseFailure
  beforeShellExecution
  afterShellExecution
  beforeMCPExecution
  afterMCPExecution
  beforeReadFile
  afterFileEdit
  subagentStart
  subagentStop
  preCompact
  afterAgentResponse
  afterAgentThought
  stop
)

case "${1:-install}" in
--show)
  if [ ! -f "$LOG" ]; then
    echo "Nothing captured yet — $LOG does not exist."
    echo "Run a Composer turn in Cursor first, ideally one that asks to run a command."
    exit 0
  fi
  echo "==> $LOG  ($(wc -l < "$LOG" | tr -d ' ') lines)"
  echo "==> events seen:"
  grep -o '^==== [a-zA-Z]*' "$LOG" | sort | uniq -c | sed 's/^/    /'
  echo
  cat "$LOG"
  exit 0
  ;;
--uninstall)
  rm -f "$SCRIPT" "$LOG"
  if [ -f "$HOOKS.gc-backup" ]; then
    mv "$HOOKS.gc-backup" "$HOOKS"
    echo "==> Restored your previous $HOOKS"
  else
    rm -f "$HOOKS"
    echo "==> Removed $HOOKS (there was none before)"
  fi
  echo "==> Probe removed. Restart Cursor to be sure it stops firing."
  exit 0
  ;;
esac

mkdir -p "$CURSOR/hooks"

# Never clobber hooks the user already has. Cursor reads one file, so a probe
# that overwrites it would silently disable their real hooks.
if [ -f "$HOOKS" ] && [ ! -f "$HOOKS.gc-backup" ]; then
  cp "$HOOKS" "$HOOKS.gc-backup"
  echo "==> Backed up your existing hooks.json to $HOOKS.gc-backup"
  echo "    --uninstall puts it back."
fi

cat > "$SCRIPT" <<'PROBE'
#!/bin/bash
# Written by Scripts/probe-cursor-hooks.sh. Observes and nothing else.
# No stdout, so no permission decision; exit 0 always, so it cannot block.
LOG="$HOME/.cursor/gc-hook-probe.log"
{
  printf '==== %s  %s\n' "${1:-unknown}" "$(date +%H:%M:%S)"
  cat
  printf '\n'
} >> "$LOG" 2>/dev/null
exit 0
PROBE
chmod +x "$SCRIPT"

# Written by hand rather than with jq: the docs warn that helper binaries may
# not be on the hook environment's PATH, and this file is small enough that
# depending on one would be the only fragile thing about it.
{
  printf '{\n  "version": 1,\n  "hooks": {\n'
  for index in "${!EVENTS[@]}"; do
    event="${EVENTS[$index]}"
    comma=","
    [ "$index" -eq $(( ${#EVENTS[@]} - 1 )) ] && comma=""
    printf '    "%s": [{ "command": "%s %s" }]%s\n' "$event" "$SCRIPT" "$event" "$comma"
  done
  printf '  }\n}\n'
} > "$HOOKS"

echo "==> Probe installed"
echo "    script: $SCRIPT"
echo "    config: $HOOKS  (${#EVENTS[@]} events)"
echo "    log:    $LOG"
echo
echo "Next:"
echo "  1. Restart Cursor — it reads hooks.json at startup."
echo "  2. Run one Composer turn that reads a file AND asks to run a shell command."
echo "  3. ./Scripts/probe-cursor-hooks.sh --show"
echo
echo "Check Cursor's Settings > Hooks tab if nothing appears; it lists what loaded."
