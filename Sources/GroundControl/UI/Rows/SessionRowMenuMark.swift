// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The row's menu affordance, and the hints for its two controls.
///
/// The menu was right-click only, which nobody discovers. This is the visible
/// way in, and it borrows the avatar button's chrome so the two read as the
/// same kind of thing — a bordered tile that lifts under the pointer.
extension SessionRowView {
    /// Larger than the mark it lights: three small dots are easy to draw and
    /// hard to hit, and the click test uses this same rectangle.
    var menuTarget: NSRect { menuRect.insetBy(dx: -4, dy: -4) }

    /// Three lines above the status dot: the same menu right-click gives, for
    /// anyone who never thinks to right-click a row.
    ///
    /// Faint until the pointer is on the row, so a list at rest stays about the
    /// sessions rather than about its own controls.
    func drawMenuMark() {
        guard menuRect.height > 0 else { return }

        // The same treatment the avatar button gets, so the two read as the
        // same kind of thing: a bordered tile that lifts under the pointer.
        if isMenuHovered {
            let tile = NSBezierPath(roundedRect: menuTarget, xRadius: 5, yRadius: 5)
            theme.colors.rowBackgroundHover.setFill()
            tile.fill()
            theme.colors.messageDim.withAlphaComponent(0.9).setStroke()
            tile.lineWidth = 1
            tile.stroke()
        } else if isHovering {
            let tile = NSBezierPath(roundedRect: menuTarget, xRadius: 5, yRadius: 5)
            theme.colors.messageDim.withAlphaComponent(0.25).setStroke()
            tile.lineWidth = 1
            tile.stroke()
        }

        let ink = theme.colors.messageDim
            .withAlphaComponent(isMenuHovered ? 1 : (isHovering ? 0.8 : 0.35))
        ink.setFill()

        // Three lines rather than three dots: the shape people already read as
        // "menu", and it survives being small better than dots do — a 2.5pt
        // circle is four pixels of grey, while a line keeps its length.
        let lineWidth = menuRect.width - 1
        let thickness: CGFloat = 1.5
        let gap: CGFloat = 3
        let total = thickness * 3 + gap * 2
        var y = menuRect.midY - total / 2
        for _ in 0..<3 {
            NSBezierPath(rect: NSRect(
                x: menuRect.midX - lineWidth / 2,
                y: y,
                width: lineWidth,
                height: thickness
            )).fill()
            y += thickness + gap
        }
    }

    /// The two controls worth explaining, and nothing else: a hint that follows
    /// the pointer everywhere is noise.
    func updateHint(at point: NSPoint) {
        if isMenuHovered {
            onHint?("Menu", menuTarget)
        } else if let avatarFrame = avatarFrameIfVisible, avatarFrame.contains(point) {
            onHint?(jumpHint, avatarFrame)
        } else {
            onHint?(nil, .zero)
        }
    }
}
