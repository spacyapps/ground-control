# Making a Ground Control Theme

A theme is a **folder** containing one `theme.json` manifest plus any images or
videos it references. That's it.

## The one choice before you draw anything

**Create a Theme…** in Settings asks this first, because it cannot be recovered
afterwards:

**Transparent colour.** Whatever is filled around — and behind — the artwork,
which the app keys out on load. It must be a colour the art never uses: a green
frame keyed on green erases itself. Green, magenta and blue are offered; pick
the one furthest from your palette.

It goes into the generated prompt as an instruction rather than a suggestion,
and the starter `theme.json` is written to match. Everything else in that form
is a sketch — the model reads it back and asks you to confirm rather than
treating it as a specification.

## What the prompt actually does

It is two pastes, and both of them ask before they draw. That is the whole
design: an image model given a description produces something plausible and
unasked-for, and the expensive part is not drawing it but discovering, four
images later, that nobody chose it.

**Part one — the four moods.** Four questions first: a reference picture, the
character, what each state *does*, how it is rendered. Then four stills, shown
at the size they will really be seen. Then your notes.

**Part two — the frame.** Four questions: what the frame is made of, its
colours, what sits in each of the four corners, what texture runs along the
edges. The corner-and-edge split is the nine-grid restated as something
answerable — corners are the only place a distinct object survives, and
anything on an edge repeats. Then one still, then two gates:

1. **Confirm the still.** Corners bleeding sideways into an edge, edges that
   will tile, the opening clear, the silhouette irregular.
2. **Choose what moves** — per corner and per edge, or nothing — then how to
   make it, then whether the cost is worth it.

**Animation is offered two ways, not prescribed.** Drawing each frame can
jitter, because every frame is an independent generation and the subject drifts
between them. A video model holds it still and costs tokens. Both sets of rules
are in the prompt; the choice is yours, and "keep the still" is named as a
finished theme rather than a failure to try.

**Expect two or three rounds.** The prompt says so in both parts. The questions
remove the rounds that were nobody's decision; the ones that remain are taste,
and those are the interesting part.

## Quick start

Four themes ship with the app and are copied into your themes folder the first
time it runs, so they are in the picker straight away — and editable, because
they are now yours. An existing folder is never overwritten, so anything you
change stays changed.

| Theme | Shows |
|---|---|
| `default/` | **the reference** — every key that exists, annotated, at its built-in value. Not selectable; it is documentation. |
| `example-avatars/` | the avatar system — three stills and an animated GIF |
| `spacyAppsLunarAvatar/` | a shaped window: nine-grid frame, an animated skin, chroma keying, art past the panel edge |

**The generated prompt only teaches the nine-grid.** Part two opens by asking
four questions — the motif, the colours, what sits in each of the four corners,
what texture runs along the edges — and tells the model to wait for answers
before drawing. Overlay, an irregular silhouette and the keyed centre are stated
as defaults rather than asked about; every one of them is a line in the manifest
that can be changed afterwards. A scaled-whole frame still *loads* — the keys in
this document are unchanged — it is simply no longer the thing we teach, because
being the easy default meant most themes learnt nothing that survives a resize.
| `spacyAppsUnicornOverlord/` | a frame drawn *in front* of the rows — `window.overlay`, four-sided insets, an animated loop |

Copy whichever is closest to what you want.

The unicorn theme lives outside this repository, at
`~/Documents/Projects/GroundControlThemes`, and ships only in alpha builds — it is
3.6 MB, most of it one avatar, and a release should not make everyone download a
theme they may never pick. It is still checked by the test suite, and still the
worked example of `window.overlay`.

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

**Seeing faint vertical or horizontal dashes inside the opening?** That is
`tile` — AppKit does not always land the tiled centre flush against the caps,
and on a keyed frame the soft edge left by `removeBackground` makes the seam
show. Switch that frame to `"mode": "stretch"`. It costs nothing on a frame
whose edges are texture rather than a pattern, and it has no seam to leak.

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
| `bodyFade` | overlay only: the solid body goes to the analyser then fades out across the first row, so the rows below float on the frame with just their own background |
| `lockAspect` | `true`: keeps the artwork's proportions, rows scroll inside. `false`: panel grows with sessions, art is nine-sliced |
| `removeBackground` | `"auto"`, `"checkerboard"`, or a hex colour to key out. Omit if the file already has real alpha |

**A still or an animated `.gif`/`.apng` — no video.** The frame is nine-sliced:
cut into corners, edges and a tiled middle, and redrawn as bitmaps every
frame. A video layer has no nine-slice concept to be cut along, so it isn't
offered here — `.mov`/`.mp4` work for avatar states and corner decorations,
which draw at a fixed size with nothing to slice, but not for the frame.

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

