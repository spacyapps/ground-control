// SPDX-License-Identifier: GPL-3.0-or-later
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
            artwork(for: brief),
            brief.wantsBackgroundArt ? ThemePromptText.backgroundSection : "",
            brief.wantsBackgroundArt ? ThemePromptText.shapeSection : "",
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
        let working = brief.wantsAnimation ? "working.gif" : "working.png"

        let animationNote = brief.wantsAnimation
            ? """


            `working` must be an **animated GIF** (or APNG): 8–16 frames, looping
            seamlessly, roughly 10fps. `.mov` / `.mp4` (H.264 or HEVC) also work if
            you would rather make real video. Do **not** produce `.webm` — macOS
            cannot decode it and the app will refuse the file.
            """
            : ""

        return """
        ## Four avatar images

        One per session state. Use exactly these filenames:

        | file | state | shown when |
        |---|---|---|
        | `idle.png` | idle | the session is quiet |
        | `\(working)` | working | Claude is actively running tools |
        | `needs-input.png` | needsInput | Claude is blocked and needs me |
        | `done.png` | done | Claude just finished its turn |

        Requirements:

        - Square, **\(pixels)×\(pixels)px**. They display at \(brief.avatarSize)pt, so this
          stays crisp on Retina and if I scale the avatar up later.
        - PNG with transparency, unless the design wants a solid tile.
        - The four must read as the **same character in four moods**, and be
          distinguishable at a glance at \(brief.avatarSize)pt. Silhouette and colour do
          that work — fine detail disappears at this size.
        - They sit on a dark panel, so avoid dark-on-dark and thin outlines.\(animationNote)
        """
    }

    private static func manifestSection(for brief: ThemeBrief) -> String {
        """
        ## `theme.json`

        Produce it in exactly this shape, replacing the colour values to match the
        artwork. Keep the filenames consistent with the images above.

        ```json
        \(starterManifest(for: brief))
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
        \(brief.wantsBackgroundArt ? backgroundKeys : "")
        """
    }

    /// Only shown when a background was asked for, and shows the *same* API the
    /// background sections describe — a JSON example that disagrees with the
    /// prose wins, because it is the concrete thing.
    private static let backgroundKeys = """
        Add this block for the background, with the numbers you chose:

        ```json
        "window": {
          "image": "panel.png",
          "lockAspect": false,
          "removeBackground": "#00FF00",
          "mode": "tile",
          "capInsets": { "top": 100, "left": 100, "bottom": 100, "right": 100 }
        },
        "layout": { "contentInset": 75 }
        ```

        - `lockAspect: false` lets the panel grow with my sessions and slices the
          art to follow, so `mode` and `capInsets` apply. Use `true` instead to
          keep your proportions exactly, with the rows scrolling inside.
        - `removeBackground` must match the flat colour you filled around the
          artwork.
        - Cap insets are drawn 1:1, so **draw at roughly 450px**, not larger. A
          200px corner on a 400px-wide panel leaves no middle.
        - Give `rowBackground` and `rowBackgroundAlt` alpha, or the rows cover
          your artwork completely.
    """

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

    // MARK: - Manifest

    /// The manifest the app writes into a freshly created theme folder, and the
    /// same text embedded in the prompt so the two cannot drift.
    static func starterManifest(for brief: ThemeBrief) -> String {
        let working = brief.wantsAnimation ? "working.gif" : "working.png"
        let defaults = DefaultTheme.colors

        return """
        {
          "manifestVersion": 1,
          "name": "\(escaped(brief.name))",
          "description": "\(escaped(brief.subject)) — \(escaped(brief.style))",

          "colors": {
            "windowBackground":   "\(hex(defaults.windowBackground))",
            "titleBarBackground": "\(hex(defaults.titleBarBackground))",
            "titleBarText":       "\(hex(defaults.titleBarText))",
            "footerBackground":   "\(hex(defaults.footerBackground))",
            "rowBackground":      "\(hex(defaults.rowBackground))",
            "rowBackgroundAlt":   "\(hex(defaults.rowBackgroundAlt))",
            "rowBackgroundHover": "\(hex(defaults.rowBackgroundHover))",
            "sessionName":        "\(hex(defaults.sessionName))",
            "message":            "\(hex(defaults.message))",
            "messageDim":         "\(hex(defaults.messageDim))",
            "needsAction":        "\(hex(defaults.needsAction))",
            "working":            "\(hex(defaults.working))",
            "idle":               "\(hex(defaults.idle))",
            "accent":             "\(hex(defaults.accent))",
            "divider":            "\(hex(defaults.divider))"
          },

          "avatar": {
            "size": \(brief.avatarSize),
            "position": "\(brief.position)",
            "cornerRadius": 8,
            "states": {
              "idle":       { "image": "idle.png" },
              "working":    { "image": "\(working)" },
              "needsInput": { "image": "needs-input.png" },
              "done":       { "image": "done.png" }
            }
          },

          "layout": {
            "rowMaxHeight": 100,
            "marqueeOnOverflow": true,
            "density": "comfortable"
          }
        }
        """
    }

    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Emits `#rrggbbaa` when the colour is not fully opaque. Dropping alpha
    /// would quietly change the design — the default `divider` is transparent,
    /// so a 6-digit value turns invisible hairlines into visible ones.
    private static func hex(_ color: NSColor) -> String {
        guard let srgb = color.usingColorSpace(.sRGB) else { return "#000000" }
        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        let alpha = Int((srgb.alphaComponent * 255).rounded())

        guard alpha < 255 else { return String(format: "#%02x%02x%02x", red, green, blue) }
        return String(format: "#%02x%02x%02x%02x", red, green, blue, alpha)
    }
}
