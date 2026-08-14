// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The ✕, as a view the panel owns rather than something inside the title bar.
///
/// It used to live in the title strip, which put it under any skin drawn in
/// front and under the artwork whenever a theme tucked its content behind the
/// frame. A decoration that can hide the only way to close the window is a bad
/// trade, however good it looks — so the two marks now sit above everything,
/// including the overlay: **marks, then frame, then panel.**
final class CloseMarkView: NSView {
    static let size = NSSize(width: 16, height: 16)

    var onClose: (() -> Void)?

    private var theme: Theme = DefaultTheme.theme
    private var isHighlighted = false
    /// The panel draws its own hints; AppKit's tooltips never show here, the
    /// app being an accessory whose panel does not activate.
    var onHint: ((String?, NSRect) -> Void)?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    /// The panel moves when dragged by its background, which would otherwise
    /// swallow the click.
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CloseMarkView is created in code only")
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
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
        onHint?("Hide", frame)
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
        onHint?(nil, .zero)
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClose?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let glyph = NSAttributedString(
            string: "\u{2715}",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: MarkInk.colour(for: theme)
                    .withAlphaComponent(isHighlighted ? 1 : 0.5)
            ]
        )
        let size = glyph.size()
        glyph.draw(at: NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        ))
    }
}

/// Shared by both corner marks so they cannot drift apart.
enum MarkInk {
    /// The title colour, which is what the marks are meant to match.
    ///
    /// Falls back to plain contrast when a theme picks a title colour that
    /// vanishes against its own window — these are the only ways to close and
    /// resize a shaped panel, so they cannot be allowed to disappear.
    static func colour(for theme: Theme) -> NSColor {
        let themed = theme.colors.titleBarText
        return contrast(themed, against: theme.colors.windowBackground) > 0.25
            ? themed
            : opposite(of: theme.colors.windowBackground)
    }

    private static func luminance(of color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }

    private static func contrast(_ one: NSColor, against other: NSColor) -> CGFloat {
        abs(luminance(of: one) - luminance(of: other))
    }

    private static func opposite(of color: NSColor) -> NSColor {
        luminance(of: color) < 0.5 ? .white : .black
    }
}
