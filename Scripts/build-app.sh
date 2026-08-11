#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Builds GroundControl.app.
#
# Signs with Developer ID when one exists, and says so plainly when it does
# not — an unsigned build still runs locally, it just makes users right-click
# to open. Signing is never silently skipped.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/GroundControl.app"
# `|| true`: grep exits 1 when there is no Developer ID, and pipefail would
# otherwise abort the whole script before printing a single line.
find_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true
}
IDENTITY="${CODESIGN_IDENTITY:-$(find_identity)}"

echo "==> Building release"
# Universal where the SDKs allow it, native otherwise. The bin path has to be
# queried with the *same* flags — a universal build lands somewhere different
# from a native one, and asking without the flags silently returns the wrong
# directory.
ARCH_FLAGS="--arch arm64 --arch x86_64"
if ! swift build -c release $ARCH_FLAGS >/dev/null 2>&1; then
  echo "    (universal build unavailable, falling back to native)"
  ARCH_FLAGS=""
  swift build -c release
fi

BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path 2>/dev/null | tail -1)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/GroundControl" "$APP/Contents/MacOS/GroundControl"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
[ -f Packaging/AppIcon.icns ] && cp Packaging/AppIcon.icns "$APP/Contents/Resources/"

# SwiftPM emits resources as a bundle beside the binary; it has to travel too
# or Brand.lockup and every themed asset comes back nil at runtime.
for bundle in "$BIN"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/" || true
done

if [ -n "$IDENTITY" ]; then
  echo "==> Signing as: $IDENTITY"
  # --options runtime is the hardened runtime, which notarisation requires and
  # which is why the apple-events entitlement has to be declared.
  codesign --force --deep --options runtime --timestamp \
           --entitlements Packaging/GroundControl.entitlements \
           --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> No 'Developer ID Application' certificate found — building UNSIGNED."
  echo "    The app runs, but users must right-click -> Open on first launch."
  echo "    Create one: Xcode -> Settings -> Accounts -> Manage Certificates -> +"
  # Ad-hoc signing still lets the hardened runtime and entitlements apply
  # locally, so behaviour matches a real build as closely as possible.
  codesign --force --deep --options runtime \
           --entitlements Packaging/GroundControl.entitlements \
           --sign - "$APP"
fi

echo "==> Done: $APP"
du -sh "$APP"
