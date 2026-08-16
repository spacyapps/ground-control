// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The ✕, as a view the panel owns rather than something inside the title bar.
///
/// It used to live in the title strip, which put it under any skin drawn in
/// front and under the artwork whenever a theme tucked its content behind the
/// frame. A decoration that can hide the only way to close the window is a bad
/// trade, however good it looks — so the two marks sit above everything,
/// including the overlay: **marks, then frame, then panel.**
final class CloseMarkView: CornerMarkView {
    var onClose: (() -> Void)?

    override var hint: String { "Hide" }
    override var glyph: String { "\u{2715}" }
    override var markCursor: NSCursor { .pointingHand }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClose?()
    }
}
