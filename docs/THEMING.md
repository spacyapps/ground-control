# Making a Ground Control Theme

A theme is a **folder** containing one `theme.json` manifest plus any images or
videos it references. That's it.

## Quick start

Two folders ship as starting points: `default/` (every colour key, no
artwork) and `example-avatars/` (the avatar system working — three stills and
one animated GIF). Copy whichever is closer to what you want.

Themes live in `~/Library/Application Support/GroundControl/Themes/`. The
menu-bar menu has **Theme → Open Themes Folder…** if you'd rather not type it.

1. Copy the `default/` folder and rename it (e.g. `themes/neon/`).
2. Open `theme.json`, change what you want.
3. **Delete any key you don't want to change** — the app fills it in with its
   built-in default. An empty `{ }` manifest is a valid theme (you get all
   defaults).
4. Pick your theme in Settings. Saved changes hot-reload instantly.

Files can be named anything — the manifest points at them by path. Paths are
relative to the theme folder.

## Seeing your work

```bash
./Scripts/theme-preview.sh          # one fake row per state
./Scripts/theme-preview.sh clear    # remove them again
```

This is the only reliable way to see all four avatars at once. `needsInput` in
particular is hard to trigger on demand — it depends on an agent actually
blocking on you — so without this you cannot check the face a theme draws for
the state that matters most. The preview rows are prefixed `preview-` and never
touch real sessions.

## The one rule

**Everything is optional.** Every color, image, and video has a code default.
A theme overrides only the pieces it cares about. This is what makes themes
easy: change one image, inherit everything else.

---

## Keys

### Top-level
| Key | Meaning | Fallback |
|-----|---------|----------|
| `manifestVersion` | Schema version (currently `1`) | assumed `1` |
| `name` | Display name in the picker | folder name |
| `author` / `description` | Metadata, shown in Settings | blank |

### `colors`
Hex strings (`#rrggbb` or `#rrggbbaa`). Any omitted color uses the app default.
Key ones:
- `needsAction` — the attention colour (default red). Used for the dot and,
  optionally, row tint.
- `working` / `idle` — state accents.
- `windowBackground`, `rowBackground`, `sessionName`, `message` — the basics.

### `assets`
Optional images that *replace* drawn defaults. Set to a filename, or `null`/omit
to use the built-in. The colour underneath is always painted first, so a
background with transparency composites onto it.

- `needsActionDot` — your own badge instead of the drawn red dot. Just scaled
  to fit; no slicing.
- `windowBackground`, `titleBarBackground`, `footerBackground` — background
  images.

**The panel resizes, so backgrounds are nine-sliced.** One image, four numbers:

```json
"assets": {
  "windowBackground": {
    "image": "panel.png",
    "mode": "tile",
    "capInsets": { "top": 28, "left": 12, "bottom": 12, "right": 12 }
  }
}
```

`capInsets` marks how far in from each side the corner artwork ends. Corners
never scale; the edges grow along one axis; the centre grows along both. So:

- **detail belongs in the corners** — anything in the middle repeats or smears;
- **the centre should be flat or a seamless tile**;
- **each edge must tile along its own axis** (the top edge repeats left to
  right, so its ends have to meet).

Three-slice is just this with `left` and `right` at 0. For a fixed-height strip
like the title bar, set `top` and `bottom` to 0 instead.

`mode` is:

| mode | what it does |
|---|---|
| `tile` (default) | repeats the edges and centre — best for texture |
| `stretch` | smears them — best for gradients |
| `center` | draws at natural size, centred, no scaling |
| `aspectFill` | scales proportionally and crops — for art that must not distort |

A bare `"windowBackground": "panel.png"` means `tile` with no corners held,
which is what a plain repeating texture wants.

Editing an image hot-reloads exactly like editing the manifest.

### `avatar`
The per-state face/mascot. Each state can be an **image** *or* a **video**
(author's choice — set whichever key).
- `states.idle` — shown when the session is quiet.
- `states.working` — shown during activity. Use `video` for animation
  (`"video": "working.mov", "loop": true`).
- `states.needsInput` — shown when the session needs you (pairs with the red dot).
- `states.done` — shown briefly on completion.
- `size`, `position` (`left` | `right`), `cornerRadius` — layout of the avatar.
- Omit a state → the **built-in drawn face** for that state is used, tinted
  with your palette. You never get a blank row, and overriding one state does
  not oblige you to draw the other three.
- `"size": 0` → no avatars at all. That is the only way to switch them off.

**Supported animation formats:** `.mov` / `.mp4` (H.264 or HEVC) and animated
`.gif` / `.apng`. Avoid `.webm` — not natively supported. Prefer GIF/APNG for
lightweight looping; reserve real video for richer motion.

### `layout`
- `rowMaxHeight` — cap per row (default 100px).
- `marqueeOnOverflow` — auto-scroll long messages (default true).
- `marqueeSpeed` — px/sec.
- `density` — `comfortable` (2-line rows) or `compact` (1-line).

### `typography`
- `fontFamily` — `null` = system font. Otherwise an installed font name.
- Size/weight per element.

---

## Examples

**Just a custom avatar, nothing else:**
```json
{
  "name": "My Mascot",
  "avatar": {
    "states": {
      "idle":    { "image": "cat_sleep.png" },
      "working": { "video": "cat_run.mov", "loop": true }
    }
  }
}
```

**Just a recolor:**
```json
{
  "name": "Amber",
  "colors": { "needsAction": "#ffb000", "accent": "#ffb000" }
}
```

Both are complete, valid themes.
