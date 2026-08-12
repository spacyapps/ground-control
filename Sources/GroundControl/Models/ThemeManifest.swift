// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// A decoded `theme.json`. Pure data — no AppKit, per the layering rule in
/// docs/STRUCTURE.md.
///
/// **Everything is optional.** A theme overrides only what it sets and an empty
/// `{}` is valid; code defaults fill the rest (docs/THEMING.md). That is why
/// every property here is an Optional rather than carrying its own default —
/// "absent" and "explicitly set" must stay distinguishable so merging works.
struct ThemeManifest: Decodable, Equatable {
    var manifestVersion: Int?
    var name: String?
    var author: String?
    var description: String?
    var colors: [String: String]?
    var assets: [String: Asset?]?
    var avatar: Avatar?
    var window: Window?
    var matrix: Matrix?
    var layout: Layout?
    var typography: Typography?

    /// A background image. Accepts either a bare filename — `"panel.png"`,
    /// meaning "just tile it" — or an object carrying the resize behaviour.
    ///
    /// The panel resizes in both axes, so the interesting case is nine-slice:
    /// `capInsets` marks corners that must never scale, leaving the edges and
    /// centre to fill. Three-slice is the same thing with `left`/`right` at 0.
    struct Asset: Decodable, Equatable {
        var image: String?
        var mode: String?
        var capInsets: Insets?
        /// Same meaning as `window.removeBackground`. A generated background
        /// arrives with a flat colour behind it as often as a skin does, and
        /// leaving it out here meant a theme that reached for the wrong key had
        /// no way at all to get transparency.
        var removeBackground: String?

        struct Insets: Decodable, Equatable {
            var top: Double?
            var left: Double?
            var bottom: Double?
            var right: Double?
        }

        private enum CodingKeys: String, CodingKey {
            case image
            case mode
            case capInsets
            case removeBackground
        }

        init(from decoder: Decoder) throws {
            if let filename = try? decoder.singleValueContainer().decode(String.self) {
                image = filename
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            image = try container.decodeIfPresent(String.self, forKey: .image)
            mode = try container.decodeIfPresent(String.self, forKey: .mode)
            capInsets = try container.decodeIfPresent(Insets.self, forKey: .capInsets)
            removeBackground = try container.decodeIfPresent(String.self, forKey: .removeBackground)
        }

        init(image: String?, mode: String? = nil, capInsets: Insets? = nil) {
            self.image = image
            self.mode = mode
            self.capInsets = capInsets
        }
    }

    /// Turns the panel into a shaped window: the image's alpha becomes the
    /// window's silhouette, so art can spill past what would have been the
    /// rectangle and transparent areas are see-through *and* click-through.
    struct Window: Decodable, Equatable {
        /// The skin. `shape` is accepted as an older spelling.
        var image: String?
        var shape: String?

        /// Keep the artwork's proportions.
        ///
        /// Locked, the panel is scaled as one piece and rows scroll inside it —
        /// nothing is ever sliced, which is where every distortion came from.
        /// Unlocked, the panel grows with the session count and the artwork is
        /// nine-sliced to follow.
        var lockAspect: Bool?

        /// How to get transparency out of what an image model produced:
        /// "auto", "checkerboard", or a hex colour to key out.
        var removeBackground: String?

        /// Only meaningful when the aspect is unlocked, since a locked skin is
        /// never sliced.
        var mode: String?
        var capInsets: Asset.Insets?

        var file: String? { image ?? shape }
    }

    /// The title-bar analyser: its palette, and what it says.
    struct Matrix: Decodable, Equatable {
        var low: String?
        var high: String?
        var alarm: String?
        var unlit: String?
        var text: String?
        var peak: String?
        /// Replaces the built-in phrases. A theme is a character; this is how
        /// it speaks. Words the font cannot draw are dropped rather than
        /// rendered as gaps.
        var messages: [String]?
    }

    struct Avatar: Decodable, Equatable {
        var size: Double?
        var position: String?
        var cornerRadius: Double?
        var states: [String: State]?

        struct State: Decodable, Equatable {
            var image: String?
            var video: String?
            var loop: Bool?
            var muted: Bool?
        }
    }

    struct Layout: Decodable, Equatable {
        var contentInset: Double?
        /// Rounds the block the rows sit in, so a skin with a rounded opening
        /// does not frame a square-cornered screen.
        var contentCornerRadius: Double?
        var rowMaxHeight: Double?
        var rowPadding: Double?
        var marqueeOnOverflow: Bool?
        var marqueeSpeed: Double?
        var density: String?
    }

    struct Typography: Decodable, Equatable {
        var fontFamily: String?
        var nameSize: Double?
        var messageSize: Double?
        var nameWeight: String?
    }

    static let empty = ThemeManifest()
}
