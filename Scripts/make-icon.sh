#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Builds AppIcon.icns from the Ground Control artwork.
#
# The source is square, full-bleed art. make-app-icon.swift gives it the shape
# macOS expects — Apple's margin, rounded corners, transparent surround —
# because recent macOS rounds nothing for you: whatever the .icns holds is what
# the Dock shows, hard corners and all.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Packaging/AppIcon-source.png"
OUT="Packaging/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift Scripts/make-app-icon.swift "$SRC" "$WORK/square.png" 1024

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size          "$WORK/square.png" --out "$ICONSET/icon_${size}x${size}.png"      >/dev/null
  sips -z $((size*2)) $((size*2)) "$WORK/square.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns "$ICONSET" --output "$OUT"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
