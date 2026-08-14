// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The state indicator: a filled dot in the state's colour.
///
/// `needsAction` is the loud case — it fills solid in the theme's needsAction
/// colour. Quiet states draw dimmer so a panel of idle rows stays calm.
final class StatusDotView: NSView {
    /// A round mark reports fully; a square one cannot.
    ///
    /// Cursor's agent fires no hook while it waits for approval, so its rows
    /// never turn red however stuck they are. A dot that means "state" beside a
    /// dot that means "state, as far as we can tell" is a quiet lie, and the
    /// difference is worth a shape — it reads at a glance and survives every
    /// theme, since it costs no colour.
    enum Mark: Equatable {
        case round
        case square

        /// Which sources can be trusted to say they are blocked. Kept here so
        /// the rule has one home rather than being re-decided per view.
        static func forSource(_ source: String) -> Mark {
            source == "cursor" ? .square : .round
        }
    }

    var mark: Mark = .round {
        didSet { needsDisplay = true }
    }

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
        let body = rect.insetBy(dx: 1, dy: 1)
        // Slightly rounded rather than a hard square: at eight points a sharp
        // corner reads as an artefact, and this still cannot be mistaken for
        // the circle beside it.
        let path = mark == .square
            ? NSBezierPath(roundedRect: body, xRadius: 1.5, yRadius: 1.5)
            : NSBezierPath(ovalIn: body)
        color.withAlphaComponent(isProminent ? 1.0 : 0.55).setFill()
        path.fill()
    }
}
