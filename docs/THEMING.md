# Making a Ground Control Theme

A theme is a **folder** containing one `theme.json` manifest plus any images or
videos it references. That's it.

## Two choices before you draw anything

**Create a Theme…** in Settings asks these first, because neither can be
recovered afterwards:

**Frame.** *Simple* draws one picture scaled to the panel — any artwork works,
nothing to measure. *Nine-grid* holds the corners and repeats the edges, so the
panel can be dragged to any shape. Nine-grid asks more of the art (ornaments in
the corners, edges that tile) and is what the good themes will be, because it is
the only kind that survives a resize intact.

**Transparent colour.** Whatever is filled around — and behind — the artwork,
which the app keys out on load. It must be a colour the art never uses: a green
frame keyed on green erases itself. Green, magenta and blue are offered; pick
the one furthest from your palette.

Both go into the generated prompt as instructions rather than suggestions, and
the starter `theme.json` is written to match.

## Quick start

Four themes ship with the app and are copied into your themes folder the first
time it runs, so they are in the picker straight away — and editable, because
they are now yours. An existing folder is never overwritten, so anything you
change stays changed.

| Theme | Shows |
|---|---|
| `default/` | every colour key, no artwork |
| `example-avatars/` | the avatar system — three stills and an animated GIF |
| `spacyAppsLunarAvatar/` | a shaped window: avatars, chroma keying, matrix messages, art past the panel edge |
| `spacyAppsUnicornOverlord/` | a frame drawn *in front* of the rows — `window.overlay`, four-sided insets, an animated loop |

Copy whichever is closest to what you want.

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

### Showing a background through the rows

Row colours accept alpha, and that is how a background image is meant to be
seen: rows span the full width, so an opaque `rowBackground` hides the artwork
completely.

```json
"rowBackground":      "#120c1cbb",   // ~73% — stars show through
"rowBackgroundAlt":   "#160f22bb",
"titleBarBackground": "#160f22cc"
```

`99` ≈ 60%, `bb` ≈ 73%, `dd` ≈ 87%, `ff` = solid.

A **framed** background — a bezel or border, with detail round the edge — also
needs `layout.contentInset`, or the rows sit exactly on top of the frame:

```json
"layout": { "contentInset": 14, "contentCornerRadius": 10 }
```

That holds every row and the title bar away from the panel edge. Match it
roughly to how thick the border is in your artwork.

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

### `window` — breaking the rectangle

Three keys. The image's alpha becomes the window itself, so transparent areas
are see-through **and** click-through, and art can escape what would have been
the edge.

```json
"window": {
  "image": "panel.png",
  "lockAspect": false,
  "removeBackground": "#00FF00"
}
```

| Key | Does |
|---|---|
| `image` | the skin — drop a generated file straight in |
| `overlay` | `true` draws the skin **in front of** the rows instead of behind |
| `lockAspect` | `true`: keeps the artwork's proportions, rows scroll inside. `false`: panel grows with sessions, art is nine-sliced |
| `removeBackground` | `"auto"`, `"checkerboard"`, or a hex colour to key out. Omit if the file already has real alpha |

### `overlay` — the frame in front

Behind the rows, a frame and its contents have to be fitted to each other:
`contentInset` has to match where the opening starts, `contentCornerRadius` has
to match its curve, and any mismatch reads as a screen pasted onto a picture.

```json
"window": { "image": "frame.png", "overlay": true, "removeBackground": "#00FF00" }
```

With `overlay`, the skin is painted after the rows. The frame covers whatever it
overlaps, so the rows can run right past its opening — `contentInset: 0` is
fine — and the artwork decides where they appear to stop. It also allows art
*over* the content: bevels, inner shadows, a vignette, a mascot leaning across a
corner.

The catch reverses the usual rule: **the artwork's centre must be the exact same
colour as the outside** — one flat key colour everywhere that is not frame, so
both the surround and the opening key out together. A near miss is a miss: a
slightly different green stays solid and the frame hides the panel.

`contentInset` still matters, but only for looks now rather than for fit — and
it takes four numbers when one will not do:

```json
"layout": { "contentInset": { "top": 140, "left": 152, "bottom": 80, "right": 152 } }
```

Wider than the frame is thick on a given side, and the content clears it there.
Narrower, and the rows tuck behind and the artwork trims their edges. A frame is
rarely as thick at the top as at the sides, so one number usually means clearing
the thickest side everywhere. The ✕ and ↔ marks sit at the ends of the title
strip, so the `top`, `left` and `right` values decide whether you can see them.

