// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The window silhouette and the body behind the rows, split out because the
/// silhouette is the expensive 44-frame composite and the body is a cheap
/// rectangle re-filled to the current row height inside it.
extension PanelBackgroundView {
    // MARK: - Shape

    /// Renders the silhouette at the current size and masks the content to it,
    /// so rows are cut to the outline instead of spilling past a curve.
    func updateShapeMask() {
        guard let shape = theme.window.shape, bounds.width > 1, bounds.height > 1 else {
            layer?.mask = nil
            shapeMask = nil
            maskedSize = .zero
            return
        }

        let size = NSSize(width: bounds.width, height: bounds.height)

        // Same size, just more rows: keep the composite, re-clip the body.
        if size == maskedSize, maskedSize != .zero {
            rebuildInteriorBody(size: size)
            return
        }

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
        // `skinOverlay` is a flipped view, this bitmap context is not — so to
        // land the frame's top `frameTopOffset` points down from the *visible*
        // top, the draw box shrinks from y=0 here, which is the visible bottom.
        let drawRect = NSRect(
            x: 0, y: 0, width: size.width, height: max(0, size.height - frameTopOffset)
        )
        // Every frame, drawn over itself. A mask only removes, so a silhouette
        // taken from frame one clips whatever a later frame moves into — and
        // swallows clicks where the art has since moved away. Compositing the
        // frames unions their coverage, which is the shape the skin occupies
        // over its whole loop.
        if let animated = AnimatedImage.load(shape), animated.isAnimated {
            for index in 0..<animated.frames.count {
                BackgroundRenderer.draw(shape, in: drawRect, elapsed: Double(index) * animated.duration)
            }
        } else {
            BackgroundRenderer.draw(shape, in: drawRect)
        }
        NSGraphicsContext.restoreGraphicsState()

        // Fills the frame's opening into the mask so the window covers its own
        // middle — the return value is unused now that the body is a rectangle.
        SkinInterior.fillEnclosed(in: rep)
        maskedSize = size
        rebuildInteriorBody(size: size)

        shapeMask = rep

        let mask = CALayer()
        mask.frame = bounds
        mask.contents = rep.cgImage
        layer?.mask = mask
        window?.invalidateShadow()
    }

    /// Re-fill the body to the rows without touching the silhouette — for when
    /// a group expanded and only the content height moved.
    func refreshInteriorBody() {
        guard maskedSize != .zero else { return }
        rebuildInteriorBody(size: maskedSize)
        needsDisplay = true
    }

    /// The body sits behind the rows and ends with them — below the last row is
    /// the frame's own floor, which the skin draws itself.
    ///
    /// A plain rectangle, not a traced shape: the silhouette mask on this view's
    /// layer already clips it to the frame's outline, so it only needs bounds.
    /// With `bodyFade` it goes solid only to the analyser strip and then ramps
    /// to nothing across the first row, so the rows past the first sit on the
    /// frame with only their own translucent background.
    func rebuildInteriorBody(size: NSSize) {
        guard theme.window.drawsOverContent else {
            interiorBody = nil
            return
        }
        let analyserBottom = effectiveInsets.top + titleBar.contentHeight
        let fades = theme.window.bodyFadesBelowAnalyser
        let bodyBottom = fades ? analyserBottom : analyserBottom + list.contentHeight
        interiorBody = SkinInterior.solidBody(
            size: size,
            contentTop: titleStripTop,
            contentBottom: bodyBottom,
            colour: theme.colors.windowBackground,
            fadeOver: fades ? SessionRowView.height(for: theme) : 0
        )
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
