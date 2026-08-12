// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The skin drawn *over* the rows rather than behind them.
///
/// Behind the rows, a frame and its contents have to be fitted to each other:
/// `contentInset` has to match where the artwork's opening starts, and the
/// content's corners have to match its curve, or the panel looks like a screen
/// pasted onto a picture. Over the rows, none of that arises — the frame simply
/// covers whatever it overlaps, so the rows can run past its opening and the
/// artwork decides where they appear to stop.
///
/// The trade is that the artwork's centre must now be *transparent*, which is
/// the exact opposite of what a background skin needs. An opaque middle drawn on
/// top hides the panel entirely.
final class SkinOverlayView: NSView {
    /// Supplied by the panel so the overlay animates on the same clock as
    /// everything else, rather than starting its own and drifting.
    var elapsed: (() -> TimeInterval?)?

    private var shape: BackgroundImage?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SkinOverlayView is created in code only")
    }

    /// Covers the rows, so it must never take a click meant for one — including
    /// where the artwork is opaque. A frame is decoration, not a target.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(theme: Theme) {
        shape = theme.window.drawsOverContent ? theme.window.shape : nil
        isHidden = shape == nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let shape else { return }
        BackgroundRenderer.draw(shape, in: bounds, elapsed: elapsed?())
    }
}
