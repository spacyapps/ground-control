// SPDX-License-Identifier: AGPL-3.0-or-later
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
    """

    /// Stated before the first section, because the top of a prompt is where the
    /// working method gets decided. Buried at the bottom it arrives after the
    /// model has already planned to do everything at once.
    static let howWeWork = """
    ## How I want to work

    **In stages, and stop at the end of each one.** The parts below are ordered
    easiest first, and each is finished and checked before the next begins:

    1. **The avatars** — four small square images. Self-contained, and the place
       to settle the character and the palette.
    2. **The frame** — the panel's own artwork. Harder, and it depends on
       decisions made in stage 1.
    3. **The manifest** — the JSON tying it together. Last, once the filenames
       are actually known.

    At the end of each stage, show me what you have and wait. Do not run ahead
    into the next one.

    **Stills before motion, always.** Anything animated gets drawn as a single
    still first and approved before it becomes frames. A silhouette that reads
    wrong costs one drawing to fix now and every frame to fix later.

    **Ask before you start if anything is ambiguous** enough to change what you
    would draw. One question now beats a round of revisions.

    **Expect two or three rounds.** I will have notes. That is the process
    working, not a failure of it.
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

    /// What each state has to look like, and what happens when one of the four
    /// colours is overruled — which is where the system fell over in practice:
    /// a yellow needsInput sat next to a gold working and nothing forbade it.
    static let moodColours = """
        | state | read it as | carry it with |
        |---|---|---|
        | idle | asleep, nothing wanted | **blue**, quiet — see below |
        | working | busy, leave it alone | **motion.** Any colour but the other three |
        | needsInput | **stop and look** | **red**, highest contrast of the four, plus a symbol |
        | done | finished well | **green**, calm but bright |

        **On idle: the tile recedes, the mark does not.** Taken as "make it all
        dim" you get a tile with nothing to see on a dark panel. The shipped
        station theme is a deep blue field with one huge bright sleep-mark on
        it — quiet overall, unmistakable at a glance.

        **If I overrule one of these, the others have to move too.** The system
        is that all four are instantly distinguishable, not that the colours are
        sacred — so if I ask for a yellow needsInput, working cannot stay gold.
        Say so and propose what working becomes.

        Red, green and blue are spoken for, and they are the three anyone reads
        instantly. There is no obvious fourth, so do not go looking for one:
        `working` is the state that moves, and motion carries it better than any
        hue could. Both existing themes landed on a neutral violet there and it
        reads perfectly.

        **The same character in all four.** Whatever it is appears in every
        state; only its pose, colour and surroundings change. Props may come and
        go, the character may not — four tiles that each star something different
        read as four themes.
        """
}
