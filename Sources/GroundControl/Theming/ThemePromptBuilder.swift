// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Builds a paste-into-an-LLM prompt that produces a complete theme.
///
/// The prompt carries the manifest schema in full, because a vague request
/// gets back plausible-looking JSON with invented keys. Spelling out the
/// filenames, the four states and the format rules is what makes the result
/// drop straight into the folder and work.
enum ThemePromptBuilder {
    /// Both parts joined, for anywhere that wants the whole brief as one
    /// document. Not what the theme folder gets — that gets two files, because
    /// one file gets pasted whole.
    static func prompt(for brief: ThemeBrief) -> String {
        [partOne(for: brief), "---", partTwo(for: brief)].joined(separator: "\n\n")
    }

    /// **Part one: the four moods.** What gets pasted first, and often all
    /// somebody needs — a theme is perfectly good with faces and no frame.
    ///
    /// Split from the frame because a model reading the frame instructions in
    /// the same paste is a model thinking about the frame, however firmly it has
    /// been told to work in stages. A shorter first paste is also less
    /// intimidating: the whole prompt is long enough to look like homework.
    static func partOne(for brief: ThemeBrief) -> String {
        let body = [artwork(for: brief), handBackMoods(for: brief)]
            .filter { !$0.isEmpty }
        return ([ThemePromptText.preamble, request(for: brief), ThemePromptText.howWeWork,
                 ThemePromptText.questions(for: brief)] + body)
            .joined(separator: "\n\n")
    }

    /// **Part two: the frame and the manifest.** Pasted once the moods are
    /// settled, into the same conversation, so the model already knows the
    /// character it is framing.
    static func partTwo(for brief: ThemeBrief) -> String {
        // The frame comes before the manifest: the questions must be asked
        // before anything is drawn, and a JSON block above them reads as
        // permission to start.
        let frame = brief.wantsBackgroundArt ? ThemeFramePrompt.sections(for: brief) : []
        let numbered = (frame + [
            manifestSection(for: brief),
            installation(for: brief)
        ]).filter { !$0.isEmpty }

        // Numbered here rather than written into each section: sections are
        // optional, and hand-numbered headings drift the moment one is skipped.
        let body = numbered.enumerated().map { index, section in
            section.replacingOccurrences(of: "## ", with: "## \(index + 1). ", options: [], range:
                section.range(of: "## "))
        }
        return ([ThemeFramePrompt.header]
                + body
                + [ThemePromptText.paletteReference]).joined(separator: "\n\n")
    }

    /// How part one ends: hand the images over and stop.
    private static func handBackMoods(for brief: ThemeBrief) -> String {
        """
        ## Hand the moods back

        Give me the four files, named exactly as above. Then stop — the panel's
        own artwork is a separate conversation, and I will paste it when these
        are right.
        """
    }

    // MARK: - Sections

    private static func request(for brief: ThemeBrief) -> String {
        """
        ## What I want

        - **Theme name:** \(brief.name)
        - **Character / mascot:** \(brief.subject)
        - **Visual style:** \(brief.style)
        - **Mood and colours:** \(brief.mood)
        - **Animation:** \(brief.wantsAnimation
            ? "yes — working and needs-input both move; idle and done stay still"
            : "no, stills are fine")
        - **Background:** \(brief.wantsBackgroundArt ? brief.background : "none — colours only, skip section 2")
        \(brief.hasReferenceImage ? referenceNote : "")
        """
    }

    /// Said in the brief rather than further down, because it changes what the
    /// model should do first: look, rather than imagine.
    private static let referenceNote = """

        **I am attaching a picture of the character.** Work from it rather than
        from my description — the words above are only there to fill in what a
        single image cannot say. Derive all four moods from that one source so
        they look like the same character in four states, which is the thing
        four separately-imagined faces always get wrong.
        """

