#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Seeds one fake session per state so a theme can be judged in one look.
#
# Some states are otherwise hard to see on demand — `needsInput` in particular,
# since the alarm has no reliable trigger under permissive permission modes.
# Without this you cannot check the face a theme draws for the state that
# matters most.
#
#   ./Scripts/theme-preview.sh          seed the preview rows
#   ./Scripts/theme-preview.sh clear    remove them, leaving real sessions alone
set -euo pipefail

DIR="${TMPDIR:-/tmp}/groundcontrol"
PREFIX="preview-"
mkdir -p "$DIR/agents"

if [ "${1:-seed}" = "clear" ]; then
  rm -f "$DIR/${PREFIX}"*.jsonl "$DIR/agents/${PREFIX}"*.jsonl
  echo "Preview rows removed. Real sessions untouched."
  exit 0
fi

now=$(date +%s)
row() { # id name state message needs_action age
  printf '{"schema":1,"source":"preview","session_id":"%s%s","name":"%s","cwd":"/tmp/%s",' \
    "$PREFIX" "$1" "$2" "$2" > "$DIR/${PREFIX}$1.jsonl"
  printf '"tty":null,"event":"Preview","state":"%s","message":"%s","needs_action":%s,' \
    "$3" "$4" "$5" >> "$DIR/${PREFIX}$1.jsonl"
  printf '"notification_type":"permission_request","transcript_path":"","ts":%s}\n' \
    "$((now - $6))" >> "$DIR/${PREFIX}$1.jsonl"
}

row idle       "idle-state"    idle       "Quiet — nothing running"                false 900
row working    "working-state" working    "Bash: swift build --configuration release" false 4
row needsinput "needs-you"     needsInput "Allow npm install to run?"              true  240
row done       "done-state"    done       "Finished. All 102 tests passed."        false 45

# A group, so the disclosure triangle and child rows are visible too.
printf '{"schema":1,"session_id":"%sworking","agent_id":"previewA","agent_type":"Explore",' "$PREFIX" \
  > "$DIR/agents/${PREFIX}working__previewA.jsonl"
printf '"state":"working","message":"Searching the theme folder","needs_action":false,"ts":%s}\n' "$now" \
  >> "$DIR/agents/${PREFIX}working__previewA.jsonl"

echo "Seeded 4 preview rows + 1 subagent in $DIR"
echo "One per state: idle, working, needsInput (red), done."
echo "Run './Scripts/theme-preview.sh clear' when finished."