**The ✕ and ↔ marks are never covered.** They draw above the skin — marks, then
frame, then panel — so tucking the content behind the artwork can hide the rows'
edges but never the only ways to close and resize the window. They still take
their position from `contentInset`, so that is what moves them.

The app checks this rather than trusting it. If an overlay skin's middle is
solid, it is drawn *behind* the rows instead — imperfect, but visible — and
Settings says why. The frame never takes a click, however opaque it is; clicks
fall through to the rows beneath.

**On `removeBackground`.** Image models cannot produce reliable transparency —
they paint the checkerboard an editor *shows*, or drop alpha entirely. But they
will fill a flat colour perfectly, which is what chroma keying is for. Ask for
a pure `#00FF00` or `#FF00FF` background and name it here; `"auto"` reads the
corner and picks between a colour key and a checkerboard flood fill.

Two things follow from how a key works:

- **Keep the artwork well away from the key colour**, not just different from
  it. Anything within about 130 units of RGB distance is treated as background
  and removed — against `#00FF00` that erases a bright green running light like
  `#39ff14`. If the art needs green, key on `#FF00FF` instead.
- **A soft or glowing edge is fine.** The key leaves a rim of its own colour on
  whatever it cuts around, so that rim is suppressed afterwards — but only
  within a few pixels of the cut, which is the only place it can physically be.
  Your artwork's own colours, further in, are left alone.

**Resizing a shaped panel.** A skin replaces the system window frame, so the
panel carries its own handle: a ↔ mark at the right end of the title strip,
mirroring the ✕ at its left end. It sits inside `contentInset`, on your artwork rather than out
on the invisible window edge, and takes its colour from `titleBarText` like the
close mark does. Drag it to set the width. Height is never dragged: it follows
the rows, or the artwork when `lockAspect` is true.

**You can keep the artwork's shape or fit the content, never both.** Locked, the
panel is scaled as one piece and the list scrolls. Unlocked, it grows with your
sessions and the art must slice to follow.

### What each combination actually does

Two keys decide how the artwork behaves; a third decides the panel. They are
easy to set in combinations that quietly cancel each other out, so here is the
whole matrix.

| `lockAspect` | `mode` | `capInsets` | What happens as the panel resizes |
|---|---|---|---|
| `true` *(default)* | **ignored** | **ignored** | The whole image is **scaled** to the panel as one piece. Everything shrinks together. |
| `false` | `tile` *(default)* | `0` | The image **repeats** as a texture. Nothing scales. |
| `false` | `tile` | set | **Nine-grid.** Corners hold their size; edges and centre *repeat*. |
| `false` | `stretch` | set | **Nine-grid.** Corners hold their size; edges and centre *stretch*. |
| `false` | `center` | ignored | Drawn once at natural size, centred. The panel grows around it. |
| `false` | `aspectFill` | ignored | Scaled to cover and cropped. Proportions kept, edges lost. |

**The first row is the one that catches people.** With `lockAspect` left at its
default, `mode` and `capInsets` are discarded — a carefully measured set of caps
does nothing at all, and the frame simply scales.

### The nine grid

```
┌────────┬──────────────┬────────┐
│ corner │  top edge    │ corner │    corners     never change size
│  FIXED │  ↔ only      │  FIXED │    top/bottom  grow horizontally only
├────────┼──────────────┼────────┤    left/right  grow vertically only
│ left   │              │ right  │    centre      grows both ways
│ ↕ only │  centre ↔↕   │ ↕ only │
├────────┼──────────────┼────────┤    capInsets = how far in from each edge
│ corner │  bottom edge │ corner │    your corner artwork ends
│  FIXED │  ↔ only      │  FIXED │
└────────┴──────────────┴────────┘
```

### Choosing by what your artwork is

| Your image is | Write | Because |
|---|---|---|
| a **picture frame**, detail in the corners | `lockAspect: false`, `mode: "stretch"`, caps at the corner extent | ornaments hold their size; only the plain bands stretch |
| a **seamless texture** | `lockAspect: false`, `mode: "tile"`, no caps | it repeats forever at any size |
| a **designed object** whose proportions matter | `lockAspect: true` with `layout.resize: "aspect"` | scaled as one piece, never distorted |
| a **mascot or vignette** on a plain field | `lockAspect: false`, `mode: "center"` | it keeps its own size while the panel grows |

**Pair the panel's mode deliberately.** `layout.resize: "free"` with
`lockAspect: true` lets you drag the panel to any shape while the artwork is
scaled as one piece — so the picture distorts. `free` wants a nine-grid skin.
The two shipped demos are the clean pairs: `spacyAppsLunarAvatar` is
`free` + nine-grid, `spacyAppsUnicornOverlord` is `aspect` + scaled-whole.

