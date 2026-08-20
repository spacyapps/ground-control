---
name: ship-a-build
description: >-
  Use when building, notarising, or handing out Ground Control — an alpha zip for
  a tester, a public release, or a dmg. Covers which script to run, what must not
  be bundled, and the specific ways this has gone wrong before.
---

# Shipping a build

Three commands, and a list of traps that have all actually happened.

```bash
EXTRA_THEMES=1 ./Scripts/build-zip.sh   # alpha for a tester — includes paid artwork
./Scripts/build-zip.sh                  # public release — artwork excluded
./Scripts/build-app.sh                  # local only, signed, NOT notarised
```

`build-app.sh` is the one for ordinary development. Notarisation only matters
when the file crosses to another Mac, because Gatekeeper checks the ticket only
on something that arrived with a quarantine flag.

## Before you build

- **Quit the running app.** `build-app.sh` starts with `rm -rf` on the bundle.
  Rebuild underneath a live process and macOS keeps the old copy alive for it:
  you then test yesterday's code while the disk says otherwise. Cost: an hour,
  once.
- **Know which copy you are about to test.** `build/GroundControl.app`,
  `~/Desktop/*.app`, and `/Applications/GroundControl.app` can all exist at
  different ages. Two running at once means two menu-bar icons writing the same
  preferences.
- **Bump `CFBundleShortVersionString`** in `Packaging/Info.plist` for a release.
  The zip is named from it, so forgetting means overwriting the last one.

## The paid artwork rule

Themes live **outside this repository**, at
`~/Documents/Projects/GroundControlThemes`, and `EXTRA_THEMES_DIR` points there.
They are licensed separately and some are meant to be sold.

- **`EXTRA_THEMES=1` is for alpha testers only.** Never for a public release,
  never for a release asset, never for anything on the website.
- A public release ships `Themes/` alone. Extra themes go out through
  `Scripts/package-theme.sh <folder>`, as a zip you control.
- If `EXTRA_THEMES=1` is set and the folder is missing, the build now says so
  rather than silently omitting them.

## Traps, in the order they bit

**`SKIP_NOTARIZE=1` used to clobber the notarised zip.** Both wrote to
`~/Desktop/GroundControl-<version>.zip`, so a pipeline test silently replaced a
notarised artefact with one Gatekeeper rejects — same name, same size, no way to
tell by looking. Fixed 2026-08-18: the unnotarised path is now
`...-unnotarized.zip`, so the two cannot collide.

Still true, though: **any build strips the staple from `build/GroundControl.app`**,
because the bundle is deleted and rebuilt. The zip on the Desktop keeps its
ticket; the working copy does not. Verify the zip, not `build/`, when it
matters.

**Verify independently of the script's own log.** The script prints success; ask
the system instead:

```bash
spctl -a -vv build/GroundControl.app        # want: accepted, Notarized Developer ID
xcrun stapler validate build/GroundControl.app
```

**Look inside the bundle, not at the "Included" line.** A glob of
`"$DIR"/*/` copies each theme's *contents* rather than the theme, scattering
files loose into `Themes/`. The build reported success either way; only
`ls Contents/Resources/Themes/` showed it.

**A new build does not update anyone's themes.** `ThemeSeeder` skips any folder
that already exists in Application Support, so a tester who installed once keeps
the old artwork forever. To see changed art yourself, copy the files into
`~/Library/Application Support/GroundControl/Themes/<name>/` — they hot-reload.

**Rebuild before trusting a hook change.** `HookUpdater` replaces the installed
emitter with the one inside the app at launch, so running a stale build quietly
reinstalls an older `cc-notify`.

**`EXTRA_THEMES=1` sweeps the whole folder, including work in progress.** It
was one unicorn when this flag was written; the themes directory now holds
half-finished drafts too, and a plain `EXTRA_THEMES=1` ships them. Stage instead
— copy only the themes meant to travel into a temp folder and point
`EXTRA_THEMES_DIR` at it:

```bash
STAGE=$(mktemp -d)/themes; mkdir -p "$STAGE"
cp -R ~/Documents/Projects/GroundControlThemes/spacyAppsUnicornOverlord "$STAGE/"
EXTRA_THEMES=1 EXTRA_THEMES_DIR="$STAGE" ./Scripts/build-zip.sh
```

**Stapler can fail with Error 73 on `build/` while the notarisation is fine.**
Seen 2026-08-20 on 0.7.0: Apple returned `Accepted`, then

```
Could not remove existing ticket from …/Contents/CodeResources … No such file
or directory
The staple and validate action failed! Error 73.
```

It is stale state in the build directory, not a rejected build — `spctl` already
said `accepted, source=Notarized Developer ID`. The ticket is keyed to the
cdhash, not the path, so stapling a clean copy works and is still the same
notarised binary:

```bash
W=$(mktemp -d); ditto build/GroundControl.app "$W/GroundControl.app"
xcrun stapler staple "$W/GroundControl.app"     # works
rm -rf build/GroundControl.app
ditto "$W/GroundControl.app" build/GroundControl.app
```

Then finish the script's remaining steps by hand: stage with `INSTALL.txt`,
`ditto -c -k --sequesterRsrc --keepParent`, and verify. **Do not re-sign** to
fix this — re-signing changes the cdhash and throws away a notarisation Apple
has already granted.

How to tell the difference in one command: `xcrun stapler validate` on the app
inside the finished zip. A staple that survives the round trip is the only
proof that matters, because an unstapled app fails on a machine that is offline.

**Notarisation needs the keychain profile.** `NOTARY_PROFILE` defaults to
`notary`; if it is missing, create it with `xcrun notarytool store-credentials`.
Apple answers in 2–15 minutes, so run it in the background rather than blocking.

## The test that has never been run

Everything above proves the paperwork. It does not prove the experience, because
a locally produced file has **no quarantine flag** and Gatekeeper therefore never
checks it.

**Mail or AirDrop the zip to yourself and open it from Mail.** That is the only
way to see what a tester sees. Still outstanding as of 2026-08-18.

## After shipping

- Tell testers whether hooks need reinstalling. They usually do not — the
  installer repoints existing registrations — but say which it is.

  **0.7.0 is the first time the answer is yes.** `HookUpdater` replaces the
  installed `cc-notify` on launch, so the emitter half self-heals; the
  registration in `~/.claude/settings.json` is the installer's job alone and is
  deliberately never touched. A release that adds an *event* therefore does not
  reach anyone who only replaces the app. Whenever the installer's event list
  changes, say so explicitly.
- A release goes on GitHub Releases with the notarised zip attached; the theme
  zip is a separate asset. See `docs/PUBLISHING.md`.
