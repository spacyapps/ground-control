#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Builds, styles, notarises and staples a distributable disk image — the
# drag-to-Applications window people expect from a Mac app.
#
#   ./Scripts/build-dmg.sh               build, notarise, staple
#   SKIP_NOTARIZE=1 ./Scripts/build-dmg.sh   local dmg, no round trip to Apple
#
# Needs create-dmg (Homebrew): it drives the mount / Finder-AppleScript /
# convert dance that lays out the window, which is fiddly and macOS-version
# sensitive to hand-roll.
#
#   brew install create-dmg
#
# Notarisation needs a keychain profile:
#   xcrun notarytool store-credentials "notary" --apple-id <email> \
#     --team-id <team> --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/GroundControl.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Packaging/Info.plist)"
DMG="build/GroundControl-${VERSION}.dmg"
PROFILE="${NOTARY_PROFILE:-notary}"
SRC="build/dmg-src"

if ! command -v create-dmg >/dev/null; then
  echo "!! create-dmg is not installed. Run: brew install create-dmg"
  exit 1
fi

bash Scripts/build-app.sh

# A dmg that is not signed with Developer ID can never be notarised, and a
# cheerful "done" at the end would be a lie.
# Captured first, not piped: `grep -q` exits on its first match, codesign then
# dies of SIGPIPE, and pipefail reports the whole pipeline as failed even
# though the match succeeded.
SIGNATURE="$(codesign -d --verbose=2 "$APP" 2>&1 || true)"
if ! printf '%s' "$SIGNATURE" | grep -q "Authority=Developer ID Application"; then
  echo "!! The app is not signed with Developer ID — the dmg cannot be notarised."
  echo "   Create the certificate, then re-run."
  exit 1
fi
IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" \
  | head -1 | sed 's/.*"\(.*\)"/\1/' || true)"

# create-dmg copies the whole source folder in, so stage the app alone and let
# it add the Applications drop-link itself.
echo "==> Staging"
rm -rf "$SRC" "$DMG"
mkdir -p "$SRC"
cp -R "$APP" "$SRC/"

# The window is 864x576 points. The art is 1728x1152 (2x); wrapping it in a
# HiDPI TIFF — a 1x rep at the point size plus the 2x rep — is what tells
# Finder "this is 864 points, sharp on Retina". A bare 2x PNG makes Finder lay
# the window out at 2x the size, which is what put the icons up in the corner.
BG="build/dmg-background.tiff"
sips -z 576 864 "Packaging/dmg-background@2x.png" --out "build/dmg-bg-1x.png" >/dev/null
tiffutil -cathidpicheck "build/dmg-bg-1x.png" "Packaging/dmg-background@2x.png" -out "$BG" >/dev/null
rm -f "build/dmg-bg-1x.png"

# The icon coordinates land on the two landing pads painted into the background.
echo "==> Creating $DMG"
create-dmg \
  --volname "Ground Control" \
  --volicon "Packaging/AppIcon.icns" \
  --background "$BG" \
  --window-pos 200 120 \
  --window-size 864 576 \
  --icon-size 128 \
  --text-size 12 \
  --icon "GroundControl.app" 210 274 \
  --app-drop-link 650 274 \
  --hide-extension "GroundControl.app" \
  --hdiutil-retries 5 \
  --codesign "$IDENTITY" \
  "$DMG" "$SRC"
# create-dmg occasionally leaves its intermediate read-write image behind.
rm -rf "$SRC" "$BG" build/rw.*.GroundControl-*.dmg

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "==> Skipping notarisation (SKIP_NOTARIZE=1)"
  echo "    Users will need to right-click -> Open."
  echo "==> Done: $DMG"
  exit 0
fi

echo "==> Notarising — Apple usually answers in 2-15 minutes"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

# Stapling attaches the ticket to the file, so Gatekeeper can verify it
# offline. Without it a first launch with no network still warns.
echo "==> Stapling the ticket"
xcrun stapler staple "$DMG"

echo "==> Verifying as Gatekeeper will see it"
spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | sed 's/^/    /'

echo
echo "==> Done: $DMG  ($(du -h "$DMG" | cut -f1))"
echo "    Double-clicks cleanly on any Mac — no right-click, no warning."
