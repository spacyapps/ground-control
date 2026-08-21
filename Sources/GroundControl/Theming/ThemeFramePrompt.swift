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
        let body = brief.frame == .ninegrid ? ninegridKeys(for: brief) : simpleKeys(for: brief)
        return overlayModel(for: brief) + "\n\n" + body
    }

    /// What a frame *is*, before any JSON says how to configure one.
    ///
    /// This section exists because it was missing. Part 2 opened with a
    /// `window.image` key and never said what the image was, so a model reading
    /// "frame" reasonably drew a picture: the first attempt at the garden theme
    /// was a full landscape in a square, and the whole generation was wasted.
    /// The motif was never the problem — the engineering of an overlay was.
    static func overlayModel(for brief: ThemeBrief) -> String {
        """
        ## First, what a frame is here

        **You are drawing an overlay, not a picture.** It sits *in front of* the
        panel. The middle is a hole, keyed out in `\(brief.keyColour)`, and the
        app's rows of text show through it. Anything you paint in that hole is
        erased.

        So the artwork is a ring, and only a ring. Not a window looking onto a
        scene, not a square illustration with a border around it. If you find
        yourself composing a landscape, you have already gone wrong — that is
        the single most expensive mistake available here, because a scene cannot
        become a frame by editing and has to be redrawn from nothing.

        The shipped station theme is the working model: a narrow structural ring,
        ornaments sticking out from the corners into the space beyond, and
        everything else keyed away. Look at it before you draw.

        **The overlay is in front, and that is allowed to show.** Ornaments may
        overhang the opening and cross what is underneath — the station's do. Do
        not try to prevent every overlap by inflating `contentInset`; that pushes
        every row down and shrinks the usable panel to buy back a few pixels of
        clearance you did not need.

        **On the key colour.** `\(brief.keyColour)` was chosen without seeing the
        art. If the motif genuinely needs that colour — green grass, green
        foliage, a pink sky against magenta — **say so before you draw**, and we
        will change it. Discovering it mid-generation costs a whole set.
        """
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
          flourishes, a bird, a knot, a hanging twig. Put one on an edge and the
          panel does not show it once — it repeats it the whole way along, and
          cuts it in half wherever the tile happens to end. This rule has been
          broken by every theme so far, including by people who had read it, so
          check your drawing against it before you export rather than after.
        - **Point the ornaments outward**, away from the opening in the middle.
          That opening is where the app's text goes, and the frame is drawn on
          top of it — anything reaching inward covers content. Keep the inner
          edge clean and rectangular on all four sides.
        - **Know what is under the top-left corner.** The panel's own title and
          close button sit just inside it, beneath your artwork. Overhang there
          is not banned — the overlay is in front and some overlap looks right —
          but a solid ornament more than roughly 60px deep in a 450px image will
          bury the title rather than decorate it. Keep that one corner readable;
          the other three are yours.
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
        - **`capInsets` and `contentInset` are not the same number and do not do
          the same job.** `capInsets` cuts *your artwork* into the nine pieces —
          get it wrong and the ornaments tile along the edges. `contentInset`
          pads *the app's rows* away from the border — get it wrong and the text
          sits under your frame. They have been swapped once, and the result was
          twigs tiling across the title, which reads as a corrupt image rather
          than a wrong number.
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
        - **Close the loop.** The last frame must be a legal step *into* the first —
          not merely similar to it. Play frames 28, 1, 2 in sequence and the
          motion should be indistinguishable from 1, 2, 3. Ping-ponged poses
          fail this: they look alike at the wrap and still jump.

        Animate surface detail only — window lights, indicator lamps, a glint
        travelling along a panel — on a cycle that returns exactly to its
        starting values. 24–30 frames is plenty; more frames is more drift and a
        far larger file.

        **Draw the still frame first and show it to me.** One static image, the
        full composition, before a single animated frame exists. This is the same
        staging the avatars use, and for the same reason: a fix to the shape of a
        spout is one drawing on a still-approved pipe, and thirty on a scene
        already in motion. Wait for me to
        confirm the corners, the edges and the opening are right. Only then
        animate it.

        Everything that goes wrong here goes wrong in the composition, not in the
        motion — an ornament in the wrong place or an edge that will not tile is
        one drawing to redo before it is animated, and thirty afterwards.
        """
}