**`bodyFade` — let the rows float on the frame.** Behind the rows an overlay
skin still gets a solid panel colour, sized to the list. `"bodyFade": true`
keeps that ground solid only under the analyser strip, then ramps it to
nothing across the height of the first row. From the second row down the rows
keep only their own `rowBackground`, so a translucent row colour lets the
frame's own artwork — or whatever its keyed centre shows through to — read
behind the list. Give `rowBackground` and `rowBackgroundAlt` some alpha for the
effect to be worth anything.

**On `removeBackground`.** Image models cannot produce reliable transparency —
they paint the checkerboard an editor *shows*, or drop alpha entirely. But they
will fill a flat colour perfectly, which is what chroma keying is for. Ask for
a pure `#00FF00` or `#FF00FF` background and name it here; `"auto"` reads the
corner and picks between a colour key and a checkerboard flood fill.

Two things follow from how a key works:

- **Keep the artwork well away from the key colour**, not just different from
  it. Anything within about 130 units of RGB distance is treated as background
  and removed — against `#00FF00` that erases a bright green running light like
  `#39ff14`. If the art needs green, key on `#FF00FF` instead. **Distance is not
  the whole test:** a pixel whose *key channels* lead the others by more than
  120 is cut whole as a shaded key, however far it is in plain distance — so a
  desaturated pinkish highlight against `#FF00FF` disappears even though it
  looks nothing like magenta. The aquarium frame lost a glint on its palm this
  way and the desktop showed through the hole.
- **Deliver the frame with the key colour still in it — do not pre-key it.**
  Chroma-keying the clip in a video tool *and then* naming `removeBackground`
  keys it twice: the first pass desaturates a near-key pixel just enough to push
  it over the shaded-key line on the second. One pass, done on load, is the
  contract.
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
`spacyAppsLunarAvatar` is the clean pair: `free` + nine-grid, which is the
combination that survives any shape.

`spacyAppsUnicornOverlord` is deliberately the other way — `free` +
scaled-whole. Its border is ornate the whole way round, so nine-slicing would
cut through the corners, and dragging the panel away from the artwork's
proportions stretches the picture. That is an accepted trade for being able to
drag it at all; use `aspect` instead if the proportions matter more.

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

##### Caps are points, so the artwork's size is a design decision

Caps are drawn **1:1 in points**. That makes the pixel size of nine-grid art
something other than a quality setting: it decides how thick the frame appears
on screen and how narrow the panel may get, and the caps must move with it.

Redrawing `spacyAppsLunarAvatar` at 900px while its manifest still said
`capInsets: 75` cut 75px into a corner tower that runs 190px deep. Everything
past the cut belongs to the *tiled* strip, so the tower repeated down both
edges and the frame never closed.

```
450px art, caps 94   ->  corner ends at the cut, girder tiles cleanly
900px art, caps 75   ->  cut lands mid-tower; the rest tiles down the edge
900px art, caps 190  ->  correct, but a 380pt-wide frame on a 487pt panel
```

Two rules follow:

- **Draw nine-grid art at roughly the panel's own size**, 400–500px. Bigger art
  is not sharper, it is heavier.
- **Re-measure the caps whenever the art is redrawn**, at the column where the
  corner ornament ends and the plain edge begins.
  `swift Scripts/fit-frame-art.swift <in> <out> 450` resizes the art — animated
  or still, keeping every frame and its timing — and prints that measurement.

  It measures by how *deep* the artwork hangs in each column: the girder is a
  thin band and any ornament is thicker than it. An earlier version looked for
  where the silhouette's top edge stops moving, and read `10` on artwork whose
  corner towers happen to have flat tops — a cap that would have sliced the
  whole corner into the tiled strip.

##### With `tile`, the cap also decides where the seam falls

`tile` repeats the band between the caps, so that band's **two ends meet at
every repeat**. Where a girder bows even slightly — hand-drawn and generated art
both do — that join shows as a step, and the cap is what decides which two rows
have to match.

The smallest cap that clears the ornament is therefore not automatically the
best one. On the current lunar frame the ornament ends at 119, where the join
steps 6px; going out to 137 brings it to 1px:

```
cap 119  ->  seam 6px      (the smallest cap that clears the ornament)
cap 129  ->  seam 2px
cap 137  ->  seam 1px      (what the script suggests)
```

`fit-frame-art.swift` sweeps this and prints both numbers, so the trade is
visible: a larger cap joins better but raises the panel's minimum size, since
that minimum is `cap × 2`. Where nothing larger helps, it says so.

