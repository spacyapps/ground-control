import AppKit

/// A theme with every value present — the thing the UI actually reads.
///
/// Built by layering a `ThemeManifest` over `DefaultTheme`, so the UI never
/// deals in optionals and a theme that sets one colour still works.
struct Theme {
    var name: String
    var colors: Colors
    var layout: Layout
    var typography: Typography
    var avatar: Avatar
    /// Folder the manifest was loaded from; asset paths resolve against it.
    var folder: URL?

    /// The per-state face. A theme may set any subset of states; an omitted
    /// state draws nothing at all, leaving the dot and colours to carry the
    /// meaning (docs/THEMING.md).
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

        var isEmpty: Bool { states.isEmpty }

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
