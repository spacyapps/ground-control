#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Builds AppIcon.icns from the SpacyApps glyph.
#
# The source art is wider than it is tall, so it is centred on a square canvas
# first — sips would otherwise squash it, and a distorted icon is the most
# visible possible flaw in a menu-bar app.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Sources/SkinTerminal/Resources/logo-glyph.png"
OUT="Packaging/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift Scripts/square-image.swift "$SRC" "$WORK/square.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size          "$WORK/square.png" --out "$ICONSET/icon_${size}x${size}.png"      >/dev/null
  sips -z $((size*2)) $((size*2)) "$WORK/square.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns "$ICONSET" --output "$OUT"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
