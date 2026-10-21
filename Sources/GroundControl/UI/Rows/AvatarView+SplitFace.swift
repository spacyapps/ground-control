// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The split face: two states' stills on either side of a seam that sweeps round
/// like a minute hand. Drawing only; the view decides when to show it.
extension AvatarView {
    /// Where the seam points: a clock's minute hand, one full turn an hour.
    /// It moves because "we don't know" is a live guess, not a resting state —
    /// docs/GROK-BOT-GROUPING.md.
    static func clockSeamAngle(_ date: Date = Date()) -> CGFloat {
        let seconds = date.timeIntervalSince(Calendar.current.startOfDay(for: date))
        let intoHour = seconds.truncatingRemainder(dividingBy: 3600)
        // A real minute hand: vertical at :00, horizontal (pointing at the 3)
        // at :15, and sweeping clockwise — so the angle counts *down* from π/2.
        return .pi / 2 - CGFloat(intoHour / 3600) * 2 * .pi
    }

    static func splitFace(left: SessionState,
                          right: SessionState,
                          theme: Theme,
                          angle: CGFloat) -> NSImage {
        let side = max(1, theme.avatar.size)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let centre = NSPoint(x: rect.midX, y: rect.midY)
            let reach = rect.width * 4
            let along = NSPoint(x: cos(angle), y: sin(angle))       // the seam's direction
            let across = NSPoint(x: -sin(angle), y: cos(angle))     // its normal

            for (state, sign) in [(left, CGFloat(1)), (right, CGFloat(-1))] {
                NSGraphicsContext.current?.saveGraphicsState()
                // The half-plane on one side of the seam, as a big quad.
                let ends = (NSPoint(x: centre.x - along.x * reach, y: centre.y - along.y * reach),
                            NSPoint(x: centre.x + along.x * reach, y: centre.y + along.y * reach))
                let half = NSBezierPath()
                half.move(to: ends.0)
                half.line(to: ends.1)
                half.line(to: NSPoint(x: ends.1.x + across.x * reach * sign,
                                      y: ends.1.y + across.y * reach * sign))
                half.line(to: NSPoint(x: ends.0.x + across.x * reach * sign,
                                      y: ends.0.y + across.y * reach * sign))
                half.close()
                half.addClip()
                face(for: state, theme: theme)?.draw(in: rect)
                NSGraphicsContext.current?.restoreGraphicsState()
            }

            // The seam itself — a diameter at `angle`. `messageDim` is the
            // avatar's own border colour, so the line belongs to the plate
            // rather than sitting on the artwork like the old white one did.
            let seam = NSBezierPath()
            seam.lineWidth = max(2, rect.width * 0.05)
            seam.move(to: NSPoint(x: centre.x - along.x * reach, y: centre.y - along.y * reach))
            seam.line(to: NSPoint(x: centre.x + along.x * reach, y: centre.y + along.y * reach))
            theme.colors.messageDim.withAlphaComponent(0.75).setStroke()
            seam.stroke()
            return true
        }
    }

    /// One state's face as a plain image — the theme's still, or the built-in
    /// symbol tinted and inset the way `layout()` insets a drawn avatar.
    static func face(for state: SessionState, theme: Theme) -> NSImage? {
        switch theme.avatar.asset(for: state) {
        case .image(let url):
            return imageCache.object(forKey: url as NSURL) ?? NSImage(contentsOf: url)
        case .video, .none:
            guard let symbol = DrawnAvatar.symbol(for: state) else { return nil }
            let colour = theme.colors.color(for: state)
            let tinted = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [colour])
            ) ?? symbol
            return NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
                tinted.draw(in: rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.2))
                return true
            }
        }
    }
}
