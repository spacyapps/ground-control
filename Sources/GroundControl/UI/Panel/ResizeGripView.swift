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
    var onResize: ((CGSize) -> Void)?
    var onResizeBegan: (() -> Void)?

    private var theme: Theme = DefaultTheme.theme
    private var start: NSPoint = .zero

    /// Whether a vertical drag means anything. Everywhere else the height is
    /// derived — from the rows, or from the artwork — so offering it would
    /// promise a drag that snaps back the moment it ends.
    private var allowsVertical: Bool { theme.layout.resize == .free }
    private var isHighlighted = false
    /// The panel draws its own hints; AppKit's tooltips never show here, the
    /// app being an accessory whose panel does not activate.
    var onHint: ((String?, NSRect) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    /// The panel moves when dragged by its background, which would otherwise
    /// swallow this drag before it starts.
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
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
        // No public cursor for a corner resize, so the closest honest thing:
        // both directions when both are live, sideways when only width is.
        (allowsVertical ? NSCursor.crosshair : NSCursor.resizeLeftRight).set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
        onHint?("Resize", frame)
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
        onHint?(nil, .zero)
    }

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

    override func draw(_ dirtyRect: NSRect) {
        // The glyph is a promise about what the drag does: sideways where only
        // the width is yours, diagonal where the panel is free.
        let glyph = NSAttributedString(
            string: allowsVertical ? "\u{2921}" : "\u{2194}",
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