The panel refuses to shrink below `left + right` and `top + bottom`, so caps
that are too large cost you a minimum size rather than a mangled frame.

##### Ornament depth is a layout decision too

The cap measurement says how far in an ornament reaches *across*. How far it
reaches *down* matters just as much, because the panel's own chrome lives in
the top-left: the ✕, the brand glyph, and the title, in that order from the
edge.

The marks are drawn above the skin and always visible. **The title and glyph
are not** — they sit under an `overlay: true` frame, so a corner ornament
deeper than about 60px in a 450px image will cover them. Keep corner ornaments
shallow, or accept that the strip's left end is decoration.

#### Animated frames

An animated skin has two failure modes a still cannot have, and both are worth
stating to whoever draws it:

- **The silhouette must be locked.** Every frame must have identical outer
  bounds. Frames generated one from the next drift: one station frame varied
  17px in height and 6px in width across 60 frames, and read on screen as the
  panel changing size while it played.
- **The loop must close.** The last frame has to flow into the first. The same
  frame ended 2,300 artwork pixels heavier than it started — it grew steadily,
  then snapped back at the wrap.

Both are measurable before the file is installed: compare each frame's bounding
box and its opaque pixel count. A good one holds all four edges at zero
variation and returns to its starting pixel count exactly.

Animate surface detail only — window lights, indicator lamps, a glint moving
along a hull panel — and keep the frame count low. Twenty-four to thirty frames
at 450px is roughly 700KB; sixty frames at 900px was 5.9MB for the same
animation.

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

**Draw for the size, do not shrink a detailed picture.** Avatars are generated
large and drawn at `size` points — around 60, roughly a favicon. Detail that
cannot be seen there does not politely disappear, it turns to mud: fine
linework, small facial features, texture, gradients spanning a few pixels and
thin outlines all read as dirt at display size. Few shapes and big ones, flat
colour over gradient, no text, and a silhouette still recognisable as a solid
black shape. The check is to shrink the image to `size` pixels and look at it —
if you cannot tell what it is, it is too busy, and more resolution will not save
it. The generated prompt says all of this to the model; it is repeated here for
anyone drawing by hand.

**Animate only what is asking for you.** `working` and `needsInput` are the two
states with something to say, and motion is how they say it. `idle` and `done`
are resting states — animating them means four looping avatars on screen at once
and nothing standing out, which is the opposite of the point.

**And they are only ever seen small.** At 60pt a face is a few dozen pixels and
its expression is unreadable, so the state has to be carried by colour and
shape:

| state | reads as | carried by |
|---|---|---|
| idle | nothing wanted | dim, cool, low contrast — it should recede |
| working | busy, leave it | motion, cool blue or cyan |
| needsInput | **stop and look** | warm alarm colour, highest contrast, a symbol if you can |
| done | finished well | settled green, calm but bright |

Squint at the four at 60pt. If two look alike, the difference is in detail
nobody can see.
- Omit a state → the **built-in drawn face** for that state is used, tinted
  with your palette. You never get a blank row, and overriding one state does
  not oblige you to draw the other three.
- `"size": 0` → no avatars at all. That is the only way to switch them off.

**Supported animation formats:** `.mov` / `.mp4` (H.264 or HEVC) and animated
`.gif` / `.apng`. Avoid `.webm` — not natively supported. Prefer GIF/APNG for
lightweight looping; reserve real video for richer motion.

**Shipped themes update themselves, unless you have edited them.** The app
records what it installed. On a later launch a folder whose contents still match
is replaced with the newer version, so fixes reach you; a folder that differs by
so much as one colour is left alone, permanently, and so is anything installed
by a build from before this was recorded. If you want a theme to be yours,
change anything in it and it stops being ours.

### `cornerDecorations` — fixed art in a panel corner

Up to four independent, optional pieces of art, one per corner —
`topLeft`, `topRight`, `bottomLeft`, `bottomRight`. A mascot, a light, a
prop, sitting above the frame and below the close/resize marks. Nothing to
do with `window` — no slicing, no nine-grid, no silhouette to draw.

```json
"cornerDecorations": {
  "bottomRight": {
    "image": "chest.apng",
    "removeBackground": "#00FF00",
    "scale": 1,
    "offset": { "x": 0, "y": 0 }
  }
}
```

| Key | Does |
|---|---|
| `image` | a still or animated gif/apng, by filename |
| `video` | a `.mov`/`.mp4`/`.m4v` — wins over `image` if both are set |
| `loop` / `muted` | video only, both default `true` |
| `removeBackground` | `"auto"`, `"checkerboard"`, or a hex colour to key out — image/gif only, not video |
| `scale` | multiplies the artwork's own pixel size. 1 is the file's real size |
| `offset` | `{ x, y }`, screen direction from the corner — `x` right, `y` down |

