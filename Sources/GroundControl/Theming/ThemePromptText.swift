// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The fixed prose of the theme prompt.
///
/// Deliberately terse. A model needs constraints, not explanation, and every
/// paragraph of background is a paragraph competing with the rules that
/// actually decide whether the result works.
///
/// Note the JSON examples carry no comments: JSON forbids them, and a model
/// shown commented JSON will emit commented JSON. The keys are described in
/// tables instead.
enum ThemePromptText {
    static let preamble = """
    Design a theme for **Ground Control**, a small macOS menu-bar panel listing
    my running AI agent sessions. Dark, compact, always on screen.

    A theme is one folder: a `theme.json` manifest plus the images it names.
    Every key is optional — anything omitted falls back to a built-in default.

    **Rules for the JSON you give me:**
    - No comments. No trailing commas. It must parse as strict JSON.
    - Only include keys you are actually setting.
    """

    static let backgroundSection = """
    ## Panel artwork (optional)

    **One key does this: `window`. Put the file in `window.image`.** There is no
    other place for panel art — do not invent one, and do not put it under
    `assets`.

    The simplest version is also the best one, and is all most themes need:

    ```json
    "window": { "image": "panel.png", "removeBackground": "#00FF00" }
    ```

    That keeps the artwork's proportions, scales it as one piece, and scrolls
    the rows inside it. Everything below is only for `lockAspect: false`, where
    the panel grows with my sessions and the art must be **nine-sliced**:
    corners hold their size, edges stretch or tile, the centre fills.

    - Detail and ornament → **corners only**
    - Long edges → plain, **seamlessly repeating** texture
    - Centre → flat or a tiling texture, dark enough for text
    - No single large object anywhere but a corner

    ### How the frame behaves when I resize the panel

    | `lockAspect` | `mode` | `capInsets` | Result |
    |---|---|---|---|
    | `true` (default) | ignored | ignored | whole image scales as one piece |
    | `false` | `tile` | none | image repeats as a texture |
    | `false` | `tile` / `stretch` | set | **nine-grid**: corners hold, edges and centre repeat or stretch |
    | `false` | `center` | ignored | drawn once at natural size, centred |

    **For a picture frame, use the nine-grid row**: `"lockAspect": false`,
    `"mode": "stretch"`, and `capInsets` set to where your corner ornaments end.
    With `lockAspect` left at its default your caps are ignored entirely and the
    frame just shrinks.

    ### Insets are measured in your artwork's own pixels

    `layout.contentInset` is where your painted frame ends and the calm centre
    begins — read it straight off your image. A 900px picture with a frame
    180px thick is `180`.

    - With `lockAspect: true` (the default, and what you want) the art is scaled
      to the panel and the inset scales with it. Any resolution works
    - With `lockAspect: false` the corners are drawn at their natural size, so
      **draw the whole thing about 400–500px wide** or the frame will swamp the
      panel. `window.capInsets` is likewise in artwork pixels
    - If your opening is rounded, give `layout.contentCornerRadius` its radius
      in the same pixels — otherwise a round frame encloses a square screen
    """

    static let shapeSection = """
    ## Breaking the rectangle (optional)

    The image's alpha can become the window itself: transparent pixels are
    see-through and click-through, so art can extend past the panel edge —
    antennae, masts, a mascot leaning out, a torn border.

    - Canvas **larger than the panel body**; surplus is where art escapes
    - Body **opaque** — rows are drawn on it
    - **Centre must never be keyed out**; a hole there erases the rows
      (unless you use `overlay` below, where the opposite is true)
    - Protruding parts fully opaque, surrounded by pure background colour

    ### `overlay` — the frame in front (recommended for picture frames)

    ```json
    "window": { "image": "frame.png", "overlay": true, "removeBackground": "#00FF00" }
    ```

    Normally the skin is painted behind the rows, so its opening and the rows
    have to be fitted to each other by hand. With `overlay` it is painted **in
    front**, and the frame simply covers whatever it overlaps — no fitting, and
    the artwork alone decides where the content appears to stop. Bevels, glows
    and vignettes over the content all become possible.

    `layout.contentInset` takes one number or four:

    ```json
    "layout": { "contentInset": { "top": 140, "left": 152, "bottom": 80, "right": 152 } }
    ```

    The ✕ and ↔ marks always draw on top of your artwork, so they cannot be
    lost — but they sit at the ends of the title strip, so `top`, `left` and
    `right` still decide whether they land on the frame or inside the opening.
    Anywhere you want the frame to visibly overlap the rows, go
    **under** it: the rows tuck behind and the artwork trims their edges. A
    frame is rarely as thick at the top as at the sides, which is why one
    number for all four rarely fits.

    One requirement, and it reverses the rule above: **the middle must be the
    exact same colour as the outside** — one flat `#00FF00` everywhere that is
    not frame, inside and out. Only the frame itself is painted. A near miss is
    a miss: a slightly different green does not key out, and a solid middle
    drawn on top hides the whole panel.

    **Transparency — do not attempt real alpha.** Fill everything outside the
    artwork with one flat colour, `#00FF00` or `#FF00FF`. I key it out on load.

    - Keep the art **well clear of that colour**, not merely different from it:
      anything close is removed too. Against `#00FF00`, a bright green light
      like `#39ff14` is erased — pick `#FF00FF` if the art needs green
    - I clean up the rim the key leaves, so a soft or glowing edge is fine

    The app draws its own ✕ and ↔ marks at the ends of the title strip, so a
    skin does not need to supply them — just leave `layout.contentInset` wide
    enough that the strip sits inside the frame rather than under it.
    """

    static let paletteReference = """
    ## Keys

    | Key | Value |
    |---|---|
    | `colors.*` | `#rrggbb` or `#rrggbbaa` |
    | `avatar.states.{idle,working,needsInput,done}` | `{ "image": "file.png" }` |
    | `avatar.size` / `position` / `cornerRadius` | number, `left` or `right`, number |
    | `window.image` | filename of the skin |
    | `window.lockAspect` | `true` keeps proportions and rows scroll; `false` grows with sessions and the art slices |
    | `window.removeBackground` | `"auto"`, `"checkerboard"`, or a hex colour to key out |
    | `window.capInsets` | `{ top, left, bottom, right }` — only when `lockAspect` is false |
    | `layout.contentInset` | holds rows inside your border — panel points, 8–48 |
    | `matrix.messages` | array of phrases, 13 chars max, A–Z 0–9 `. - !` only |

    ## Colours

    | Key | Paints |
    |---|---|
    | `windowBackground` | the panel's base colour, painted under any artwork |
    | `titleBarBackground` / `titleBarText` | title strip |
    | `rowBackground` / `rowBackgroundAlt` | alternating rows — **give these alpha** so a background shows through |
    | `rowBackgroundHover` | row under the pointer |
    | `sessionName` / `message` / `messageDim` | row text |
    | `needsAction` | **the alarm** — must jump out |
    | `working` / `idle` / `accent` | state accents |
    | `divider` | hairlines |
    | `matrix.{low,high,alarm,unlit,text,peak}` | the title-bar analyser |

    Contrast matters more than prettiness: `needsAction` has to be visible
    across a room, and `messageDim` still has to be readable.
    """
}
