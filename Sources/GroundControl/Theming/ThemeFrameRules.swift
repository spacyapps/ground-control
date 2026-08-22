// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The rules a nine-grid frame has to obey to work at all.
///
/// Split from `ThemeFramePrompt`, which asks the questions and states the
/// defaults, because these are the part nobody may skip and both files were
/// over the size a single one should be.
///
/// Every line here is something that visibly broke a real theme. None of it is
/// style advice, and none of it is negotiable in the way the motif is.
enum ThemeFrameRules {
    /// The grid itself, drawn rather than described. The diagram does more work
    /// than any paragraph: it is the one place the tiling is obvious at a
    /// glance, which is what stops ornaments landing on edges.
    static let grid = """
        ## The nine-grid — this decides how you must draw

        Your image is cut into nine pieces, and each behaves differently as I
        drag the panel to any size:

        ```
        ┌────────┬──────────────┬────────┐
        │ corner │  top edge    │ corner │   corners     never change size
        │  FIXED │  repeats ↔   │  FIXED │   top/bottom  repeat sideways
        ├────────┼──────────────┼────────┤   left/right  repeat vertically
        │ left   │              │ right  │   centre      keyed out, rows show
        │ rpts ↕ │  centre ↔↕   │ rpts ↕ │
        ├────────┼──────────────┼────────┤
        │ corner │  bottom edge │ corner │
        │  FIXED │  repeats ↔   │  FIXED │
        └────────┴──────────────┴────────┘
        ```

        This is why the questions asked for **objects in corners** and **texture
        on edges**, and it is the whole reason the split matters.
        """

    /// How the art has to be drawn. The order is deliberate: the mistakes that
    /// cost a whole redraw come first.
    static let drawing = """
        ### Drawing rules

        - **Every distinct object goes in a corner.** Towers, masts, dishes,
          mascots, a bird, a knot, a hanging twig. Put one on an edge and the
          panel does not show it once — it repeats it the whole way along and
          cuts it in half wherever the tile ends. Every theme so far has broken
          this rule, including ones drawn by someone who had read it.
        - **Each edge is a seamless repeating strip.** The top edge tiles
          left-to-right, so its left and right ends must meet. Same for the
          others down their own axis.
        - **Draw the whole thing about 450px square.** Caps are used at their
          literal size, so a 150px corner on a 450px panel leaves almost no
          middle. Pixel size here is not a quality setting — it is how thick the
          frame appears and how narrow the panel may get. The same art at 900px
          is not sharper, it is twice as heavy.
        - **Know what is under the top-left corner.** The panel's title and its
          ✕ and ↔ marks sit just inside it, beneath your artwork. Overhang there
          is fine — the frame is in front, and some overlap looks right — but a
          solid ornament more than about 60px deep buries the title rather than
          decorating it. Keep that one corner readable; the other three are
          yours.
        - Give `rowBackground` and `rowBackgroundAlt` alpha, or the rows cover
          your artwork completely.
        """

    /// Measuring, which is the step most likely to be guessed at.
    static let measuring = """
        ### The two inset numbers, which are not the same number

        Both are read straight off the image you actually produced. Measure
        them; do not reuse a number from an example.

        - **`window.capInsets` cuts your artwork** into the nine pieces above.
          Each value is the column or row where your corner ornament stops and
          the plain repeating edge begins. A cap that falls short leaves the
          rest of the ornament inside the *tiled* strip, which then repeats it
          along the edge — the most expensive mistake available here.
        - **`layout.contentInset` pads my rows** away from your frame. It is how
          far in the text starts, and it takes one number or four.

        They have been swapped once. The result was twigs tiling across the
        title, which reads as a corrupt image rather than a wrong number, so
        nobody thinks to look at a config key.

        A frame is rarely as thick at the top as at the sides, so four numbers
        usually fit better than one:

        ```json
        "layout": { "contentInset": { "top": 140, "left": 152, "bottom": 80, "right": 152 } }
        ```

        If your opening is rounded, give `layout.contentCornerRadius` its radius
        in the same pixels — otherwise a round frame encloses a square screen.

        **If you redraw at a different size, re-measure both.** Caps do not
        scale themselves, and stale ones land inside the ornament.
        """

    /// Only reaches an author who asked for movement. Both rules come from
    /// animations that shipped and had to be redone.
    static let animation = """
        ### If the frame animates

        Two things matter more than the animation itself, and both have gone
        wrong before:

        - **Lock the silhouette.** Every frame must have identical outer bounds.
          Do not generate each frame from the previous one — that drifts. One
          attempt varied 17px in height across its frames and read on screen as
          the panel changing size while it played.
        - **Close the loop.** The last frame must be a legal step *into* the
          first, not merely similar to it. Play frames 28, 1, 2 in sequence and
          the motion should be indistinguishable from 1, 2, 3. Ping-ponged poses
          fail this: they look alike at the wrap and still jump.

        Animate surface detail only — lights, lamps, a glint travelling along a
        panel — on a cycle returning exactly to its starting values.

        **Draw the still frame first and show it to me.** One static image, the
        full composition, before a single animated frame exists. Everything that
        goes wrong here goes wrong in the composition, not the motion: an
        ornament in the wrong place is one drawing to redo before it is
        animated, and thirty afterwards.
        """
}
