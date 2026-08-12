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
    ## Background image (optional)

    The panel resizes, so a background is **nine-sliced**: corners hold their
    size, edges stretch or tile, the centre fills.

    - Detail and ornament → **corners only**
    - Long edges → plain, **seamlessly repeating** texture
    - Centre → flat or a tiling texture, dark enough for text
    - No single large object anywhere but a corner

    Tell me:
    - `capInsets` — px from each edge where the corner artwork ends
    - `contentInset` — px from the edge where the calm centre begins
    """

    static let shapeSection = """
    ## Breaking the rectangle (optional)

    The image's alpha can become the window itself: transparent pixels are
    see-through and click-through, so art can extend past the panel edge —
    antennae, masts, a mascot leaning out, a torn border.

    - Canvas **larger than the panel body**; surplus is where art escapes
    - Body **opaque** — rows are drawn on it
    - **Centre must never be keyed out**; a hole there erases the rows
    - Protruding parts fully opaque, surrounded by pure background colour

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
    | `window.capInsets` | `{ top, left, bottom, right }` in px — only when `lockAspect` is false |
    | `layout.contentInset` | px holding rows inside your border |
    | `matrix.messages` | array of phrases, 13 chars max, A–Z 0–9 `. - !` only |

    ## Colours

    | Key | Paints |
    |---|---|
    | `windowBackground` | the panel |
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
