#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Checks the context meter's Claude Code half still works after a CLI update:
# the mod must still get a reading from `$.session.usage()` after a turn, and
# the reading must fall after a real /compact.
#
#   ./Scripts/probe-context-meter.sh
#
# Three headless `claude -p` turns on haiku (a few cents): read two big docs,
# /compact, then one more turn. The mod runs from a scratch copy whose
# cc-notify path is rewritten to a spy that logs stdin, so nothing reaches the
# real panel. The user's own settings are left out (--setting-sources project).
#
# Not covered: that the app draws the bar (unit-tested), or an *idle*
# compaction, which only happens on a real interactive session left alone.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cwd" "$WORK/mod"

cp -R "$ROOT/Mods/context-meter/." "$WORK/mod/"
cp "$ROOT/docs/LIMITATIONS.md" "$ROOT/docs/HOOK-PAYLOADS.md" "$WORK/cwd/"
printf '#!/bin/bash\n{ date +%%s; cat; echo; } >> %s/events.log\n' "$WORK" > "$WORK/spy.sh"
chmod +x "$WORK/spy.sh"
# The mod calls ${home}/.groundcontrol/bin/cc-notify; point it at the spy.
sed -i '' "s#\`\${home}/.groundcontrol/bin/cc-notify\`#'$WORK/spy.sh'#" "$WORK/mod/hooks/register.ts"
grep -q "$WORK/spy.sh" "$WORK/mod/hooks/register.ts" || { echo "could not repoint the mod at the spy"; exit 1; }

turn() { # prompt, extra claude args…
  local prompt="$1"; shift
  (cd "$WORK/cwd" && claude -p --model haiku --plugin-dir "$WORK/mod" --setting-sources project "$@" <<< "$prompt" >/dev/null 2>&1) || true
}

echo "Claude Code $(claude --version)"
turn "Read LIMITATIONS.md and HOOK-PAYLOADS.md fully, then reply with one word: ok" --allowedTools Read
turn "/compact" --continue
turn "reply with one word: ok" --continue

pcts=($(grep -o '"context_percent":[0-9.]*' "$WORK/events.log" 2>/dev/null | cut -d: -f2 || true))
sid=$(grep -o '"session_id":"[^"]*"' "$WORK/events.log" 2>/dev/null | head -1 | cut -d'"' -f4 || true)
compacted=0
[ -n "$sid" ] && compacted=$(cat "$HOME"/.claude/projects/*/"$sid".jsonl 2>/dev/null | grep -c compact_boundary || true)
echo "readings: ${pcts[*]:-none}   compact_boundary in transcript: $([ "$compacted" -gt 0 ] && echo yes || echo NO)"

if [ "${#pcts[@]}" -lt 2 ]; then echo "FAIL: the mod reported fewer than two readings"; exit 1; fi
if [ "$compacted" -eq 0 ]; then echo "FAIL: /compact never ran, so the drop proves nothing"; exit 1; fi
first="${pcts[0]}"; last="${pcts[${#pcts[@]}-1]}"
if python3 -I -c "import sys; sys.exit(0 if float('$last') < float('$first') else 1)"; then
  echo "PASS: meter fed after each turn and fell after /compact ($first -> $last)"
else
  echo "FAIL: reading did not fall after /compact ($first -> $last)"; exit 1
fi
