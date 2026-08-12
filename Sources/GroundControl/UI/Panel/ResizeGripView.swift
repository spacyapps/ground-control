// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The panel's own width handle.
///
/// A shaped theme is `.borderless`, which costs the system resize control, and
/// nothing replaced it — so a skinned panel was stuck at whatever width it
/// opened at. Even with the control back, a themed edge is the wrong place to
/// grab: `layout.contentInset` can hold the artwork 75pt clear of the real
/// window edge, so the frame the mouse would find is nowhere near the hull you
/// can see.
///
/// So the handle lives inside the content, on the visible surface, and moves
/// the window itself. Width only: height is derived from the rows (or from the
/// artwork, when the aspect is locked), so a vertical drag would only snap back.
final class ResizeGripView: NSView {
    /// The close button's size, because it is the close button's twin: one
    /// corner mark top-left, one bottom-right.
    static let size = NSSize(width: 16, height: 16)

    /// Reports the drag as a distance from where it started, in screen points.
    /// Absolute rather than incremental so a drag that outruns the clamp still
    /// tracks the pointer on the way back.
    var onResize: ((CGFloat) -> Void)?
    var onResizeBegan: (() -> Void)?

    private var theme: Theme = DefaultTheme.theme
    private var startX: CGFloat = 0
    private var isHighlighted = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    /// The panel moves when dragged by its background, which would otherwise
    /// swallow this drag before it starts.
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        toolTip = "Drag to resize"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ResizeGripView is created in code only")
    }

    func apply(theme: Theme) {
        self.theme = theme
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        // Screen coordinates, because the window is about to move under us and
        // anything window-relative would drift by exactly what we changed.
        startX = NSEvent.mouseLocation.x
        onResizeBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        onResize?(NSEvent.mouseLocation.x - startX)
    }

    override func draw(_ dirtyRect: NSRect) {
        // A double-headed arrow rather than a diagonal one: height is not
        // draggable, and a corner arrow pointing both ways would promise a
        // drag that snaps straight back.
        let glyph = NSAttributedString(
            string: "\u{2194}",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: MarkInk.colour(for: theme).withAlphaComponent(isHighlighted ? 1 : 0.5)
            ]
        )
        let size = glyph.size()
        glyph.draw(at: NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        ))
    }
}
