// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The `theme.json` a new theme starts from.
///
/// Split out of `ThemePromptBuilder` because emitting JSON and writing prose
/// for a model are different jobs that happened to share a file: this one is
/// judged by whether it parses, the other by whether it reads. The prompt
/// embeds this text and `ThemeScaffold` writes the same string to disk, so
/// what the author is told to produce and what is waiting in the folder cannot
/// drift apart.
enum ThemeStarterManifest {
    /// The manifest the app writes into a freshly created theme folder, and the
    /// same text embedded in the prompt so the two cannot drift.
    static func text(for brief: ThemeBrief) -> String {
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
              "needsInput": { "image": "\(brief.needsInputFile)" },
              "done":       { "image": "done.png" }
            }
          },

          "layout": {
            "rowMaxHeight": 100,
            "marqueeOnOverflow": true,
            "density": "comfortable"
          },

          "matrix": {
            "messages": [\(messageList(for: brief))]
          }
        }
        """
    }

    /// The words the analyser spells, always present in the manifest even when
    /// the author gave none.
    ///
    /// An empty array left in the file is the point: it is the only way anyone
    /// finds out the display can be given something to say. A key that appears
    /// only when used teaches nobody.
    private static func messageList(for brief: ThemeBrief) -> String {
        guard !brief.words.isEmpty else { return "" }
        return "\n" + brief.words.map { "      \"\(escaped($0))\"" }.joined(separator: ",\n") + "\n    "
    }

    /// JSON-safe, including control characters.
    ///
    /// Escaping only quotes and backslashes left a newline in a theme name
    /// producing a manifest that does not parse — and that file is written
    /// straight into the scaffolded folder, so the author starts from something
    /// broken.
    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n", "\r": result += " "
            case "\t": result += " "
            default:
                // Anything else below space would also be illegal unescaped.
                if let scalar = character.unicodeScalars.first, scalar.value < 0x20 {
                    result += " "
                } else {
                    result.append(character)
                }
            }
        }
        return result
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
