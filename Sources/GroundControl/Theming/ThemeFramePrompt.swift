// SPDX-License-Identifier: AGPL-3.0-or-later
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
          "capInsets": { "top": 90, "left": 90, "bottom": 90, "right": 90 },
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

        \(drawingRules)

        \(animationRules)
        """
    }

    /// How the art has to be drawn for the nine-grid to work at all. Not style
    /// advice — every line here is something that visibly broke a real theme.
    private static let drawingRules = """
        So, drawing rules — these are not style advice, the art breaks without
        them:

        - **Every ornament goes in a corner.** Towers, masts, dishes, mascots,
          flourishes. Anything distinctive on an edge is repeated across the
          whole side.
        - **Point the ornaments outward**, away from the opening in the middle.
          That opening is where the app's text goes, and the frame is drawn on
          top of it — anything reaching inward covers content. Keep the inner
          edge clean and rectangular on all four sides.
        - **Keep the corners shallow**, no more than about 60px deep in a 450px
          image. The panel's own title and icon sit just inside the top-left
          corner, underneath the frame, and a deeper ornament hides them.
        - **Each edge must be a seamless repeating strip.** The top edge tiles
          left-to-right, so its left and right ends have to meet. Same for the
          others down their own axis.
        - **The centre must be flat or a seamless tile**, and dark enough for
          white text.
        - **Draw the whole thing about 450px square.** Cap insets are used at
          their literal size, so a 150px corner on a 450px-wide panel leaves
          almost no middle. This is the single most common way one of these
          goes wrong.
        - `capInsets` is where your corner artwork ends, in those same pixels.
          **Measure it off the drawing you actually produced** — the column
          where the ornament stops and the plain edge begins — rather than
          reusing a number from an example. A cap that falls short leaves the
          rest of the ornament in the *tiled* strip, which then repeats it
          along the edge. Roughly a fifth of the image is typical.
        - Use `"mode": "tile"` for detailed edges made of repeating segments,
          `"stretch"` for plain gradients.
        - Give `rowBackground` and `rowBackgroundAlt` alpha, or the rows cover
          your artwork completely.
        """

    /// Only reaches an author who asked for movement. Both rules come from
    /// animations that shipped and had to be redone.
    private static let animationRules = """
        **If the frame animates**, two things matter more than the animation
        itself, and both have gone wrong before:

        - **Lock the silhouette.** Every frame must have identical outer bounds.
          Do not generate each frame from the previous one — that drifts. One
          attempt varied 17px in height across its frames and read on screen as
          the panel changing size while it played.
        - **Close the loop.** The last frame must flow into the first. The same
          attempt ended heavier than it started, growing steadily and then
          snapping back at the wrap.

        Animate surface detail only — window lights, indicator lamps, a glint
        travelling along a panel — on a cycle that returns exactly to its
        starting values. 24–30 frames is plenty; more frames is more drift and a
        far larger file.

        **Draw the still frame first and show it to me.** One static image, the
        full composition, before a single animated frame exists. Wait for me to
        confirm the corners, the edges and the opening are right. Only then
        animate it.

        Everything that goes wrong here goes wrong in the composition, not in the
        motion — an ornament in the wrong place or an edge that will not tile is
        one drawing to redo before it is animated, and thirty afterwards.
        """
}
