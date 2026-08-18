// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The panel's own resize handle.
///
/// A shaped theme is `.borderless`, which costs the system resize control, and
/// nothing replaced it — so a skinned panel was stuck at whatever size it
/// opened at. Even with the control back, a themed edge is the wrong place to
/// grab: `layout.contentInset` can hold the artwork 75pt clear of the real
/// window edge, so the frame the mouse would find is nowhere near the hull you
/// can see.
///
/// So the handle lives inside the content, on the visible surface, and moves
/// the window itself.
final class ResizeGripView: CornerMarkView {
    /// Reports the drag as a distance from where it started, in screen points.
    /// Absolute rather than incremental so a drag that outruns the clamp still
    /// tracks the pointer on the way back.
    var onResize: ((CGSize) -> Void)?
    var onResizeBegan: (() -> Void)?

    private var start: NSPoint = .zero

    /// Whether a vertical drag means anything. In the other two modes the
    /// height is derived — from the rows, or from the artwork — so offering it
    /// would promise a drag that snaps back the moment it ends.
    private var allowsVertical: Bool { theme.layout.resize == .free }

    // Bigger than the close mark, and its own box to draw it in. An arrow is
    // thin strokes and a lot of nothing, so at the ✕'s eleven points it read as
    // a speck — and unlike the ✕, it is the *only* way to resize a shaped
    // panel, so it has to be findable.
    //
    // swiftlint:disable static_over_final_class
    override class var size: NSSize { NSSize(width: 26, height: 26) }
    override class var glyphPointSize: CGFloat { 19 }
    // swiftlint:enable static_over_final_class

    override var hint: String { "Resize" }

    /// The glyph is a promise about what the drag does: sideways where only the
    /// width is yours, diagonal where the panel is free.
    override var glyph: String { allowsVertical ? "\u{2921}" : "\u{2194}" }

    /// No public cursor for a corner resize, so the closest honest thing: both
    /// directions when both are live, sideways when only width is.
    override var markCursor: NSCursor { allowsVertical ? .crosshair : .resizeLeftRight }

    override func mouseDown(with event: NSEvent) {
        // Screen coordinates, because the window is about to move under us and
        // anything window-relative would drift by exactly what we changed.
        start = NSEvent.mouseLocation
        onResizeBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        onResize?(NSSize(
            width: now.x - start.x,
            // Screen coordinates run upward and a panel grows downward, so
            // dragging down has to read as taller.
            height: allowsVertical ? start.y - now.y : 0
        ))
    }
}