**Always drawn at its own pixel size — never fitted, never automatically
scaled for Retina.** Draw it at the size you actually want it to occupy on
screen, or use `scale` to resize the same file without redrawing it. `scale`
and `offset` are computed together: the anchor point is the *scaled* size's
own corner, so shrinking a decoration brings it in from the panel's edge
rather than just shrinking it in place.

**`offset: {0,0}` puts the artwork's own matching corner exactly on the
window's.** `bottomRight` at `{0,0}` means the art's bottom-right pixel sits
on the panel's bottom-right pixel, growing left and up from there. Offsets
can be large — the art is only ever clipped by the real window edge, never
by anything else, so a decoration can reach well toward the panel's middle
if you want it to.

**No video keying.** `removeBackground` only applies to the image/gif path.
A video corner decoration needs real embedded alpha (ProRes 4444, HEVC with
alpha) or an already-clean background — chroma-keying a video would need a
compositing pass this app does not have.

**Animates only while a session is working**, the same rule as everywhere
else in the panel — a still corner decoration is a complete, finished
choice, not a fallback.

A fuller guide with worked examples will eventually live at
`groundcontrol.app/docs` — not live yet as of this writing.

## Making a light theme

Every shipped theme is dark, so the defaults are dark, and a light theme has to
say so in more places than you would expect. Four keys default to a dark value
that does not follow the rest of the palette:

| Key | Default | Why it matters |
|---|---|---|
| `colors.footerBackground` | `#16161d` | Fills the analyser strip. Leave it and you get a black band across a pale panel. |
| `matrix.text` | near-white | The letters the display spells. Invisible on a light strip. |
| `matrix.peak` | near-white | The mark above a falling bar. Same. |
| `matrix.unlit` | `divider` at 10% | The dim grid. Needs to be a dark tint on light, not a light one. |

The empty-state mark looks after itself: it draws as artwork on a dark panel and
as a tinted silhouette on a light one, decided from `windowBackground`.

A complete light palette that works, if you want somewhere to start:

```json
{
  "colors": {
    "windowBackground": "#f4f2ee",
    "titleBarBackground": "#e8e5df",
    "footerBackground": "#e8e5df",
    "rowBackground": "#ffffff",
    "rowBackgroundAlt": "#faf8f4",
    "rowBackgroundHover": "#eeece6",
    "titleBarText": "#20201c",
    "sessionName": "#20201c",
    "message": "#3a3a34",
    "messageDim": "#6a6a60",
    "divider": "#c9c5bc",
    "needsAction": "#c81e3c",
    "working": "#1d6fa5",
    "idle": "#9a968c",
    "accent": "#2e7d32"
  },
  "matrix": { "text": "#20201c", "peak": "#20201c", "unlit": "#00000014" }
}
```

Note the state colours were darkened too. `#ff2d55` on white is legible but
shrill; the alarm should still be the loudest thing on the panel without being
the only thing you can look at.


### `matrix`
The five-row LED analyser in the title bar. Every key is optional. The bar
colours follow the palette — `low`, `high` and `alarm` fall back to `accent`,
`working` and `needsAction` — but **`text`, `peak` and the strip's own
background do not**: the letters default to a near-white and the strip is filled
with `footerBackground`. On a dark theme that is free. On a light one it is a
black band with invisible writing, so see "Making a light theme" below.

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

#### `matrix.feel` — how it moves

Named levels, not numbers: you know what "slow" looks like, not what `0.012`
does. Every key is independent and optional; an absent `feel` is the shipped
analyser. An unrecognised word is logged and ignored.

```json
"matrix": {
  "feel": {
    "fall":        "slow",     // still | slow | medium | fast
    "jitter":      "calm",     // none | calm | lively | chaotic
    "sensitivity": "steady",   // mellow | steady | eager
    "speed":       "medium"    // slow | medium | fast
  },
  "patterns":    ["wave", "ripple", "pyramid"],
  "patternHold": "medium",     // short | medium | long
  "sleep":       { "face": "-  ‿  -", "zzz": true }
}
```

