// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The frame half of a theme prompt: four questions, the defaults nobody is
/// asked about, and the nine-grid rules.
///
/// **It asks before it draws.** The frame used to be described at the author in
/// one long block, which produced frames nobody had chosen — a full landscape
/// in a square, on the first real attempt, because "frame" without a model
/// means "paint a scene". Four questions cost a minute and remove that whole
/// class of waste: the model knows the motif, the palette, what is in each
/// corner and what runs along the edges before a pixel exists.
///
/// **Only the nine-grid remains.** A scaled-whole frame was the other option
/// and the default, which meant the easy path taught nothing that survives a
/// resize. The manifest still loads those themes; we simply stopped teaching a
/// second way to do it.
enum ThemeFramePrompt {
    /// Returned as separate sections rather than one block, because part two
    /// numbers its headings and a frame folded into the manifest section would
    /// be read as a footnote to the JSON rather than as the work itself.
    static func sections(for brief: ThemeBrief) -> [String] {
        [
            questions,
            defaults(for: brief),
            [ThemeFrameRules.grid, ThemeFrameRules.drawing,
             ThemeFrameRules.measuring, manifestBlock(for: brief)]
                .joined(separator: "\n\n"),
            ThemeFrameRules.confirmStill,
            [ThemeFrameRules.animationChoices, ThemeFrameRules.animation]
                .joined(separator: "\n\n")
        ]
    }

    /// What to ask, and the shape of a good answer.
    ///
    /// Asked in one batch rather than one at a time: the answers interact —
    /// corners and edges have to belong to the same object — and four separate
    /// round trips is how a five-minute job becomes a chore.
    ///
    /// Each carries examples, because "describe your frame" gets a paragraph of
    /// adjectives while "a spaceship hull, a bakery counter, a carved picture
    /// frame" gets a decision.
    static let questions = """
        ## Ask me these four questions first

        Ask all four at once, then wait. Do not draw anything until I answer.
        If I say "you choose" to any of them, choose something that belongs with
        the moods you have already drawn, and tell me what you chose.

        1. **What is this frame made of?** A few words. For example: a spaceship
           hull, a bakery counter, a carved wooden picture frame, a forest
           floor, a circuit board, a coral reef, stacked books.

        2. **What colours?** Two or three that dominate, and one bright accent
           that appears only in small amounts.

        3. **What is in each of the four corners?** Corners are the only place a
           distinct object can live, so this is where the character goes. Name
           one per corner, or say "plain" for any you want left quiet. For
           example: a satellite dish top-left, a sun top-right, an engine nozzle
           bottom-left, a warning lamp bottom-right.

        4. **What runs along the edges?** Not objects — a texture that repeats
           forever without a visible seam. Rivets, brickwork, cabling, vines,
           rope, moulding, circuitry. Say whether the top should differ from the
           sides and bottom; they usually do.
        """

    /// Decisions already made, stated so they are not asked about.
    ///
    /// The instruction that produced this section: *"those defaults they can
    /// override themselves in the json so don't over ask."* Every question here
    /// would have a near-universal answer, and asking it spends the author's
    /// patience on something the manifest can change later in ten seconds.
    static func defaults(for brief: ThemeBrief) -> String {
        """
        ## What I have already decided — do not ask me about these

        **You are drawing an overlay, not a picture.** It sits in front of the
        panel. The middle is a hole and my rows of text show through it.
        Anything painted in that hole is erased. If you find yourself composing
        a landscape you have gone wrong — a scene cannot be edited into a frame,
        it has to be redrawn from nothing.

        - **Overlay is on.** The frame is painted in front of the rows and
          simply covers what it overlaps, so nothing has to be fitted to
          anything. Ornaments may hang over the opening; that is the look, not a
          mistake.
        - **The silhouette is irregular, inside and out.** Not a rectangle with
          a rectangular hole. The outer edge breaks its outline — things stick
          out past it — and the inner opening is uneven too. A plain square
          frame is the one answer that is always wrong here. Whatever
          irregularity sits on an *edge* still has to tile; irregularity that
          cannot repeat belongs in a corner.
        - **Everything that is not frame is `\(brief.keyColour)`**, flat and
          exact, inside the opening and outside the artwork alike. I key it out
          on load. A near miss is a miss: a slightly different green stays
          visible, and a solid middle hides the whole panel. Keep the art well
          clear of that colour rather than merely different from it — against a
          green key a bright green light is erased too, which is why the colour
          is chosen per theme. I clean the rim afterwards, so soft or glowing
          edges are fine.
        - **`window.image` is the only key for panel art.** Do not invent
          another place for it and do not put it under `assets`.
        - **My ✕ and ↔ marks draw themselves** at the ends of the title strip,
          on top of your artwork, so you never need to supply them.

        Each of these is a line in the manifest and I can change any of them
        later. They are defaults, not laws — but do not spend a question on
        them.
        """
    }

    /// The keys that make the drawing above actually behave as a nine-slice.
    ///
    /// Kept beside the measuring rules rather than in the manifest section: the
    /// numbers here are the ones just measured, and a model that has to scroll
    /// to find where they go will invent a place to put them. `assets` is the
    /// place it invents.
    static func manifestBlock(for brief: ThemeBrief) -> String {
        """
        ### The block this needs in `theme.json`

        ```json
        "window": {
          "image": "frame.png",
          "overlay": true,
          "lockAspect": false,
          "mode": "tile",
          "capInsets": { "top": 90, "left": 90, "bottom": 90, "right": 90 },
          "removeBackground": "\(brief.keyColour)"
        },
        "layout": {
          "resize": "free",
          "contentInset": { "top": 90, "left": 90, "bottom": 90, "right": 90 }
        }
        ```

        `lockAspect: false` with `capInsets` set is what makes it a nine-slice.
        Leave `lockAspect` at its default and the caps are ignored entirely —
        the frame simply shrinks, corners and all, and every measurement above
        was wasted.

        Replace all eight numbers with the ones you measured. The values shown
        are a shape to copy, not a suggestion.
        """
    }
}