#### When the aspect is unlocked

Nine-slice applies, so two more keys matter:

```json
"mode": "tile",
"capInsets": { "top": 100, "left": 100, "bottom": 100, "right": 100 }
```

- **Corners never scale.** Put every distinctive object — antennae, dishes,
  logos — inside the cap region.
- **Edges stretch or tile.** Keep them plain and repeating, or a feature there
  will smear (`stretch`) or repeat (`tile`).
- `tile` keeps texture at its drawn size, which reads as the pattern sliding
  past as the panel grows. `stretch` suits gradients.

**Insets are measured in the artwork's own pixels** — read them straight off
your image. A 900px picture whose frame is 180px thick uses `180`.

What differs is whether they get scaled, and that follows how the art is drawn:

| `lockAspect` | Art is | So insets are |
|---|---|---|
| `true` (default) | scaled bodily to the panel | scaled with it — any resolution works |
| `false` | nine-sliced, corners at natural size | used as-is, so **draw the art near panel size (400–500px)** |

That is the single most common way a skin goes wrong: a 1408px artwork with
160px caps and `lockAspect: false` puts 160 *points* of corner on each side of a
400pt panel. `contentInset` is additionally capped at a third of the panel, so an
over-large value cannot squeeze the rows out of existence entirely.

`layout.contentInset` holds the rows inside the frame; without it they cover
your border. `Themes/spacyAppsLunarAvatar` is a working example of all of this — a station hull whose antennae extend past the panel edge.

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

### `matrix`
The five-row LED analyser in the title bar. Every key is optional and falls
back to the row palette, so a recolour restyles the meter for free.

```json
"matrix": {
  "low":   "#39ff14",   // bar colour at the floor
  "high":  "#39c5ff",   // bar colour at the ceiling
  "alarm": "#ff2d55",   // replaces the ramp while something needs you
  "unlit": "#26263219", // the dim grid behind the bars — keep it subtle
  "text":  "#e6e6ec",   // letters of a sweeping message
  "peak":  "#e6e6ec",   // the mark that hangs above a falling bar

  "messages": [         // what the display spells — replaces the built-ins
    "SYSTEM ONLINE", "NEURAL LINK", "STANDING BY"
  ]
}
```

`messages` is how a theme gets a voice. Rules, all enforced at load:

- **13 characters maximum** — longer fills the whole grid and reads as a sign
  rather than a word passing through a meter.
- **A–Z, 0–9, space and `. - !` only.** Anything else is dropped, because an
  undrawable character renders as a gap mid-word and looks like a bug in the
  app rather than a typo in your theme.
- Lower case is fine; it renders in capitals either way, since five rows leave
  no room for descenders.

Two things a theme cannot silence: the app's own name, which still appears
every third message, and words harvested from what your sessions actually
said — those come from your work rather than from anyone's idea of what the
panel should say.

### `layout`
- `resize` — how the panel may be resized. Three answers, because a skin and a
  list want opposite things and a person wants neither:

  | value | drag the grip and… |
  |---|---|
  | `content` (default) | width is yours, height follows the rows |
  | `aspect` | width is yours, height follows the artwork's proportions |
  | `free` | both are yours; the rows scroll and the panel stays put |

  `window.lockAspect` is the older spelling and still works — `true` means
  `aspect`, `false` means `content`. Where a theme sets both, `resize` wins.

  **`free` wants nine-sliced artwork.** A skin scaled as one piece will stretch
  out of shape when you drag both directions, so pair `"resize": "free"` with
  `"lockAspect": false` and `capInsets` — corners then hold their size while the
  edges tile. `spacyAppsLunarAvatar` is set up this way;
  `spacyAppsUnicornOverlord` is the opposite, holding its proportions.

  **And nine-slice art must be drawn near panel size.** Caps are points, drawn
  1:1, so a 900px file with 150px caps puts 300pt of corner on a 487pt panel —
  62% of the window is corner, and the skin looks enormous. The station art was
  halved to 450px with 75pt caps for exactly this reason. `aspect` mode hides
  the problem, because there the whole image is scaled; switching such a theme
  to `free` is when it appears.
- `contentInset` — holds the rows inside your frame, in artwork pixels. One
  number for all four sides, or `{ "top": …, "left": …, "bottom": …, "right": … }`
  for the common case where a frame is not equally thick all round.
- `contentCornerRadius` — rounds the block the rows sit in, so a frame with a
  rounded opening does not enclose a square-cornered screen. Same artwork
  pixels, scaled the same way.
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
