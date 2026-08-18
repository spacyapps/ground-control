# Theme delivery

> **Moved 2026-08-18.** Extra themes left the repository altogether and now
> live at `~/Documents/Projects/GroundControlThemes`, keeping their own git
> history. Artwork is licensed separately from the code, and a public repo
> carrying only an AGPL `LICENSE` reads as licensing everything inside it —
> so the artwork is not inside it. `Scripts/build-app.sh` reads
> `EXTRA_THEMES_DIR`, which defaults to that folder.
>
> **Settled 2026-08-15.** `spacyAppsUnicornOverlord`
> lives there and is bundled only when `EXTRA_THEMES=1`, which the alpha zip and
> the dmg both set. The release app went from 9.6 MB to **6.0 MB**.
>
> The proposal below — `.gcTheme` packaging, release-asset downloads, an in-app
> gallery — is **not being built**. It was written when the unicorn theme was
> 5.5 MB of an 11 MB app and the split looked structural. It is not: 2.6 MB of
> that theme is a single avatar GIF, and a theme's weight is its maker's problem
> once themes are distributed separately. Moving one folder and adding one
> environment variable got the whole benefit.
>
> Kept for the reasoning, not as a plan.

---

# Delivering themes separately — a proposal

**Status: proposal, nothing built.** Written 2026-08-12 during alpha.

## Why

Themes ship inside the app today (`ThemeSeeder` copies them to
`~/Library/Application Support/GroundControl/Themes/` on first launch and never
overwrites). That was the right first move — a downloaded app with an empty
theme picker is a bad first impression — but one theme now dominates the
download:

| | size |
|---|---|
| `default` | 4 KB |
| `example-avatars` | 104 KB |
| `spacyAppsLunarAvatar` | 1.4 MB |
| **`spacyAppsUnicornOverlord`** | **5.5 MB** |
| app | 11 MB |
| dmg | 9.3 MB |

Two large GIFs in one demo theme are over half the app. Ship only `default`,
`example-avatars` and the lunar station and the app is ~5.5 MB, the dmg ~3.5 MB.

The constraint that matters for alpha: **the fun ones are what make testing
enjoyable**, so moving them out must not make them awkward to get. A theme
nobody installs is worse than a large download.

## What a theme actually is

A folder: `theme.json` plus images. Nothing executable, so **no signing and no
notarisation** — that applies to the app, not to art. A theme is data, and can
be distributed like any other file.

Installing one means putting that folder in
`~/Library/Application Support/GroundControl/Themes/`. The app already watches
that folder, hot-reloads on change, and offers **Theme → Open Themes Folder…**.

So the machinery exists. The question is only what a person downloads and what
they do with it.

## Options

| | What the user does | Build cost | Feels like |
|---|---|---|---|
| **A. Plain zip** | download, unzip, drag folder into the themes folder | none — zip the folder | fiddly, three steps, easy to drop in the wrong place |
| **B. `.gcTheme` file** | double-click | small: register a document type, handle the open, copy it in | an installer, one step |
| **C. In-app gallery** | Settings → browse → Install | large: hosting, manifest, downloads, progress, failure states | an app store |
| **D. Git clone** | `git clone` into the themes folder | none | developer-only |

## Recommendation

**A now, B soon, C probably never.**

**For alpha — option A, today.** Publish each theme as a zip on the GitHub
release beside the dmg. `INSTALL.txt` and the README gain three lines:

```
Extra themes: download, unzip, and drop the folder into
Ground Control → menu bar → Theme → Open Themes Folder…
Then pick it in Settings.
```

That is genuinely enough for alpha testers, needs no code, and can be done in
the same pass as the next dmg. Keep the lunar station bundled so a fresh install
still demonstrates skins, overlay drawing and keying with no download at all.

**Then option B**, when there is a reason to touch packaging again. A
`.gcTheme` is just a renamed zip; the work is declaring the document type in
`Info.plist`, handling `application(_:open:)`, unzipping to the themes folder,
and refusing anything without a `theme.json` at its root. Roughly an afternoon,
and it turns "download, unzip, find a hidden folder, drag" into "double-click".
It is also the point at which a theme becomes shareable — one file to send a
coworker.

**Option C is a shop, not a feature.** It needs hosting, a manifest format,
update semantics, and failure handling for every network state, and it earns its
keep only when other people are publishing themes. Not before.

## What stays in the app

- `default` — the reference palette, and the fallback for every key
- `example-avatars` — the avatar system, 104 KB
- `spacyAppsLunarAvatar` — a full worked skin: shaped window, overlay drawing,
  chroma keying, matrix messages, art past the panel edge

That is 1.5 MB and covers every feature a theme author needs to see. The unicorn
frame demonstrates nothing the station does not; it is simply more fun, which is
exactly what a download is for.

## Open questions

- **Where do the zips live?** GitHub releases is free and needs no
  infrastructure. Anything else means hosting.
- **Versioning.** A theme has no version today. If a theme is redownloaded, the
  seeder's never-overwrite rule does not apply — the user is choosing to
  replace. Option B has to decide whether to ask before overwriting, and it
  should.
- **Naming.** `spacyAppsUnicornOverlord` is a folder name doing double duty as a
  product name. A separately downloaded theme wants a display name (`name` in
  the manifest already exists), and the folder should probably be short.
- **A theme's own preview.** A person choosing a download would want to see it
  first. A `preview.png` beside `theme.json` costs nothing and would serve both a
  release page and, later, any gallery.
