#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Builds, notarises and staples a zip you can hand to another machine.
#
#   ./Scripts/build-zip.sh                    build, notarise, staple, put it on the Desktop
#   SKIP_NOTARIZE=1 ./Scripts/build-zip.sh    local zip, recipient must right-click -> Open
#
# A dmg is the nicer install, but a zip is what actually travels — Slack, AirDrop,
# a USB stick. The difference that matters is the stapling: a zip cannot carry a
# notarisation ticket itself, so the *app* is stapled and then re-zipped. Skip
# that and the recipient gets "cannot be opened because the developer cannot be
# verified" on any Mac that is offline or behind a captive portal.
#
# Notarisation needs the same keychain profile the dmg uses:
#   xcrun notarytool store-credentials "notary" --apple-id <email> \
#     --team-id <team> --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/GroundControl.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Packaging/Info.plist)"
PROFILE="${NOTARY_PROFILE:-notary}"
UPLOAD="build/GroundControl-${VERSION}-upload.zip"
STAGE="build/zip-stage/GroundControl-${VERSION}"
DEST="$HOME/Desktop/GroundControl-${VERSION}.zip"

# Testers get the demo themes: an alpha is judged on what it looks like,
# and the unicorn skin is what exercises overlay and a long animation.
EXTRA_THEMES=1 bash Scripts/build-app.sh

# Notarisation is only possible for Developer ID signing, so say so here rather
# than after a round trip to Apple.
SIGNATURE="$(codesign -d --verbose=2 "$APP" 2>&1 || true)"
if ! printf '%s' "$SIGNATURE" | grep -q "Authority=Developer ID Application"; then
  echo "!! The app is not signed with Developer ID — it cannot be notarised."
  exit 1
fi

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "==> Skipping notarisation (SKIP_NOTARIZE=1)"
else
  echo "==> Zipping for submission"
  # ditto, not `zip`: it preserves symlinks and extended attributes inside the
  # bundle, and a bundle that arrives mangled fails notarisation for reasons
  # that read as a signing problem.
  rm -f "$UPLOAD"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$UPLOAD"

  echo "==> Notarising — Apple usually answers in 2-15 minutes"
  xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait

  # The ticket goes on the app. A zip is a container, not something Gatekeeper
  # can hold a ticket for, which is why the zip is made twice.
  echo "==> Stapling the ticket to the app"
  xcrun stapler staple "$APP"
  rm -f "$UPLOAD"
fi

# The app travels with a note. install-hooks.sh lives inside the bundle, and a
# tester who does not run it sees an empty panel and reasonably concludes the
# app is broken.
echo "==> Zipping for delivery"
rm -rf "$STAGE" "$DEST"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp Packaging/INSTALL.txt "$STAGE/INSTALL.txt"
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$DEST"
rm -rf "$STAGE"

echo "==> Verifying as the other machine will see it"
spctl -a -vvv "$APP" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$APP" 2>&1 | sed 's/^/    /' || true

echo
echo "==> Done: $DEST  ($(du -h "$DEST" | cut -f1))"
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "    Not notarised — the recipient must right-click -> Open the first time."
else
  echo "    Unzip and double-click on any Mac. No right-click, no warning."
fi
