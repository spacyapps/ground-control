// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Pointer handling: hover, the hint, and what a click does.
extension SessionRowView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // Pushed imperatively rather than via cursorUpdate: this panel never
    // becomes key, and AppKit only runs cursor updates for the key window.
    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.pointingHand.push()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isMenuHovered = false
        NSCursor.pop()
        needsDisplay = true
        onHint?(nil, .zero)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let inside = menuTarget.contains(point)
        if inside != isMenuHovered {
            isMenuHovered = inside
            needsDisplay = true
        }
        updateHint(at: point)
    }

    /// One word, because the hint appears beside a 48pt avatar in a panel that
    /// is often narrow. The row menu names the destination in full; this only
    /// has to say what kind of thing a click is.
    func applyJumpHint(canJump: Bool) {
        jumpHint = canJump ? "Jump" : "Finder"
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Generously sized: the mark is 14pt but the target is not.
        if menuTarget.contains(point) {
            onSecondaryClick?(event)
            return
        }
        if isGroup && disclosure.frame.insetBy(dx: -4, dy: -4).contains(point) {
            onToggleChildren?()
            return
        }
        onActivate?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick?(event)
    }
}
