// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The state indicator: a filled dot in the state's colour.
///
/// `needsAction` is the loud case — it fills solid in the theme's needsAction
/// colour. Quiet states draw dimmer so a panel of idle rows stays calm.
final class StatusDotView: NSView {
    /// A round mark reports fully; a square one cannot; a split one does not
    /// know which quiet state it is in.
    ///
    /// Cursor's agent fires no hook while it waits for approval, so its rows
    /// never turn red however stuck they are. A dot that means "state" beside a
    /// dot that means "state, as far as we can tell" is a quiet lie, and the
    /// difference is worth a shape — it reads at a glance and survives every
    /// theme, since it costs no colour.
    ///
    /// `.unknown` is Grok Bot: we can read "a card is waiting" (that row turns
    /// red and round like any other), but between cards its cloud agent can be
    /// working, idle or done and the local cache never says which. The dot
    /// splits idle | done to show exactly that — never a guess at "working".
    enum Mark: Equatable {
        case round
        case square
        case unknown

        /// Which sources can be trusted to say they are blocked, and which
        /// cannot say what they are doing at all. Kept here so the rule has one
        /// home rather than being re-decided per view.
        static func forSource(_ source: String) -> Mark {
            switch source {
            case "cursor": return .square
            case "grokbot": return .unknown
            default: return .round
            }
        }
    }

    /// The other half of an `.unknown` split dot. Ignored for every other mark.
    var altColor: NSColor = DefaultTheme.colors.accent {
        didSet { needsDisplay = true }
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

        // A split dot only while quiet: a waiting Grok bot is prominent, and
        // then it is a solid red circle like every other alarm.
        if mark == .unknown, !isProminent {
            drawSplit(in: body)
            return
        }

        // Slightly rounded rather than a hard square: at eight points a sharp
        // corner reads as an artefact, and this still cannot be mistaken for
        // the circle beside it.
        let path = mark == .square
            ? NSBezierPath(roundedRect: body, xRadius: 1.5, yRadius: 1.5)
            : NSBezierPath(ovalIn: body)
        color.withAlphaComponent(isProminent ? 1.0 : 0.55).setFill()
        path.fill()
    }

    /// Left half `color`, right half `altColor`, clipped to the circle — idle
    /// on one side, done on the other, because it is genuinely one or the
    /// other and the cache will not say.
    private func drawSplit(in body: NSRect) {
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(ovalIn: body).addClip()
        color.withAlphaComponent(0.55).setFill()
        NSRect(x: body.minX, y: body.minY, width: body.width / 2, height: body.height).fill()
        altColor.withAlphaComponent(0.55).setFill()
        NSRect(x: body.midX, y: body.minY, width: body.width / 2, height: body.height).fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
