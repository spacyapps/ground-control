#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Packages one theme folder as a zip anybody can install by hand.
#
#   ./Scripts/package-theme.sh ~/path/to/themes/myTheme
#   ./Scripts/package-theme.sh <folder> <output-dir>
#
# Without an output directory the zip lands on the Desktop, which is right for
# packaging one theme by hand. Anything batching them wants its own folder.
#
# Deliberately plain. A `.gcTheme` bundle with a document type, a UTI and an
# in-app installer would be nicer to double-click and worse in every other way:
# more to sign, more to explain, and a format nobody can open with anything else.
# A zip of a folder is understood by every Mac ever made, and the app already
# offers "Theme > Open Themes Folder…", which turns installing into a drag.
#
# The theme keeps its own licence. Code here is GPL; artwork is not a derivative
# of it, and shipping the two separately is what makes that distinction real.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-}"
OUT_DIR="${2:-$HOME/Desktop}"
if [ -z "$SRC" ] || [ ! -f "$SRC/theme.json" ]; then
  echo "usage: package-theme.sh <folder containing theme.json> [output-dir]" >&2
  exit 2
fi

# A `private/` folder marks themes that are personal and never distributed —
# one machine, not for sale, not for sharing. Packaging one is always a
# mistake, so refuse rather than produce a zip nobody should send.
case "/$SRC/" in
  */private/*)
    echo "refusing: $SRC is under a private/ folder — those themes are not for distribution" >&2
    exit 2
    ;;
esac

NAME="$(basename "$SRC")"
# The archive's own root, so unzipping produces "<name>-theme/" rather than
# whatever the staging directory happened to be called.
ROOT="build/theme-stage/${NAME}-theme"
STAGE="$ROOT/$NAME"
mkdir -p "$OUT_DIR"
DEST="$OUT_DIR/${NAME}-theme.zip"

rm -rf "build/theme-stage" "$DEST"
mkdir -p "$STAGE"
cp -R "$SRC"/. "$STAGE/"

# The Finder leaves .DS_Store in any folder it has looked at, and four of the
# five themes were carrying one. It records icon positions and window sizes for
# a folder on this Mac; it means nothing to a buyer and looks like debris in
# something they paid for.
find "$STAGE" -name '.DS_Store' -delete

# Travels with the artwork, because a folder of PNGs tells you nothing about
# where it belongs.
cat > "$ROOT/INSTALL.txt" <<TXT
${NAME} — a theme for Ground Control
$(printf '%.0s-' $(seq 1 $((${#NAME} + 28))))

1. Open Ground Control's menu-bar icon and choose
   Theme > Open Themes Folder…

2. Drag the "${NAME}" folder from this zip into that window.

3. Back in the menu, choose Theme > ${NAME}.

That is the whole installation. Themes are plain folders — a theme.json and
some images — so you can open them, edit them, and copy them. Saving a change
re-skins the panel immediately.

To remove it, delete the folder again.
TXT

# Strip extended attributes before archiving. Without this the zip carries a
# __MACOSX shadow of every file — harmless, but it is the first thing someone
# sees when they open it, and a theme should look like a folder of pictures.
xattr -cr "$ROOT" 2>/dev/null || true

# --norsrc --noextattr, and no --sequesterRsrc.
#
# The comment that used to be here was half right and the zips proved it:
# leaving out --sequesterRsrc does avoid a __MACOSX/ folder, but ditto then
# writes the same metadata as ._INSTALL.txt, ._theme.json, ._preview.png
# sitting beside every real file — worse, if anything, because it is scattered
# rather than in one folder a person can ignore. Telling ditto not to carry
# resource forks or extended attributes at all is what actually produces a
# clean archive. These are plain images and JSON; there is nothing to preserve.
( cd build/theme-stage && ditto --norsrc --noextattr -c -k --keepParent "${NAME}-theme" "$DEST" )
rm -rf "build/theme-stage"

echo "==> $DEST  ($(du -h "$DEST" | cut -f1))"
echo "    Unzip, drag the folder into Theme > Open Themes Folder…"
