// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The panel's themed content: title bar and session list.
///
/// Owns the whole surface so the theme reaches the window's edges — macOS
/// chrome is switched off in `FloatingPanel`, and this is what replaces it.
final class PanelBackgroundView: NSView {
    let titleBar = TitleBarView()
    let list = SessionListView()

    private var theme: Theme = DefaultTheme.theme

    /// The silhouette rendered at the current size.
    ///
    /// Kept as a bitmap rather than sampled from the source image because the
    /// shape is nine-sliced: a point on screen does not map linearly back to a
    /// pixel in the file once the edges have stretched. Rendering once per
    /// resize and sampling that is both simpler and exact.
    private var shapeMask: NSBitmapImageRep?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        addSubview(titleBar)
        addSubview(list)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PanelBackgroundView is created in code only")
    }

    func apply(theme: Theme) {
        self.theme = theme
        shapeMask = nil
        layer?.cornerRadius = theme.window.isShaped ? 0 : 10
        needsLayout = true
        layer?.backgroundColor = theme.colors.windowBackground.cgColor
        titleBar.apply(theme: theme)
        list.apply(theme: theme)
        needsDisplay = true
    }

    /// Height at which nothing is clipped: title strip, every row, and the
    /// frame the theme asked to keep clear.
    var desiredHeight: CGFloat {
        TitleBarView.height + list.contentHeight + theme.layout.contentInset * 2
    }

    func refreshElapsed() {
        list.refreshElapsed()
    }

    func update(sessions: [Session], renames: [String: String]) {
        titleBar.update(sessions: sessions)
        list.apply(sessions: sessions, renames: renames)
    }

    override func layout() {
        super.layout()
        updateShapeMask()
        // Everything sits inside the inset, so a framed background shows all
        // the way round rather than only above the first row.
        let inset = theme.layout.contentInset
        let width = max(0, bounds.width - inset * 2)

        titleBar.frame = NSRect(x: inset, y: inset, width: width, height: TitleBarView.height)
        list.frame = NSRect(
            x: inset,
            y: titleBar.frame.maxY,
            width: width,
            height: max(0, bounds.height - TitleBarView.height - inset * 2)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        // A shaped panel has no rectangle to fill: the silhouette is the whole
        // window, and painting a background colour first would square it off
        // again.
        if let shape = theme.window.shape {
            BackgroundRenderer.draw(shape, in: bounds)
            return
        }

        // Otherwise the colour goes down first, so a background image carrying
        // transparency composites onto it rather than onto nothing.
        theme.colors.windowBackground.setFill()
        bounds.fill()

        if let background = theme.backgrounds.window {
            BackgroundRenderer.draw(background, in: bounds)
        }
    }

    // MARK: - Shape

    /// Renders the silhouette at the current size and masks the content to it,
    /// so rows are cut to the outline instead of spilling past a curve.
    private func updateShapeMask() {
        guard let shape = theme.window.shape, bounds.width > 1, bounds.height > 1 else {
            layer?.mask = nil
            shapeMask = nil
            return
        }

        let size = NSSize(width: bounds.width, height: bounds.height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        BackgroundRenderer.draw(shape, in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        shapeMask = rep

        let mask = CALayer()
        mask.frame = bounds
        mask.contents = rep.cgImage
        layer?.mask = mask
        window?.invalidateShadow()
    }

    /// Lets clicks fall through transparent parts of a skin.
    ///
    /// Without this a shaped panel is still an invisible rectangle as far as
    /// the mouse is concerned, swallowing clicks meant for whatever is behind
    /// it — the most irritating way a skinned window can misbehave.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard theme.window.isShaped, let mask = shapeMask else {
            return super.hitTest(point)
        }

        let local = convert(point, from: superview)
        let column = Int(local.x)
        let row = Int(isFlipped ? local.y : bounds.height - local.y)
        guard column >= 0, row >= 0,
              column < mask.pixelsWide, row < mask.pixelsHigh else { return nil }

        let alpha = mask.colorAt(x: column, y: row)?.alphaComponent ?? 0
        return alpha > 0.08 ? super.hitTest(point) : nil
    }
}
