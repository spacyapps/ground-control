#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Builds, packages, notarises and staples a distributable disk image.
#
#   ./Scripts/build-dmg.sh              build, notarise, staple
#   SKIP_NOTARIZE=1 ./Scripts/build-dmg.sh   local dmg, no round trip to Apple
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
STAGE="build/dmg-stage"

bash Scripts/build-app.sh

# A dmg that is not signed with Developer ID can never be notarised, and a
# cheerful "done" at the end would be a lie.
# Captured first, not piped: `grep -q` exits on its first match, codesign then
# dies of SIGPIPE, and pipefail reports the whole pipeline as failed even
# though the match succeeded.
# --verbose=2 because `-dv` alone does not print the Authority chain.
SIGNATURE="$(codesign -d --verbose=2 "$APP" 2>&1 || true)"
if ! printf '%s' "$SIGNATURE" | grep -q "Authority=Developer ID Application"; then
  echo "!! The app is not signed with Developer ID — the dmg cannot be notarised."
  echo "   Create the certificate, then re-run."
  exit 1
fi

echo "==> Staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
# The Applications alias is what makes a drag-to-install window work.
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create -volname "Ground Control" -srcfolder "$STAGE" \
               -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Signing the disk image"
IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" \
  | head -1 | sed 's/.*"\(.*\)"/\1/' || true)"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

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
