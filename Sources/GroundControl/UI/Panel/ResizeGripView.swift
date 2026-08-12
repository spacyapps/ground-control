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
    static let size = NSSize(width: 11, height: 46)

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

    /// White on a dark theme, black on a light one.
    ///
    /// Drawing the handle in palette colours made it invisible: on a dark skin
    /// a `titleBarBackground` capsule is near-black on near-black, and a theme
    /// cannot be relied on to have picked anything that contrasts with itself.
    /// The one colour guaranteed to read against a background is its opposite.
    private var ink: NSColor {
        let background = theme.colors.windowBackground.usingColorSpace(.sRGB)
            ?? .black
        let luminance = 0.2126 * background.redComponent
            + 0.7152 * background.greenComponent
            + 0.0722 * background.blueComponent
        return luminance < 0.5 ? .white : .black
    }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: bounds.width / 2,
            yRadius: bounds.width / 2
        )
        let ink = self.ink
        ink.withAlphaComponent(isHighlighted ? 0.3 : 0.18).setFill()
        capsule.fill()
        ink.withAlphaComponent(isHighlighted ? 0.75 : 0.4).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()

        (isHighlighted ? theme.colors.accent : ink.withAlphaComponent(0.85)).setStroke()

        // Two grip lines, the convention for a handle that moves sideways.
        let inset = bounds.height * 0.3
        for offset in [-2.0, 2.0] {
            let line = NSBezierPath()
            line.lineWidth = 1.5
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: bounds.midX + offset, y: inset))
            line.line(to: NSPoint(x: bounds.midX + offset, y: bounds.height - inset))
            line.stroke()
        }
    }
}
