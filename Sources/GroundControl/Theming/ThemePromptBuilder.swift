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
    static func prompt(for brief: ThemeBrief) -> String {
        let numbered = [
            brief.wantsBackgroundArt ? choices(for: brief) : "",
            artwork(for: brief),
            brief.wantsBackgroundArt
                ? ThemePromptText.backgroundSection(
                    key: brief.keyColour,
                    ninegrid: brief.frame == .ninegrid
                )
                : "",
            brief.wantsBackgroundArt ? ThemePromptText.shapeSection(key: brief.keyColour) : "",
            manifestSection(for: brief),
            installation(for: brief)
        ].filter { !$0.isEmpty }

        // Numbered here rather than written into each section: sections are
        // optional, and hand-numbered headings drift the moment one is skipped.
        let body = numbered.enumerated().map { index, section in
            section.replacingOccurrences(of: "## ", with: "## \(index + 1). ", options: [], range:
                section.range(of: "## "))
        }

        return ([ThemePromptText.preamble, request(for: brief)]
                + body
                + [ThemePromptText.paletteReference])
            .joined(separator: "\n\n")
    }

    // MARK: - Sections

    private static func request(for brief: ThemeBrief) -> String {
        """
        ## What I want

        - **Theme name:** \(brief.name)
        - **Character / mascot:** \(brief.subject)
        - **Visual style:** \(brief.style)
        - **Mood and colours:** \(brief.mood)
        - **Animation:** \(brief.wantsAnimation ? "yes, animate the working state" : "no, stills are fine")
        - **Background:** \(brief.wantsBackgroundArt ? brief.background : "none — colours only, skip section 2")
        """
    }

    private static func artwork(for brief: ThemeBrief) -> String {
        let pixels = brief.recommendedPixels
        // Motion is reserved for the two states that are asking for attention.
        // A theme that animates all four is four looping GIFs on screen at all
        // times, and nothing stands out because everything moves.
        let working = brief.wantsAnimation ? "working.gif" : "working.png"
        let needsInput = brief.needsInputFile
        let motion = brief.wantsAnimation ? "animated" : "still"

        let animationNote = brief.wantsAnimation
            ? """


            `\(working)` and `\(needsInput)` must be **animated GIFs** (or APNG):
            8–16 frames, looping seamlessly, roughly 10fps. `.mov` / `.mp4`
            (H.264 or HEVC) also work if you would rather make real video. Do
            **not** produce `.webm` — macOS cannot decode it and the app will
            refuse the file.

            **`idle` and `done` must be still images.** They are the resting
            states, and motion there competes with the two that mean something.
            """
            : ""

        return """
        ## Four avatar images

        One per session state. Use exactly these filenames:

        | file | state | shown when | motion |
        |---|---|---|---|
        | `idle.png` | idle | the session is quiet | still |
        | `\(working)` | working | it is actively running tools | \(motion) |
        | `\(needsInput)` | needsInput | it is blocked and needs me | \(motion) |
        | `done.png` | done | it just finished its turn | still |

        Requirements:

        - Square, **\(pixels)×\(pixels)px**. They display at \(brief.avatarSize)pt, so this
          stays crisp on Retina and if I scale the avatar up later.
        - PNG with transparency, unless the design wants a solid tile.
        - They sit on a dark panel, so avoid dark-on-dark and thin outlines.

        ### Each state must be obvious at \(brief.avatarSize)pt

        This is the whole job of these images. At that size a face is a few dozen
        pixels and its expression is unreadable, so **the state has to be carried
        by colour and shape, not by acting**:

        | state | read it as | carry it with |
        |---|---|---|
        | idle | resting, nothing wanted | dim, cool, low contrast — it should recede |
        | working | busy, leave it alone | motion, and a cool blue or cyan cast |
        | needsInput | **stop and look** | warm alarm colour, highest contrast of the four, plus a symbol |
        | done | finished well | a settled green, calm but bright |

        The one that matters is `needsInput`: I should notice it from across the
        room without reading anything. Give it the boldest silhouette, the
        brightest background, or a mark — anything that survives being small.

        Squint at each image at \(brief.avatarSize)pt. If two of them look alike, the
        difference is in detail I cannot see, and the colour or shape has to do
        more work.\(animationNote)
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
        \(brief.wantsBackgroundArt ? ThemeFramePrompt.keys(for: brief) : "")
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
    static func choices(for brief: ThemeBrief) -> String {
        let frame = brief.frame == .ninegrid
            ? "**nine-grid** — corners hold their size, edges repeat, so the panel can be dragged to any shape"
            : "**one picture, scaled** — the whole frame shrinks and grows together, keeping its proportions"

        return """
        ## Two things that govern everything below

        **Frame:** \(frame).

        **Key colour: `\(brief.keyColour)`.** Fill every pixel that is not
        artwork with exactly this colour — the surround, and the middle too if
        the frame is drawn in front. I remove it on load. Never use it, or
        anything near it, inside the art itself: that is why it is chosen per
        theme rather than fixed.
        """
    }

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
