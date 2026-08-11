// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// A theme with every value present — the thing the UI actually reads.
///
/// Built by layering a `ThemeManifest` over `DefaultTheme`, so the UI never
/// deals in optionals and a theme that sets one colour still works.
struct Theme {
    /// Manifests carry plain numbers; the UI wants CGFloat. Spelled out rather
    /// than `.map(CGFloat.init)`, which the type checker cannot resolve inside
    /// a multi-argument initialiser.
    static func length(_ value: Double?, _ fallback: CGFloat) -> CGFloat {
        guard let value else { return fallback }
        return CGFloat(value)
    }

    var name: String
    var colors: Colors
    var layout: Layout
    var typography: Typography
    var avatar: Avatar
    var backgrounds: Backgrounds
    /// Folder the manifest was loaded from; asset paths resolve against it.
    var folder: URL?

    /// The per-state face. A theme may set any subset of states; an omitted
    /// state falls back to the drawn built-in, keeping with the rule that
    /// every key has a code default (docs/THEMING.md). Set `size` to 0 to turn
    /// avatars off entirely.
    struct Avatar {
        var size: CGFloat
        var position: Position
        var cornerRadius: CGFloat
        var states: [SessionState: Asset]

        enum Position: String {
            case left
            case right
        }

        /// An author picks *either* an image or a video per state, by setting
        /// whichever key they want — the manifest has no "kind" field.
        enum Asset: Equatable {
            /// Still or animated (`.gif` / `.apng`); AppKit animates both.
            case image(URL)
            case video(URL, loop: Bool, muted: Bool)

            var url: URL {
                switch self {
                case .image(let url): return url
                case .video(let url, _, _): return url
                }
            }
        }

        /// The one way to opt out of avatars completely.
        var isHidden: Bool { size <= 0 }

        /// `nil` means "no theme artwork for this state" — the caller draws the
        /// built-in instead.
        func asset(for state: SessionState) -> Asset? { states[state] }
    }

    struct Colors {
        var windowBackground: NSColor
        var titleBarBackground: NSColor
        var titleBarText: NSColor
        var rowBackground: NSColor
        var rowBackgroundAlt: NSColor
        var rowBackgroundHover: NSColor
        var sessionName: NSColor
        var message: NSColor
        var messageDim: NSColor
        var needsAction: NSColor
        var working: NSColor
        var idle: NSColor
        var footerBackground: NSColor
        var footerText: NSColor
        var accent: NSColor
        var divider: NSColor

        /// The accent for a given row state — what the dot and tint use.
        func color(for state: SessionState) -> NSColor {
            switch state {
            case .needsInput: return needsAction
            case .working: return working
            case .done: return accent
            case .idle: return idle
            }
        }
    }

    struct Layout {
        var rowMaxHeight: CGFloat
        var rowPadding: CGFloat
        var marqueeOnOverflow: Bool
        var marqueeSpeed: CGFloat
        var isCompact: Bool
    }

    struct Typography {
        var fontFamily: String?
        var nameSize: CGFloat
        var messageSize: CGFloat
        var nameWeight: NSFont.Weight

        func nameFont() -> NSFont {
            font(size: nameSize, weight: nameWeight)
        }

        func messageFont() -> NSFont {
            font(size: messageSize, weight: .regular)
        }

        private func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
            if let family = fontFamily,
               let custom = NSFont(name: family, size: size) {
                return custom
            }
            return .systemFont(ofSize: size, weight: weight)
        }
    }
}
