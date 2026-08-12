// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The fixed prose of the theme prompt.
///
/// Separated from `ThemePromptBuilder` because it is copy rather than
/// logic: it changes when the theme format gains a feature, not when the
/// builder does, and it is long enough to drown the assembly code.
enum ThemePromptText {
    static let preamble = """
    I want you to design a theme for **Ground Control**, a macOS menu-bar app that
    shows my running Claude Code sessions as rows in a small floating panel.

    A theme is ONE FOLDER containing a `theme.json` manifest plus the image or
    video files it references. Paths in the manifest are relative to that folder,
    and files can be named anything as long as the manifest points at them.

    Every key is optional: anything I leave out falls back to the app's built-in
    default, so the manifest only needs the keys we actually want to change.
    """

    /// The single most misunderstood part of the format. An image generator
    /// asked for "a panel background" will centre a composition and put detail
    /// in the middle — exactly the region that gets stretched or tiled.
    static let backgroundSection = """
    ## 2. Backgrounds (optional — skip if colours alone suit the design)

    **Read this before drawing any background: the panel is resizable.** I drag
    it wider and taller, so a background cannot be a fixed composition. The app
    uses **nine-slice** scaling:

    ```
    ┌───┬─────────┬───┐   corners  — never scale, stay pixel-crisp
    │ ▨ │    ↔    │ ▨ │   top/bottom edges — repeat or stretch HORIZONTALLY
    ├───┼─────────┼───┤   left/right edges — repeat or stretch VERTICALLY
    │ ↕ │   ↔ ↕   │ ↕ │   centre  — fills in BOTH directions
    ├───┼─────────┼───┤
    │ ▨ │    ↔    │ ▨ │
    └───┴─────────┴───┘
    ```

    What that means for the art:

    - Put **detail, ornament and logos in the CORNERS only.** Anything in the
      middle gets repeated or smeared as the panel grows.
    - The **centre must be a flat colour or a seamlessly tiling texture.** Give
      it no gradient across the whole image, no single focal point, no framing
      that only works at one size.
    - The **edges must tile seamlessly along their axis** — the top edge repeats
      left-to-right, so its left and right ends have to match up.
    - Tell me the **`capInsets`** in pixels: how far in from each side the
      corner artwork ends. That is the only extra number I need.
    - One image, not nine tiles. The app slices it.
    - If you draw a **frame or border**, tell me a `layout.contentInset` in
      points (roughly how thick the border is at display size, usually 10–20).
      Rows span the full width, so without it they sit on top of your border and
      it is never seen.
    - Also give the row colours some alpha — `"rowBackground": "#120c1cbb"` —
      or the rows cover the artwork completely. Around `bb` (73%) keeps text
      readable while the background still reads through.

    A background is only worth making if the theme wants texture — a metal
    plate, worn paper, a CRT bezel, scanlines. If the design is flat colour,
    skip it entirely and let the palette do the work.

    Surfaces that accept one: `windowBackground` (the whole panel),
    `titleBarBackground` (a fixed-height strip, so only the left/right caps
    matter — set top/bottom insets to 0), `footerBackground` (the small well
    behind the spectrum analyser). There is also `needsActionDot`, a tiny
    square badge that replaces the drawn red dot; that one just scales, no
    slicing.

    If art must stay proportional instead — a mascot painted into the panel —
    use `"mode": "aspectFill"` and ignore the slicing rules; it will be scaled
    and cropped to fit rather than sliced.
    """

    /// Shaped windows are the one feature that changes what a theme *is* — a
    /// skin rather than a colour scheme — so the model needs telling that the
    /// rectangle is optional at all.
    static let shapeSection = """
    ## Optional: break the rectangle

    The panel does not have to be a rectangle. If you supply a `window.shape`
    image, **its alpha channel becomes the window itself** — transparent pixels
    are not part of the window, so they are see-through *and* click-through.

    That means art can escape what would have been the edge: an antenna over
    the corner, a mascot leaning out of the side, a torn or curved border, a
    glow bleeding past the body.

    How to draw one:

    - Make the canvas **larger than the panel body** and leave the surplus
      transparent. That surplus is where anything "outside" lives.
    - Draw the body itself opaque; that is where rows will sit.
    - Tell me a `layout.contentInset` in points — how far in from the canvas
      edge the body starts — or rows will be laid over your border.
    - It is nine-sliced like any background, so give `capInsets` too and the
      corners keep their shape while the panel resizes.

    ```json
    "window": {
      "shape": "skin.png",
      "capInsets": { "top": 90, "left": 90, "bottom": 90, "right": 90 },
      "resizable": true
    },
    "layout": { "contentInset": 34 }
    ```

    **Two things a shaped theme must provide**, because macOS draws no window
    chrome at all in this mode: somewhere obvious to grab and drag, and
    somewhere to click to close. Draw them into the skin. A beautiful panel
    nobody can move or dismiss is worse than a plain one.

    Give the row colours alpha as well, or the rows will cover the body art.
    """

    static let paletteReference = """
    ## Colour keys

    | key | what it paints |
    |---|---|
    | `windowBackground` | the panel behind everything |
    | `titleBarBackground` / `titleBarText` | the title strip and its text |
    | `footerBackground` | the well behind the spectrum analyser |
    | `rowBackground` / `rowBackgroundAlt` | alternating session rows |
    | `rowBackgroundHover` | a row under the pointer |
    | `sessionName` | the project name on each row |
    | `message` / `messageDim` | the latest message, lit and quiet |
    | `needsAction` | **the alarm colour** — dot and face when Claude is blocked |
    | `working` | accent while a session is running |
    | `idle` | accent for a quiet session |
    | `accent` | accent for a finished session; also the analyser's floor |
    | `divider` | hairlines between rows |

    ### The analyser

    The title bar holds a five-row LED matrix that shows how busy the agents are
    and occasionally spells a word. It inherits the row colours, but you can set
    it separately with a `matrix` block — worth doing, since it is the most
    eye-catching part of the panel:

    ```json
    "matrix": {
      "low":   "#39ff14",
      "high":  "#39c5ff",
      "alarm": "#ff2d55",
      "unlit": "#26263219",
      "text":  "#e6e6ec",
      "peak":  "#e6e6ec"
    }
    ```

    Bars ramp from `low` at the floor to `high` at the ceiling; `alarm` replaces
    the whole ramp when something needs me; `unlit` is the dim grid behind them,
    so keep it subtle; `text` is the colour of a word sweeping through.

    You can also give the theme a **voice** — short phrases the display spells
    out now and then, in character with the mascot:

    ```json
    "matrix": { "messages": ["SYSTEM ONLINE", "NEURAL LINK", "STANDING BY"] }
    ```

    Six to ten of them. **Thirteen characters maximum each**, and only A–Z, 0–9,
    space and `. - !` — anything else cannot be drawn and will be dropped.

    Contrast matters more than prettiness here: `needsAction` has to jump out of
    the panel from across the room, and `messageDim` has to stay readable.
    """
}
