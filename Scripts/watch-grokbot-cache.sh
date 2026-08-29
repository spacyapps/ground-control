#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Prints a line every time Grok Bot rewrites its roster or a transcript blob,
# so you can see whether state updates mid-turn or only at the end, and what a
# "needs you" card looks like the moment it appears.
#
#   ./Scripts/watch-grokbot-cache.sh            follow live
#   ./Scripts/watch-grokbot-cache.sh --dump     print the current roster once and exit
#
# Background: docs/GROK-BOT-INTEGRATION.md. Grok Bot fires no local hooks; this
# cache is the only local signal. It is undocumented — the roster schema was
# already at v3 when first read — so treat every field as provisional.
#
# bash 3.2 safe: no associative arrays.
set -euo pipefail

DIR="$HOME/Library/Application Support/Grok Bot/sand-client-persistence"

decode() {  # base32 (lowercase, unpadded) -> slice key
  python3 -c "import base64,sys;n=sys.argv[1];print(base64.b32decode(n.upper()+'='*((8-len(n)%8)%8)).decode('utf8','replace'))" "$1" 2>/dev/null
}

roster_line() {
  python3 -c "
import json,sys,time
d=json.load(open(sys.argv[1]))
for x in d['value']['rows']:
    p=x.get('lastEntry',{}).get('sessionPreview') or {}
    print(f\"{time.strftime('%H:%M:%S')} ROSTER {x['name']}: updated={x.get('updatedAt')} unread={x.get('unreadCount')} awaiting={x.get('awaitingUserResponse')} preview={p.get('kind')}\")" "$1" 2>/dev/null
}

transcript_line() {
  python3 -c "
import json,sys,time
d=json.load(open(sys.argv[1])); e=d['value']['entries']; l=e[-1]
print(f\"{time.strftime('%H:%M:%S')} TRANSCRIPT n={len(e)} last={l.get('kind')}/{l.get('id')} type={(l.get('message') or {}).get('type')}\")" "$1" 2>/dev/null
}

if [ ! -d "$DIR" ]; then
  echo "Grok Bot is not installed (no $DIR)"; exit 0
fi

if [ "${1:-}" = "--dump" ]; then
  for f in "$DIR"/*.blob; do
    [ -e "$f" ] || continue
    key=$(decode "$(basename "${f%.blob}")")
    case "$key" in
      *roster.last-roster) echo "== $key =="; python3 -m json.tool "$f" ;;
    esac
  done
  exit 0
fi

echo "watching $DIR  (Ctrl-C to stop)"
STATE=$(mktemp)
first=1
while true; do
  for f in "$DIR"/*.blob; do
    [ -e "$f" ] || continue
    bn=$(basename "$f")
    key=$(decode "${bn%.blob}")
    case "$key" in
      *roster.last-roster|*transcript.replicas.*) : ;;
      *) continue ;;   # composer-drafts rewrites per keystroke; ignore it and every other slice
    esac
    m=$(stat -f %m "$f" 2>/dev/null)
    prev=$(grep "^$bn " "$STATE" 2>/dev/null | awk '{print $2}')
    [ "$prev" = "$m" ] && continue
    grep -v "^$bn " "$STATE" > "$STATE.tmp" 2>/dev/null || true; mv "$STATE.tmp" "$STATE" 2>/dev/null || true
    echo "$bn $m" >> "$STATE"
    [ -n "$first" ] && continue   # skip the startup enumeration
    case "$key" in
      *roster.last-roster)       roster_line "$f" ;;
      *transcript.replicas.*)    transcript_line "$f" ;;
    esac
  done
  first=""
  sleep 0.4
done
