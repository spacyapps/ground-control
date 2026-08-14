// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// What the panel's two corner marks have in common.
///
/// A shaped theme is `.borderless`, which costs the system title bar and resize
/// control, so the panel supplies its own — a ✕ at one end of the title strip
/// and a ↔ at the other. They are drawn above any skin, because a decoration
/// that can hide the only way to close a window is a bad trade however good it
/// looks.
///
/// Everything below was written twice before this existed: the hover tracking,
/// the ink, the hint wiring, and the rule that a drag on a mark must not be
/// taken as a drag on the window behind it.
class CornerMarkView: NSView {
    static let size = NSSize(width: 16, height: 16)

    /// The panel draws its own hints. AppKit's tooltips never show here: they
    /// appear for the active application, and this one is an accessory whose
    /// panel deliberately does not activate.
    var onHint: ((String?, NSRect) -> Void)?

    private(set) var theme: Theme = DefaultTheme.theme
    private(set) var isHighlighted = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    /// The panel moves when dragged by its background, which would otherwise
    /// swallow anything these marks are trying to do.
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CornerMarkView is created in code only")
    }

    // MARK: - For subclasses

    /// One word, shown beside the mark on hover.
    var hint: String { "" }

    /// The glyph, chosen after the theme is known so it can answer it.
    var glyph: String { "" }

    var markCursor: NSCursor { .arrow }

    /// The title colour, so the marks match the strip they sit on — falling
    /// back to plain contrast when a theme picks one that vanishes against its
    /// own window. These are the only ways to close and resize a shaped panel,
    /// so they may not disappear.
    var ink: NSColor { MarkInk.colour(for: theme) }

    // MARK: - Shared behaviour

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
        markCursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
        onHint?(hint, frame)
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
        onHint?(nil, .zero)
    }

    override func draw(_ dirtyRect: NSRect) {
        let text = NSAttributedString(
            string: glyph,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: ink.withAlphaComponent(isHighlighted ? 1 : 0.5)
            ]
        )
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
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
