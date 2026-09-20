#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# The mechanical half of the licence audit, run before every release.
#
#   ./Scripts/licence-audit.sh
#
# Settings shows three pages — what the app does and does not do, the licence,
# and the disclaimer — and they are the only reason a stranger trusts a monitor
# sitting beside their terminal. Every sentence on them maps to something a
# machine can check. This checks those things.
#
# What it cannot check is whether the prose still describes the product, and
# that is where both real findings came from: a permission prompt nobody had
# written down, and two other applications' files being read by a page that
# still described hooks alone. So this script is a gate, not the audit. When it
# fails, or when it passes and the code has grown a new way of reaching outside
# itself, read the pages with .claude/skills/license-guru.
#
# `SKIP_LICENCE_AUDIT=1` skips it when you mean to, the way --no-verify does.
set -uo pipefail
cd "$(dirname "$0")/.."

# The FSF's AGPL-3.0 text, as shipped. Verified against gnu.org whenever this
# machine is online; the hash is what makes the check work on a plane.
AGPL_SHA256="0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0"

# Counts, not contents. Each of these is the size of a list the pages claim is
# exhaustive, so a change means the prose needs re-reading — the number itself
# proves nothing.
EXPECTED_ENTITLEMENTS=1
EXPECTED_USAGE_DESCRIPTIONS=1
# 11 since 2026-09-20: opening `claude://code/continue` so a click on a Claude
# for Desktop row lands on that conversation rather than whatever was last open.
# Named on the privacy page with the rest.
EXPECTED_REACH_OUT_CALLS=11

fails=0

fail() {
  printf '  FAIL  %s\n' "$1" >&2
  fails=$((fails + 1))
}

pass() {
  printf '  ok    %s\n' "$1"
}

echo "Licence audit"

# --- the licence itself -----------------------------------------------------

actual_sha="$(shasum -a 256 LICENSE | cut -d' ' -f1)"
if [ "$actual_sha" = "$AGPL_SHA256" ]; then
  pass "LICENSE is the FSF text, unmodified"
else
  fail "LICENSE has been edited (sha256 $actual_sha, expected $AGPL_SHA256)"
fi

# Online, confirm the constant above still matches what the FSF publishes — a
# hash pinned once and never re-checked only proves the file has not changed
# since somebody wrote the hash down.
if remote="$(curl -sS --max-time 10 https://www.gnu.org/licenses/agpl-3.0.txt 2>/dev/null)" \
  && [ -n "$remote" ]; then
  remote_sha="$(printf '%s\n' "$remote" | shasum -a 256 | cut -d' ' -f1)"
  if [ "$remote_sha" = "$AGPL_SHA256" ]; then
    pass "the pinned hash still matches gnu.org"
  else
    fail "gnu.org's AGPL text no longer hashes to the pinned value — re-read it before changing anything"
  fi
else
  pass "gnu.org unreachable, checked against the pinned hash alone"
fi

# "agpl-3.0" contains "gpl-3.0", so the [^Aa] is what stops the correct URL
# hiding a wrong claim underneath it.
stale="$(grep -rnE "(^|[^Aa])GPL-3\.0|(^|[^Aa])gpl-3\.0|GNU General Public License" \
  --exclude-dir=.git --exclude-dir=build --exclude-dir=.build --exclude-dir=.claude \
  --exclude=LICENSE --exclude=licence-audit.sh . 2>/dev/null)"
# This file is excluded because it quotes the patterns it hunts for, and a
# checker that flags itself trains you to ignore it.
if [ -z "$stale" ]; then
  pass "no stale GPL-3.0 strings"
else
  fail "a file claims plain GPL-3.0:"
  printf '%s\n' "$stale" >&2
fi

missing_spdx=""
while IFS= read -r f; do
  head -3 "$f" | grep -q SPDX || missing_spdx="$missing_spdx$f"$'\n'
done < <(find Sources Tests Scripts -type f \
  \( -name "*.swift" -o -name "*.sh" -o -name "*.ts" -o -name "cc-notify" \))
if [ -z "$missing_spdx" ]; then
  pass "every source file carries an SPDX header"
else
  fail "missing SPDX header:"
  printf '%s' "$missing_spdx" >&2
fi

# --- "nothing leaves your Mac" ----------------------------------------------

# The strongest claim on the page, and the one that would also pull AGPL §13
# into play. Anything matching here is a redraft, not a warning.
network="$(grep -rn "URLSession\|CFNetwork\|socket(\|urlopen\|requests\.\|http\.client\|urllib\|NSURLConnection" \
  Sources/ Scripts/cc-notify Scripts/opencode-plugin.ts 2>/dev/null)"
if [ -z "$network" ]; then
  pass "no networking API in the app or the emitter"
else
  fail "something can reach the network — 'Nothing leaves your Mac' is now false:"
  printf '%s\n' "$network" >&2
fi

# --- the numbers the page quotes --------------------------------------------

if grep -q "^MAX_MESSAGE = 240$" Scripts/cc-notify; then
  pass "cc-notify still stops at 240 characters, as the page says"
else
  fail "MAX_MESSAGE is no longer 240 — the page promises 'up to 240 characters'"
fi

if grep -q "window: TimeInterval = 24 \* 60 \* 60" Sources/GroundControl/Monitoring/PurgeService.swift; then
  pass "the purge is still 24h, as the page says"
else
  fail "the purge window moved — the page promises 'removed 24 hours after their last activity'"
fi

# --- the lists the page claims are exhaustive -------------------------------

entitlements="$(grep -c '<key>' Packaging/GroundControl.entitlements | tr -d ' ')"
if [ "$entitlements" = "$EXPECTED_ENTITLEMENTS" ]; then
  pass "$entitlements entitlement, unchanged"
else
  fail "entitlements changed ($entitlements, was $EXPECTED_ENTITLEMENTS) — every one is a permission prompt the page must name"
fi

usage="$(grep -c 'UsageDescription' Packaging/Info.plist | tr -d ' ')"
if [ "$usage" = "$EXPECTED_USAGE_DESCRIPTIONS" ]; then
  pass "$usage usage description, unchanged"
else
  fail "usage descriptions changed ($usage, was $EXPECTED_USAGE_DESCRIPTIONS) — macOS will prompt in a way the page does not mention"
fi

# "The only other things it can open are…" is exhaustive by construction, so
# its truth depends on this set not growing quietly.
reach="$(grep -rn "NSWorkspace.shared.open\|openApplication\|selectFile\|activateFileViewerSelecting\|Process()\|NSAppleScript(" \
  Sources/ 2>/dev/null | grep -vc '^\s*//' | tr -d ' ')"
if [ "$reach" = "$EXPECTED_REACH_OUT_CALLS" ]; then
  pass "$reach places reach outside the app, unchanged"
else
  fail "the app reaches outside itself in $reach places, was $EXPECTED_REACH_OUT_CALLS"
  echo "        Re-read 'The only other things it can open' in LegalText.swift," >&2
  echo "        then update EXPECTED_REACH_OUT_CALLS here." >&2
  grep -rn "NSWorkspace.shared.open\|openApplication\|selectFile\|activateFileViewerSelecting\|Process()\|NSAppleScript(" \
    Sources/ 2>/dev/null | grep -v '^\s*//' >&2
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "Licence audit passed. The prose is still yours to check:"
  echo "  does LegalText.swift describe what the app does today?"
  exit 0
fi

echo "Licence audit FAILED: $fails check(s)." >&2
echo "These pages are the only reason a stranger trusts this app." >&2
exit 1