    private static func artwork(for brief: ThemeBrief) -> String {
        let pixels = brief.recommendedPixels
        // Motion is reserved for the two states that are asking for attention.
        // A theme that animates all four is four looping GIFs on screen at all
        // times, and nothing stands out because everything moves.
        let working = brief.wantsAnimation ? "working.gif" : "working.png"
        let needsInput = brief.needsInputFile
        let motion = brief.wantsAnimation ? "animated" : "still"

        let animationNote = motionRules(for: brief)

        return """
        ## The four moods

        One per session state — idle, working, needs you, done. Use exactly
        these filenames:

        | file | state | shown when | motion |
        |---|---|---|---|
        | `idle.png` | idle | the session is quiet | still |
        | `\(working)` | working | it is actively running tools | \(motion) |
        | `\(needsInput)` | needsInput | it is blocked and needs me | \(motion) |
        | `done.png` | done | it just finished its turn | still |

        Requirements:

        - Square. **\(brief.avatarSize * 2)px is the floor** — that is one image
          pixel per screen pixel at \(brief.avatarSize)pt on Retina, and the
          shipped station theme is drawn at exactly that. **\(pixels)px** gives
          headroom if I scale the avatar up later. More than that is weight for
          nothing.
        - PNG. **Decide once, for all four: transparent, or a solid tile.**
          Transparent lets the panel's own colour show through and suits a
          character with a clear outline; a tile lets each mood carry its own
          background colour, which is often the easiest way to make the four
          differ at a glance. Mixing them makes the set look broken. Say which
          you chose.
        - They sit on a dark panel, so avoid dark-on-dark and thin outlines.

        \(sizeRules(for: brief))

        ### Each state must be obvious at \(brief.avatarSize)pt

        This is the whole job of these images. At that size a face is a few dozen
        pixels and its expression is unreadable, so **the state has to be carried
        by colour and shape, not by acting**:

        \(ThemePromptText.moodColours)

        **`needsInput` red is the one thing not to negotiate.** Every other
        choice here is yours to argue with; this one carries the entire point of
        the app. If a theme's palette really cannot hold red, say so before you
        draw rather than quietly substituting orange — and expect me to move the
        other three to make room.

        The one that matters is `needsInput`: I should notice it from across the
        room without reading anything. Give it the boldest silhouette, the
        brightest background, or a mark — anything that survives being small.

        \(avatarChecks(for: brief))\(animationNote)
        """
    }

    /// What the model can verify without me, before it spends my time.
    ///
    /// An instruction that cannot be self-checked gets followed approximately.
    /// A test gets followed exactly — which is why every one of these is a
    /// question with a yes or no answer, judged at the size it will be seen at.
    private static func avatarChecks(for brief: ThemeBrief) -> String {
        """
        ### Check these before you show me anything

        - Shrunk to \(brief.avatarSize) pixels, can you still tell what each one is?
        - Side by side at that size, are all four instantly different from each
          other? If two look alike, the difference is in detail I cannot see.
        - Is `needsInput` the one your eye goes to first?
        - Are they square, the same size, and on a transparent or solid tile —
          no white boxes?

        Then show me all four together, shrunk to \(brief.avatarSize) pixels, and
        wait.
        """
    }

    /// Why the artwork has to be simple, not merely distinguishable.
    ///
    /// The rest of this prompt tells a model how to make the four states differ
    /// from one another. It never said "draw plainly", so a model would return a
    /// gorgeous detailed portrait that turns to grey mush at avatar size — the
    /// image is generated large and drawn tiny, and detail that cannot be seen
    /// does not politely disappear.
    /// The motion half of the avatar brief, and only when motion was asked for.
    ///
    /// Split out because it is long and conditional, and because the staging
    /// advice at the end is the part that saves an author the most work: the
    /// mistakes all live in the still, and animating first means paying for
    /// every one of them twice.
    private static func motionRules(for brief: ThemeBrief) -> String {
        guard brief.wantsAnimation else { return "" }
        let working = "working.gif"
        let needsInput = brief.needsInputFile
        return """





        `\(working)` and `\(needsInput)` must be **animated GIFs** (or APNG):
        8–24 frames, looping seamlessly, roughly 10fps — a guide, not a cap.
        The shipped station theme uses 20 on its alarm. More frames is more
        drift and a larger file, which is the only reason the number matters. `.mov` / `.mp4`
        (H.264 or HEVC) also work if you would rather make real video. Do
        **not** produce `.webm` — macOS cannot decode it and the app will
        refuse the file.

        **`idle` and `done` must be still images.** They are the resting
        states, and motion there competes with the two that mean something.

        **Work in two passes, and stop between them.** First draw all four as
        **stills** and show me them together, shrunk to \(brief.avatarSize)
        pixels so we are judging what I will actually see. Wait for me to say
        they are right. Only then animate the two that move.

        Animation is the expensive half and it is the half that cannot be
        repaired: a silhouette or a colour that reads wrong costs one still to
        fix now, and every frame to fix later.

        **And it is expensive literally.** Every frame is a separate generated
        image. A 16-frame loop for two states is 32 images, not two — an order
        of magnitude more than the four stills I have just approved, in both
        time and tokens.

        So once the stills are right, do not start animating. Tell me **the
        number** — frames × the two states — and ask me:

        > **Generate N images for the animation, or keep the stills?**

        Then wait. Approving the stills was not permission to animate; this is a
        separate yes. Four good stills are a complete theme, and if I say keep
        them, write the manifest against them without arguing.

        \(ThemePromptText.frameCraft(size: brief.avatarSize))
        """
    }

