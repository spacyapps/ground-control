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

    /// The gate between drawing and animating, and the only place the corner
    /// overhang gets checked.
    ///
    /// Overhang is encouraged elsewhere — the frame is in front and ornaments
    /// hanging over the opening is the look. But an ornament that runs *along*
    /// an edge, past where the cap will cut, lands inside the repeating strip
    /// and is tiled down the side. Inward overhang is fine; sideways overhang
    /// is the unicorn-head problem. Nothing else in the prompt separates those
    /// two, and they are one pixel apart.
    static let confirmStill = """
        ## Show me the still and wait

        One static image of the whole frame, before anything moves. Show it at
        the size it will actually be used, not enlarged.

        Then check these with me, and wait for a yes:

        - **Does anything from a corner run too far along an edge?** Corners are
          fixed; edges repeat. An ornament that reaches sideways past where the
          cap cuts is not drawn once — it is tiled the whole length of that side
          and sliced where the tile ends. Hanging *inward* over the opening is
          fine and looks right. Spreading *sideways* into the edge is the one
          that breaks.
        - **Will each edge tile without a seam?** Say plainly whether its two
          ends meet, rather than assuming.
        - **Is the opening clear enough** that the title and my ✕ and ↔ marks
          are still readable under the top-left corner?
        - **Is the silhouette irregular**, inside and out, rather than a
          rectangle with a rectangular hole?

        If any answer is no, fix it now. Every one of these costs one drawing to
        repair at this point and every frame to repair after it is animated.
        """

    /// Asked per corner and per edge, because that is the granularity the
    /// nine-grid already has — and because "animate the frame" gets the whole
    /// thing moving, which is exactly what a panel behind text must not do.
    static let animationChoices = """
        ## Once I confirm the still, ask what should move

        Do not decide this for me, and do not animate anything before asking.

        - **Which corners move, and how?** One at a time: a lamp that pulses, a
          dish that turns a few degrees, steam, a slow blink. Any corner may
          stay completely still — most should.
        - **Which edges move, if any?** Remember an edge repeats, so whatever
          moves there moves identically along the whole side at once. A travelling
          glint works; a single event does not.
        - **Or nothing at all.** A still frame is a perfectly good answer and
          the one I should probably pick.

        **Keep it quiet.** This sits behind text I am trying to read, so it must
        never compete with the avatars — they are the part carrying meaning. The
        shipped station theme is the level to aim at: surface lights only, on a
        slow cycle. Nothing that changes shape, nothing that sweeps across the
        whole frame, nothing that pulls the eye away from a row that has just
        turned red.

        ### Then stop, price it, and ask me whether to go ahead

        Whichever way I picked, animating costs far more than the still I have
        already approved, and leaves a heavier theme behind.

        So before you generate anything, tell me **the actual count** for what I
        chose — one clip per moving thing if we are using video, or the total
        number of frames if we are drawing them. Not "this may take a while":
        the number.

        | What I picked | What it costs |
        |---|---|
        | Keep the still | nothing more; the theme is finished |
        | One corner, drawn | a handful of images |
        | One corner, video | one clip |
        | Three corners and an edge | four of whichever, and a heavy theme |

        Then ask me, as a plain question and nothing else in the message:

        > **Generate N for the animation, or keep the still frame?**

        And wait. **My yes to the still was not permission to animate, and
        choosing what moves was not permission either — this is a third,
        separate yes.** Generating first and showing me the bill afterwards is
        the one outcome this section exists to prevent.

        If I say keep the still, that is a finished theme and a good one. Write
        the manifest against the still and hand it back without arguing.
        """

    /// The two technical rules, once something has actually been chosen to
    /// move. The staging that used to live here moved into `confirmStill`,
    /// where it is a gate rather than a footnote, and the two ways of making
    /// frames are shared with part one — an avatar and a frame are animated
    /// identically.
    static let animation = """
        ### Making the frames themselves

        Whichever way you make them, both of these have gone wrong before:
        every frame must have identical outer bounds, and whatever is *not*
        moving must sit in exactly the same place in each. A frame that drifts
        two or three pixels reads as the panel twitching, not as animation.

        Animate surface detail only — lights, lamps, a glint travelling along a
        panel. The silhouette is settled by now and must not move again.

        \(ThemePromptText.motionRoutes)
        """
}
