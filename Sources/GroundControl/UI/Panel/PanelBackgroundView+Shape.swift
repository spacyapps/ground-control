// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The window silhouette and the body behind the rows, split out because the
/// silhouette is the expensive 44-frame composite and the body is a cheap
/// re-clip of it.
extension PanelBackgroundView {
    // MARK: - Shape

    /// Renders the silhouette at the current size and masks the content to it,
    /// so rows are cut to the outline instead of spilling past a curve.
    func updateShapeMask() {
        guard let shape = theme.window.shape, bounds.width > 1, bounds.height > 1 else {
            layer?.mask = nil
            shapeMask = nil
            maskedSize = .zero
            enclosedArea = []
            return
        }

        let size = NSSize(width: bounds.width, height: bounds.height)

        // Same size, just more rows: keep the composite, re-clip the body.
        if size == maskedSize, !enclosedArea.isEmpty {
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
        // Every frame, drawn over itself. A mask only removes, so a silhouette
        // taken from frame one clips whatever a later frame moves into — and
        // swallows clicks where the art has since moved away. Compositing the
        // frames unions their coverage, which is the shape the skin occupies
        // over its whole loop.
        if let animated = AnimatedImage.load(shape), animated.isAnimated {
            for index in 0..<animated.frames.count {
                BackgroundRenderer.draw(
                    shape,
                    in: NSRect(origin: .zero, size: size),
                    elapsed: Double(index) * animated.duration
                )
            }
        } else {
            BackgroundRenderer.draw(shape, in: NSRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()

        // Also fills the opening into the mask so the window covers its middle;
        // the array it returns is what the body re-clips from later.
        enclosedArea = SkinInterior.fillEnclosed(in: rep)
        maskedSize = size
        rebuildInteriorBody(size: size)

        shapeMask = rep

        let mask = CALayer()
        mask.frame = bounds
        mask.contents = rep.cgImage
        layer?.mask = mask
        window?.invalidateShadow()
    }

    /// Re-cut the body to the rows without touching the silhouette — for when
    /// a group expanded and only the content height moved.
    func refreshInteriorBody() {
        guard maskedSize != .zero else { return }
        rebuildInteriorBody(size: maskedSize)
        needsDisplay = true
    }

    /// The body sits behind the rows and ends with them — below the last row is
    /// the frame's own floor. Cheap: a re-clip of `enclosedArea`.
    func rebuildInteriorBody(size: NSSize) {
        guard theme.window.drawsOverContent else {
            interiorBody = nil
            return
        }
        let contentBottom = effectiveInsets.top + titleBar.preferredHeight + list.contentHeight
        interiorBody = SkinInterior.overlayBody(
            from: enclosedArea,
            size: size,
            contentBottom: contentBottom,
            colour: theme.colors.windowBackground
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