    private static func sizeRules(for brief: ThemeBrief) -> String {
        """
        ### Draw for the size — do not shrink a detailed picture

        These are generated large and drawn at **\(brief.avatarSize)pt**, roughly a
        favicon. Detail that cannot be seen there does not politely disappear; it
        turns to grey mush. Fine linework, small facial features, texture,
        gradients spanning a few pixels and thin outlines all read as dirt at
        display size, and no amount of resolution fixes it.

        You will draw large — that is how these are generated. So the rule is not
        "compose at 48 pixels", which nothing can actually do; it is **shrink it
        to \(brief.avatarSize) pixels and look, before you show me anything, and
        redraw whatever turns to mud.** In practice that means:

        - **The state lives in a colour wash and one big mark** — not in acting,
          and not in detail. A fully rendered character is fine, as long as
          nothing about the *state* depends on features nobody can see. The
          shipped station theme is a detailed portrait that works for exactly
          this reason: each tile is a colour field plus one unmissable mark.
        - **Flat colour over gradient**, with strong contrast between neighbouring
          areas.
        - **No fine pattern, no jewellery-scale detail.** A single large glyph is
          not detail — the station's idle tile is three enormous Zs, and they are
          the thing you read at \(brief.avatarSize)pt. Small lettering is what to
          avoid, not lettering.
        - **A readable silhouette** — filled in solid black, it should still be
          recognisable. This is about shape, not about drawing an outline; a
          style with no outlines can still have a strong silhouette.

        Test it before you send it: shrink the image to \(brief.avatarSize) pixels
        and look. If you cannot tell what it is, it is too busy.

        **If something I asked for cannot survive that size, drop it and tell me
        you dropped it.** A desk, a texture, a small prop — better gone than
        rendered as three grey pixels. Silently omitting it is the only wrong
        answer.
        """
    }

    private static func manifestSection(for brief: ThemeBrief) -> String {
        """
        ## `theme.json`

        Produce it in exactly this shape, replacing the colour values to match the
        artwork. Keep the filenames consistent with the images above.

        ```json
        \(ThemeStarterManifest.text(for: brief))
        ```

        **Rules for the JSON:** no comments, no trailing commas, it must parse
        as strict JSON, and only include keys you are actually setting.

        Notes:

        - `manifestVersion` is `1`.
        - Colours are `#rrggbb` or `#rrggbbaa`. An invalid or omitted colour falls
          back to the built-in value rather than failing.
        - `avatar.position` is `left` or `right`; `avatar.size` is in points.
        - Use the `image` key for stills **and** animated GIF/APNG. Use `video`
          only for `.mov` / `.mp4`. If both are set, video wins.
        - Omit any state you do not want to draw and the app's own drawn face is
          used for it, tinted from this palette.
        \(matrixNote(for: brief))
        """
    }

    /// Either "keep what the author wrote" or "write some yourself", but always
    /// an explanation of the display, because the model has no other way to know
    /// the panel has a 3×5 LED sign in it.
    private static func matrixNote(for brief: ThemeBrief) -> String {
        let shared = """
        - `matrix.messages` is what the panel's little LED display spells while \
        nothing is happening. **Only A–Z, 0–9, space and `. - !`** — no accents, \
        no other punctuation — and **13 characters maximum** per phrase. \
        Anything else is dropped when the theme loads.
        """
        guard brief.words.isEmpty else {
            return shared + "\n  Keep the phrases exactly as written above."
        }
        return shared + """

          Write 8–10 of them in this theme's voice: things \(brief.subject) \
        would say. Short, dry, and in keeping with the mood — not instructions \
        to the user.
        """
    }

    /// Stated once, near the top, because both facts govern every image the
    /// author is about to draw.
    private static func installation(for brief: ThemeBrief) -> String {
        """
        ## How to hand it back

        Give me the four image files and the `theme.json` contents. I will drop them
        all into a folder named `\(brief.slug)` inside Ground Control's Themes folder,
        then pick "\(brief.name)" in Settings. Saving `theme.json` afterwards
        re-skins the panel instantly, so iterating is cheap — feel free to suggest
        tweaks once I tell you how it looks.
        """
    }
}
