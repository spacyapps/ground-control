// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The frame half of a theme prompt.
///
/// Kept apart from the rest because the two branches are long and share
/// nothing: a simple frame is scaled whole and has nothing to measure, while a
/// nine-grid dictates how the artwork itself must be drawn.
enum ThemeFramePrompt {
    static func keys(for brief: ThemeBrief) -> String {
        brief.frame == .ninegrid ? ninegridKeys(for: brief) : simpleKeys(for: brief)
    }

    static func simpleKeys(for brief: ThemeBrief) -> String {
        """
        Add this block for the frame:

        ```json
        "window": {
          "image": "panel.png",
          "lockAspect": true,
          "removeBackground": "\(brief.keyColour)"
        },
        "layout": { "resize": "aspect", "contentInset": 60 }
        ```

        **The whole picture is scaled to the panel as one piece.** Draw it at any
        size you like and at whatever proportions suit the art — the panel keeps
        those proportions, and the rows scroll inside. Nothing needs to tile and
        nothing needs measuring.

        - `contentInset` holds the rows off your border. Measure it in your own
          artwork's pixels: if the frame is 120px thick in a 900px image, use
          `120`. It is scaled along with everything else.
        - Give `rowBackground` and `rowBackgroundAlt` alpha, or the rows cover
          your artwork completely.
        """
    }

    static func ninegridKeys(for brief: ThemeBrief) -> String {
        """
        Add this block for the frame:

        ```json
        "window": {
          "image": "frame.png",
          "lockAspect": false,
          "mode": "tile",
          "capInsets": { "top": 75, "left": 75, "bottom": 75, "right": 75 },
          "removeBackground": "\(brief.keyColour)"
        },
        "layout": { "resize": "free", "contentInset": 60 }
        ```

        **This is the nine-grid, and it decides how you must draw.** The image is
        cut into nine pieces by `capInsets`, and each behaves differently as the
        panel is dragged to any size:

        ```
        ┌────────┬──────────────┬────────┐
        │ corner │  top edge    │ corner │   corners     never change size
        │  FIXED │  repeats ↔   │  FIXED │   top/bottom  repeat sideways
        ├────────┼──────────────┼────────┤   left/right  repeat vertically
        │ left   │              │ right  │   centre      repeats both ways
        │ rpts ↕ │  centre ↔↕   │ rpts ↕ │
        ├────────┼──────────────┼────────┤
        │ corner │  bottom edge │ corner │
        │  FIXED │  repeats ↔   │  FIXED │
        └────────┴──────────────┴────────┘
        ```

        So, drawing rules — these are not style advice, the art breaks without
        them:

        - **Every ornament goes in a corner.** Towers, masts, dishes, mascots,
          flourishes. Anything distinctive on an edge is repeated across the
          whole side.
        - **Each edge must be a seamless repeating strip.** The top edge tiles
          left-to-right, so its left and right ends have to meet. Same for the
          others down their own axis.
        - **The centre must be flat or a seamless tile**, and dark enough for
          white text.
        - **Draw the whole thing about 450px square.** Cap insets are used at
          their literal size, so a 150px corner on a 450px-wide panel leaves
          almost no middle. This is the single most common way one of these
          goes wrong.
        - `capInsets` is where your corner artwork ends, in those same pixels —
          75 for a 450px image with corners about a sixth of the way in.
        - Use `"mode": "tile"` for detailed edges made of repeating segments,
          `"stretch"` for plain gradients.
        - Give `rowBackground` and `rowBackgroundAlt` alpha, or the rows cover
          your artwork completely.
        """
    }
}
