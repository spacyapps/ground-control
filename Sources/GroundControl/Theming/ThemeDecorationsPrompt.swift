// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Part three of a theme prompt: corner decorations, optional.
///
/// A guided step like `ThemeFramePrompt` — questions asked before anything is
/// drawn — rather than a page of rules to read. Its own file because part three
/// grew from a footnote into a real stage, and `ThemePromptText` was already at
/// its length limit. Split into three constants so the one part that varies —
/// the closing rules, which name the key colour — is the only function.
enum ThemeDecorationsPrompt {
    /// Takes the theme's key colour so it can name it the way part two does.
    static func text(key: String) -> String {
        [intro, questions, closing(key: key)].joined(separator: "\n\n")
    }

    private static let intro = """
    # Part three — corner decorations (optional)

    Most themes are finished after part two. This part adds **corner
    decorations** — small, independent pieces of art pinned to the panel's
    corners: a mascot, a hanging lantern, an antenna, ivy creeping in. They have
    nothing to do with the frame — none of part two's fitting rules apply. They
    are the one place art is allowed to break the panel's outline, so they are
    worth deciding before you draw them.

    ## Ask me these, then wait

    Ask them all at once. Draw nothing until I answer. If I say "you choose" to
    any, pick something that belongs with the moods and the frame already made,
    and tell me what you chose.
    """

    private static let questions = """
    **1. Which corners?** Any of `topLeft`, `topRight`, `bottomLeft`,
    `bottomRight` — or "none, we're done." Each corner is its own drawing and
    its own decision; they need not match or come in pairs.

    **2. What is in each one?** One thing per corner. A perched bird, a crescent
    moon, a paper lantern, a coil of rope, a satellite dish. Name it plainly.

    **3. A subject, or a flourish?** A *subject* — a creature, an object — sits
    at the corner and reads as placed there. A *flourish* — sparks, vines,
    drifting smoke, trailing circuitry — has no centre and creeps in from the
    edge. Say which, per corner.

    **4. How big?** As a fraction of the panel's shorter side. A quarter is a
    generous mascot that owns its corner; a tenth is a quiet accent. I can
    resize it afterwards with one number, so this is a starting point, not a
    commitment.

    **5. Tucked in the corner, or reaching past the frame?** A decoration may
    extend past the frame's outline — an antenna, a horn, a branch. The margin
    around the frame, out to the panel's own rectangle, is yours to use; that is
    what makes it read as sticking out. The panel rectangle itself is a hard
    edge, though — anything past it is clipped, and the panel will not grow to
    keep it, so nothing reaches far into the desktop. Per corner: inside, or
    breaking the edge — and if breaking it, which way and how far?

    **6. Still, or moving?** Movement plays *only while a session is working*; at
    rest it freezes on its first frame, which has to be a finished picture on
    its own.
    - If it moves: **in place, or travelling?** A flicker, a pulse, a slow
      breath stays inside its own footprint. A bird flying across, smoke
      drifting up and out, a fish crossing the corner — that *travels*.
    - **If it travels: which direction, and how far?** "Left to right along the
      top, most of the panel's width." "Straight up and off the edge, about its
      own height again." This sets how wide the canvas has to be and where the
      subject sits at rest — I draw the whole journey into one image and never
      move it myself.
    - **Format: APNG if it moves, PNG if it is still — GIF only as a fallback.**
      Give the APNG or PNG a **real transparent alpha channel** — the area
      around the decoration genuinely empty, not filled with any colour. That
      is the whole reason to use these formats here: their 8-bit alpha keeps a
      soft, anti-aliased edge that a colour key cannot. Only if you can output
      nothing but GIF, flood the background with the flat key colour instead
      and I will key it on load — a GIF's 1-bit alpha then leaves a hard
      fringe, which is why it is the lesser option. Never a video: MP4 and MOV
      are not read from a decoration's `image`, and I cannot key a clip.
    """

    /// Split in two only to stay under the 60-line function limit. The seam is
    /// the heading the prose already breaks on — what to draw, then the JSON to
    /// write — so neither half reads as having been cut mid-thought.
    private static func closing(key: String) -> String {
        drawingNotes(key: key) + "\n" + blockNotes(key: key)
    }

    private static func drawingNotes(key: String) -> String {
        """
        ## Once I have answered

        - **Draw each one at the size it should occupy on screen.** No box to fit
          into, no Retina doubling — its pixels are its points. If you drew the
          moods at 2x for sharpness, do the same here and set `scale` to `0.5`.
        - **Hand it to me transparent.** An APNG or PNG carries its own alpha,
          so the area around the decoration is simply empty — do not fill it,
          and do not set `removeBackground`. The key colour is only for the GIF
          fallback: there, flood everything that is not the decoration with the
          flat `\(key)` and add `"removeBackground": "\(key)"` so I strip it on
          load — and the part-two warnings apply, a near-miss colour is not
          removed and a glint in the key hue is erased. Never a video.
        - **A travelling decoration is one wide canvas.** Crop it tight to the
          whole path of travel — do not pad it out to a square. An animated
          APNG corner is the heaviest file a theme ships, so keep it lean:
          roughly 60–120 frames, and no more pixels than it covers on screen.
        - **If it moves, close the loop** — the last frame flows back into the
          first — and keep the resting anchor point still between frames, or it
          jitters against the corner.
        - **Keep the outer corner of a top decoration quiet.** My ✕ and ↔ marks
          draw on top of `topLeft` and `topRight` art, so they still work, but a
          busy top corner crowds them. Leave roughly the outermost 28pt clear of
          anything that must be seen.
        - **Part two may already have an ornament in this corner.** Your
          decoration sits on top of it — draw it to work *with* what is there: a
          mascot leaning against the frame's dish, not a second dish over it.
        - **A quiet easter egg, if you want one:** `image` can be a *list* of
          filenames instead of one. While a session is working the corner
          plays through the list end to end and loops — each entry for its own
          natural length: an animation runs its whole loop, a still holds a few
          seconds, then the next takes over. It freezes when work stops and
          picks up from there. Two or three distinct poses is the idea; skip
          this unless I ask.
        """
    }

    private static func blockNotes(key: String) -> String {
        """
        ## The block

        Add one `"cornerDecorations"` key at the **top level of `theme.json`** —
        a sibling of `"window"` and `"avatar"`, not nested inside either. One
        entry per corner you are using, keyed by corner name:

        ```json
        {
          "window": { "…": "…" },
          "avatar": { "…": "…" },
          "cornerDecorations": {
            "topRight": {
              "image": "antenna.apng",
              "scale": 0.5,
              "offset": { "x": 12, "y": -40 }
            }
          }
        }
        ```

        No `removeBackground` — the APNG is already transparent. Add
        `"removeBackground": "\(key)"` only if `antenna` is the GIF fallback.

        `offset` moves it from the corner in screen terms — `x` right, `y` down —
        measured after `scale`. `{0,0}` sets its own matching corner exactly on
        the panel's; a negative `y` on a top corner lifts it up past the edge.
        Replace the numbers with the ones you measure against the still.
        """
    }
}
