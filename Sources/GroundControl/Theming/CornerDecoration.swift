// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

extension Theme {
    /// Art fixed to one corner of the panel — sized off its own pixels, never
    /// sliced, drawn above the frame and below the close and resize marks.
    ///
    /// `image` reuses `BackgroundImage` purely to share its decode/cache/key
    /// machinery with everything else that draws a themed picture — `mode` and
    /// `capInsets` on that value are meaningless here and always resolved to
    /// `.center` / zero by `AssetResolver`, never something a theme author
    /// writes for this block.
    struct CornerDecoration: Equatable {
        enum Asset: Equatable {
            /// One image, or several the corner plays through and loops while
            /// working — see `DecorationSequence`. Never empty.
            case image([BackgroundImage])
            case video(URL, loop: Bool, muted: Bool)
        }

        var asset: Asset
        /// Screen direction from this corner's own point: x right, y down,
        /// the same meaning at every corner. Measured against the *scaled*
        /// size, so it still means "from the corner" at any scale.
        var offset: CGSize
        /// Multiplies the artwork's own pixel size. 1 is the file's real
        /// size — trying a different size is a number to change, not a new
        /// image to generate.
        var scale: CGFloat = 1
    }

    /// One optional slot per corner. Named properties rather than a
    /// dictionary keyed by a `Corner` enum — there is no other use for such an
    /// enum anywhere else in the app, and `Backgrounds` already sets the
    /// precedent for a small fixed set of independent optional slots.
    struct CornerDecorations: Equatable {
        var topLeft: CornerDecoration?
        var topRight: CornerDecoration?
        var bottomLeft: CornerDecoration?
        var bottomRight: CornerDecoration?

        static let none = CornerDecorations()

        var isEmpty: Bool {
            topLeft == nil && topRight == nil && bottomLeft == nil && bottomRight == nil
        }
    }
}
