// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The state indicator: a filled dot in the state's colour.
///
/// `needsAction` is the loud case — it fills solid in the theme's needsAction
/// colour. Quiet states draw dimmer so a panel of idle rows stays calm.
final class StatusDotView: NSView {
    var color: NSColor = DefaultTheme.colors.idle {
        didSet { needsDisplay = true }
    }

    var isProminent = false {
        didSet { needsDisplay = true }
    }

    /// A theme may replace the drawn dot with its own badge. Only used while
    /// prominent — it is the *needsAction* dot, and a quiet row keeps the
    /// understated painted version.
    var badge: URL? {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 10, height: 10) }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let rect = NSRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )

        if isProminent, let badge, let image = NSImage(contentsOf: badge) {
            image.draw(in: rect)
            return
        }
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        color.withAlphaComponent(isProminent ? 1.0 : 0.55).setFill()
        path.fill()
    }
}