| Key | Does |
|---|---|
| `fall` | how the bars settle — `still` snaps, `slow` is a long lazy descent, `fast` is snappy. Moves the peak markers with it. |
| `jitter` | per-bar noise. `none` is perfectly clean; `chaotic` is the old spectrum shimmer on every shape. Omit it and each pattern keeps the noise that suits it. |
| `sensitivity` | how loudly work reads. `mellow` needs a busy panel before the bars really move; `eager` makes one working session already look busy. Never changes whether silence is silent. |
| `speed` | how fast a wave travels across the row. |
| `patterns` | which of the eight built-in shapes rotate. Case-insensitive; unknown names dropped; `[]` or absent means all eight. |
| `patternHold` | seconds a shape holds before the next — `short` ≈ 5–9s, `medium` ≈ 9–16s, `long` ≈ 16–28s. |
| `sleep.face` | the little face shown when nothing is running. `sleep.zzz` toggles the trailing `z z z`. |

The eight shapes: `wave` (a travelling sine), `ripple` (rings from the centre),
`chase` (a sweeping bright column), `pyramid` (a breathing triangle), `sawtooth`
(marching ramps), `butterfly` (mirrored wings), `heartbeat` (a flat floor with a
crossing pulse), `spectrum` (jittery noise).

#### `matrix.shape.working` — your own bar formula

A pure-math expression, evaluated for every bar every frame. If it parses it
replaces the pattern rotation entirely; if it doesn't, it's logged and the
rotation carries on, so a typo costs you a look at Console, not a broken panel.

```json
"matrix": { "shape": { "working": "0.5 + 0.5*sin(pos*7 - phase*2)" } }
```

- **Variables** — `pos` (0–1 across the row), `phase` (a monotonically growing
  clock), `energy` (0–1, how busy the panel is), `bar` (this bar's index),
  `count` (total bars).
- **Functions** — `sin cos abs floor sqrt exp`, `min(a,b)` `max(a,b)`,
  `step(t,x)` (0 until `x` reaches `t`, then 1), `pulse(centre,width,x)` (a
  triangular bump), `wrap(x)` (the fractional part).
- **The eight shapes are callable** — `wave(pos)`, `ripple(pos)`, `pyramid(pos)`
  … each at the current phase — so you can lean on one and bend it.
- No assignment, no loops, no `if`. Divide-by-zero and negative roots are 0. The
  result is clamped to 0–1.

**Preview a formula without the app:**

```
swift run matrix-preview "0.5 + 0.5*sin(pos*7 - phase*2)"
swift run matrix-preview "<formula>" --speed slow --jitter none --state done
```

It parses with the real engine and animates in the terminal — edit, re-run,
watch. `--frames N` prints N frames and exits instead of looping.

#### The other three states

`shape.needsInput`, `shape.done` and `shape.idle` take the same formulas. Each
is optional and each falls back to what the panel does today:

| State | With no formula | With a formula |
|---|---|---|
| `needsInput` | flat, lit red floor | strobes at full height for ~15s, then settles to that lit floor until answered. Always wins the meter while something waits. |
| `done` | nothing | blooms once, on top of whatever else is drawn, when a turn finishes — then decays. One at a time, suppressed while an alarm is up. |
| `idle` | flat / the sleep face | a resting texture. Runs at full amplitude, so **keep the values small** — this is not a spectrum. `"0"` is flat, the default. |

The priority is `needsInput` > `working` > `idle`, decided every frame with no
memory. The full model — mixed states, the escalation timer, what a finish under
an alarm does — is in `docs/MATRIX-CUSTOMISATION.md`.

##### `decay()`, in a `done` formula only

`decay(span)` is `1` at the instant a turn finishes and ramps to `0` over `span`
seconds. It is how a `done` bloom fades:

```json
"shape": { "done": "pyramid(pos) * decay(0.6)" }
```

Using `decay()` anywhere but `shape.done` is a parse error.

##### The `swell` — an ocean wave

`wave` is a *sine*: symmetric, repeating. An ocean wave is one swell — a gentle
back, a steep face, a crest that rolls through and resets. Build it:

```
head = wrap(phase * 0.15)              crest position, loops across the row
back = max(0, head - pos) * 0.7        gentle slope behind the crest
face = max(0, pos - head) * 4.0        steep drop ahead of it
      exp(-((back + face)^2) / 0.05)
```

As one formula:

```json
"shape": {
  "working": "exp(-((max(0, wrap(phase*0.15) - pos) * 0.7 + max(0, pos - wrap(phase*0.15)) * 4.0) ^ 2) / 0.05)"
}
```

`back` is zero ahead of the crest and `face` is zero behind it, so adding them
gives one asymmetric hump. Swap `0.7` and `4.0` and the wave breaks the other
way.

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
  edges tile. `spacyAppsLunarAvatar` is set up this way. `spacyAppsUnicornOverlord`
  is `free` with `lockAspect: true`, which stretches the picture — an accepted
  trade for a border that cannot be nine-sliced.

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
