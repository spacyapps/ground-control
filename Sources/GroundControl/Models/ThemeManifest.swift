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
        }

        init(image: String?, mode: String? = nil, capInsets: Insets? = nil) {
            self.image = image
            self.mode = mode
            self.capInsets = capInsets
        }
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
