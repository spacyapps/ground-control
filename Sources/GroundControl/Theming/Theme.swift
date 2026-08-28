// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import MatrixKit

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
    /// Manifest metadata, surfaced in Settings so a picked theme can say who
    /// made it and what it is — the folder name alone is a poor label.
    var author: String?
    var summary: String?
    /// Things wrong with the theme that it cannot fix for itself, in plain
    /// words, shown in Settings. A theme that silently does nothing is the
    /// worst outcome — this is how it says what happened instead.
    var warnings: [String] = []
    var colors: Colors
    var layout: Layout
    var typography: Typography
    var avatar: Avatar
    var matrix: Matrix
    var window: Window
    var backgrounds: Backgrounds
    var cornerDecorations: CornerDecorations = .none
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

    /// A shaped panel: the silhouette comes from an image rather than from a
    /// rectangle. Nothing is shaped unless a theme asks — `shape` nil keeps the
    /// ordinary window, which is what every existing theme gets.
    struct Window: Equatable {
        var shape: BackgroundImage?
        /// Keeps the artwork's proportions: the panel is scaled as one piece
        /// and rows scroll inside it.
        ///
        /// You can preserve the artwork's shape or fit the content, never
        /// both — eight rows of square art would be as wide as it is tall.
        /// Locked, width drives and the list scrolls; unlocked, the panel
        /// grows with sessions and the art is sliced to follow.
        var locksAspect: Bool
        /// Width ÷ height of the artwork.
        var aspectRatio: CGFloat
        /// Drawn over the rows rather than behind them. The frame then hides
        /// whatever it overlaps, so the content needs no pixel-accurate fit to
        /// the opening — at the cost of requiring a transparent centre.
        var drawsOverContent: Bool = false
        /// The artwork's own width in pixels.
        ///
        /// A locked skin is scaled bodily to the panel, so the frame painted
        /// into it is thick in proportion to the image, not in points. Insets
        /// have to be scaled by the same amount or they mean something
        /// different on every panel width.
        var naturalWidth: CGFloat = 0

        var isShaped: Bool { shape != nil }

        /// The smallest panel this artwork can be drawn into.
        ///
        /// Nine-slice caps are points, drawn 1:1 — a panel narrower than
        /// `left + right` has nowhere to put its two corners, and AppKit
        /// resolves that by squashing them into each other. The frame stops
        /// looking like a frame well before that, so the floor is the caps.
        ///
        /// Zero for everything else: stretched and bodily-scaled art have no
        /// size they stop working at.
        var minimumPanelSize: NSSize {
            guard let caps = shape?.capInsets else { return .zero }
            return NSSize(width: caps.left + caps.right, height: caps.top + caps.bottom)
        }

        static let standard = Window(shape: nil, locksAspect: false, aspectRatio: 1)

        /// How much the artwork is scaled when drawn `width` points wide.
        /// 1 when the art is not scaled bodily — nine-slice draws its corners
        /// at natural size, so there points and artwork pixels agree.
        func artworkScale(atPanelWidth width: CGFloat) -> CGFloat {
            guard locksAspect, isShaped, naturalWidth > 0 else { return 1 }
            return width / naturalWidth
        }
    }

    /// The title-bar analyser. Its colours were derived from the row palette,
    /// which meant a theme could restyle every row and still get a stock meter.
    struct Matrix {
        /// Bars ramp from `low` at the floor to `high` at the ceiling.
        var low: NSColor
        var high: NSColor
        /// Replaces the whole ramp while something needs you.
        var alarm: NSColor
        /// Cells below the current level — the visible grid.
        var unlit: NSColor
        /// Letters of a sweeping message.
        var text: NSColor
        /// The mark that hangs above a falling bar.
        var peak: NSColor
        /// What the display spells. Empty means the built-in phrases.
        var messages: [String]
        /// The Tier-1 feel knobs, already resolved to numbers
        /// (docs/MATRIX-CUSTOMISATION.md). `.standard` is today's analyser.
        var feel: MatrixFeel.Resolved = .standard
        /// Which built-in shapes rotate. All eight unless a theme narrowed it.
        var patterns: [VisualizerPattern] = VisualizerPattern.allCases
        /// Per-state bar formulas, each nil unless it parsed
        /// (docs/MATRIX-CUSTOMISATION.md). `working` replaces the pattern
        /// rotation; `needsInput` is the strobe that seizes the meter for the
        /// escalation window; `done` is the decaying flourish overlay; `idle`
        /// is the resting texture. A nil state falls back to today's behaviour
        /// for it — rotation, flat-with-lit-floor, no flourish, sleep.
        var workingShape: PatternFormula?
        var needsInputShape: PatternFormula?
        var doneShape: PatternFormula?
        var idleShape: PatternFormula?

        /// The same analyser in somebody's own colour.
        ///
        /// Only the ramp moves. `alarm` is left alone because red is the one
        /// thing in the panel that has to keep meaning what it means, and
        /// `unlit` is the dark grid the bars sit in rather than part of them.
        ///
        /// The bottom of the ramp is derived rather than asked for: a single
        /// colour is the whole point of the control, and two pickers to get one
        /// gradient right is a worse deal than a sensible darkening.
        func tinted(_ colour: NSColor) -> Matrix {
            var tinted = self
            tinted.high = colour
            tinted.low = colour.blended(withFraction: 0.55, of: .black) ?? colour
            tinted.peak = (colour.blended(withFraction: 0.6, of: .white) ?? colour)
                .withAlphaComponent(0.75)
            // The sweeping word belongs to the display, not to the theme it is
            // sweeping across: left alone, a green message crossed magenta bars
            // and read as two unrelated things. Lightened rather than matched,
            // because letters the same colour as the bars disappear into them —
            // all that would distinguish the word is the dent it makes.
            tinted.text = colour.blended(withFraction: 0.72, of: .white) ?? colour
            return tinted
        }
    }

    /// How the panel may be resized.
    ///
    /// A skin and a container want opposite things: a picture frame is a
    /// designed object whose proportions are the point, while a plain panel is
    /// a list that should grow with what is in it. Neither is right for a
    /// person who simply wants the window a particular size.
    enum Resize: String {
        /// Height follows the rows. Drag the width; the panel grows and
        /// shrinks with your sessions.
        case content
        /// Height follows the artwork's proportions. Drag the width; the rows
        /// scroll inside rather than stretching the picture.
        case aspect
        /// Both are yours. The panel stays where you put it and the rows
        /// scroll.
        case free
    }

    struct Layout {
        /// Holds the rows away from the panel edge. A background that draws a
        /// frame is invisible without this: rows span the full width, so they
        /// cover exactly the border the artwork lives in.
        var resize: Resize = .content
        var contentInset: NSEdgeInsets
        /// Corner radius of the content block, in the same artwork pixels as
        /// `contentInset` — a framed opening is rounded in the art, so this is
        /// measured off the art and scaled with it.
        var contentCornerRadius: CGFloat = 0
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
