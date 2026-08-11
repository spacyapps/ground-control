import AppKit

/// Draws a themed background into a box of any size.
///
/// Nine-slice is handled by AppKit itself: setting `capInsets` and
/// `resizingMode` on an `NSImage` makes `draw(in:)` hold the corners at their
/// natural size and grow only the edges and centre. That is why a theme needs
/// one image and four numbers rather than nine separate tiles.
enum BackgroundRenderer {
    private static let cache = NSCache<NSString, NSImage>()

    static func draw(_ background: BackgroundImage, in rect: NSRect) {
        guard let image = configuredImage(for: background) else { return }

        switch background.mode {
        case .tile, .stretch:
            image.draw(in: rect)
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

        guard let image = NSImage(contentsOf: background.url) else {
            Log.theming.notice("Could not load background \(background.url.lastPathComponent, privacy: .public)")
            return nil
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
    }
}
