// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// What the author wants, gathered from a few questions in Settings and turned
/// into a prompt for an image-capable LLM.
struct ThemeBrief: Equatable {
    /// The two ways a frame can meet a resize.
    enum Frame: String, CaseIterable {
        /// One picture, scaled as a whole. Any artwork works, nothing to
        /// measure, and the panel keeps the picture's proportions.
        case simple
        /// Nine-grid: corners hold their size while the edges repeat. More to
        /// get right — the corners must contain the ornament and the edges must
        /// tile — and the only kind that survives being dragged to any shape.
        case ninegrid

        static let defaultKey = "#00FF00"

        var title: String {
            switch self {
            case .simple: return "Simple — one picture, scaled to fit"
            case .ninegrid: return "Nine-grid — corners hold, edges repeat"
            }
        }
    }

    var name: String
    var subject: String
    var style: String
    var mood: String
    /// Animates the two states that are asking for attention — working and
    /// needsInput. Idle and done stay still whatever this says: motion there
    /// competes with the states that mean something, and four looping GIFs on
    /// screen at once means nothing stands out.
    var wantsAnimation: Bool
    /// How the frame behaves when the panel is resized. The single most
    /// consequential choice in a theme, and the one an author cannot deduce
    /// from the artwork alone.
    var frame: Frame = .simple
    /// The flat colour filled around — and, for an overlay, behind — the
    /// artwork, which the app keys out on load. It has to be a colour the art
    /// never uses, so it cannot be a fixed one: a green frame keyed on green
    /// erases itself.
    var keyColour: String = Frame.defaultKey
    /// Empty means "colours only" — no background artwork requested.
    var background: String
    var avatarSize: Int
    var position: String
    /// Whether the author has a picture of their character to hand the model.
    ///
    /// Describing a face in words is the worst way to convey one, and it is
    /// where the second round usually comes from. One image, with all four
    /// moods derived from it, also keeps them consistent — which is the thing
    /// four separately-imagined faces always get wrong.
    var hasReferenceImage: Bool = false

    /// What the analyser spells while the panel is quiet. Empty means the model
    /// is asked to invent them in the theme's voice, which is the more likely
    /// path: most authors do not know the display can speak until they see it.
    ///
    /// Already filtered to what the 3×5 font can draw, so nothing unusable
    /// reaches the manifest.
    var words: [String] = []

    static let placeholder = ThemeBrief(
        name: "My Theme",
        subject: "a sleepy robot",
        style: "16-bit pixel art, chunky outlines",
        mood: "warm amber on near-black",
        wantsAnimation: true,
        frame: .simple,
        keyColour: Frame.defaultKey,
        background: "brushed dark metal with a faint scanline texture",
        avatarSize: 48,
        position: "right",
        hasReferenceImage: false,
        words: ["BEEP BOOP", "STILL AWAKE"]
    )

    /// Folder name on disk. Themes are picked by folder, so this has to be a
    /// filename, not a title.
    var slug: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let separators = CharacterSet(charactersIn: " /\\:._")

        // Punctuation becomes a separator rather than vanishing, so "My / Theme"
        // does not collapse into "mytheme"; runs are then squeezed to one dash.
        let cleaned = name
            .lowercased()
            .unicodeScalars
            .map { separators.contains($0) ? "-" : (allowed.contains($0) ? String($0) : "") }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")

        return cleaned.isEmpty ? "my-theme" : cleaned
    }

    /// The needsInput filename, which follows the animation choice like
    /// `working` does — both are the states that are asking for something.
    var needsInputFile: String {
        wantsAnimation ? "needs-input.gif" : "needs-input.png"
    }

    var wantsBackgroundArt: Bool {
        !background.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Rendered at `avatarSize` points on a Retina display, so **2x is the
    /// floor** — 96px for a 48pt avatar is exactly one pixel per screen pixel,
    /// and the shipped station theme is drawn at precisely that and looks
    /// perfect. 4x is headroom for scaling the avatar up later, not a
    /// requirement; asking for it as a minimum was overreach.
    ///
    /// Capped: an avatar size of 9999 would otherwise ask a model for a
    /// 39996px square, which no generator will produce and no panel can use.
    var recommendedPixels: Int {
        min(512, max(192, avatarSize * 4))
    }
}
