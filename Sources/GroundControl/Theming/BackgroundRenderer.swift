// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Draws a themed background into a box of any size.
///
/// Nine-slice is handled by AppKit itself: setting `capInsets` and
/// `resizingMode` on an `NSImage` makes `draw(in:)` hold the corners at their
/// natural size and grow only the edges and centre. That is why a theme needs
/// one image and four numbers rather than nine separate tiles.
enum BackgroundRenderer {
    private static let cache = NSCache<NSString, NSImage>()

    /// Draws a background, optionally at a moment in an animation.
    ///
    /// `elapsed` nil means the still path — one decode, cached, no frames.
    static func draw(_ background: BackgroundImage, in rect: NSRect, elapsed: TimeInterval? = nil) {
        if let elapsed, let animated = AnimatedImage.load(background), animated.isAnimated {
            draw(animated.frame(at: elapsed), background: background, in: rect)
            return
        }
        guard let image = configuredImage(for: background) else { return }
        draw(image, background: background, in: rect)
    }

    /// True when this background has more than one frame, so callers know
    /// whether a timer is worth running at all.
    static func isAnimated(_ background: BackgroundImage) -> Bool {
        AnimatedImage.load(background)?.isAnimated ?? false
    }

    /// Draws the artwork the way up its author drew it.
    ///
    /// Only AppKit's resizable-image path needs correcting, and it needs it
    /// badly: it lays the pieces out in image order and ignores the context's
    /// flip, so in a flipped view the bottom cap lands at the top and the whole
    /// skin comes out mirrored. `respectFlipped:` does not reach that path.
    /// Mirroring the context around the destination rect does.
    ///
    /// Plain drawing already honours the flip, and mirroring *that* turns a
    /// correct image upside down — so the two cases cannot share a branch.
    /// Measured across every mode and cap combination rather than assumed.
    private static func drawUpright(_ image: NSImage, resizable: Bool, in rect: NSRect) {
        guard resizable, let context = NSGraphicsContext.current, context.isFlipped else {
            image.draw(in: rect)
            return
        }
        let cg = context.cgContext
        cg.saveGState()
        cg.translateBy(x: 0, y: rect.minY * 2 + rect.height)
        cg.scaleBy(x: 1, y: -1)
        image.draw(in: rect)
        cg.restoreGState()
    }

    private static func draw(_ image: NSImage?, background: BackgroundImage, in rect: NSRect) {
        guard let image else { return }

        switch background.mode {
        case .tile, .stretch:
            drawUpright(image, resizable: background.usesResizableDrawing, in: rect)
        case .center:
            drawCentered(image, in: rect, fill: false)
        case .aspectFill:
            drawCentered(image, in: rect, fill: true)
        }
    }

    /// Loads and configures once per (file, mode, insets). The cap insets and
    /// resizing mode live on the image instance, so the key has to include
    /// them — two surfaces can share a file with different behaviour.
    private static func configuredImage(for background: BackgroundImage) -> NSImage? {
        let key = background.cacheKey as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard var image = NSImage(contentsOf: background.url) else {
            Log.theming.notice("Could not load background \(background.url.lastPathComponent, privacy: .public)")
            return nil
        }

        if let key = background.removeBackground,
           let raw = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let keyed = ImageKeyer.apply(key, to: raw)
            image = NSImage(cgImage: keyed, size: NSSize(width: keyed.width, height: keyed.height))
        }

        if background.mode == .tile || background.mode == .stretch {
            image.capInsets = background.capInsets
            image.resizingMode = background.mode == .tile ? .tile : .stretch
        }

        cache.setObject(image, forKey: key)
        return image
    }

    private static func drawCentered(_ image: NSImage, in rect: NSRect, fill: Bool) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }

        let scale: CGFloat
        if fill {
            scale = max(rect.width / size.width, rect.height / size.height)
        } else {
            scale = 1
        }
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        let origin = NSPoint(
            x: rect.midX - drawn.width / 2,
            y: rect.midY - drawn.height / 2
        )

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        image.draw(in: NSRect(origin: origin, size: drawn))
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// Themes hot-reload, so a re-saved file must not keep serving the old art.
    static func clearCache() {
        cache.removeAllObjects()
        AnimatedImage.clearCache()
        // The preview holds its own decoded copies, so editing an avatar file
        // has to invalidate both or Settings keeps showing the old artwork.
        ThemePreviewView.clearCache()
    }
}
