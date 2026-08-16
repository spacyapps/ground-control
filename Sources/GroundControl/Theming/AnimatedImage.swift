// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import ImageIO

/// A multi-frame image, decoded once and held as ready-to-draw frames.
///
/// `NSImage.draw(in:)` renders frame zero and stops — animated images only move
/// inside an `NSImageView`, which the nine-slice renderer cannot use. So a
/// background that animates has to be stepped by hand, which means having the
/// frames to hand.
///
/// Each frame carries the cap insets, so every one nine-slices identically and
/// a resizing panel does not shear mid-animation.
struct AnimatedImage {
    let frames: [NSImage]
    /// Seconds per frame, honouring the file's own timing rather than guessing.
    let duration: TimeInterval

    var isAnimated: Bool { frames.count > 1 }

    /// Frame for a moment in time, looping.
    func frame(at elapsed: TimeInterval) -> NSImage? {
        guard !frames.isEmpty else { return nil }
        guard isAnimated, duration > 0 else { return frames[0] }
        let index = Int((elapsed / duration).truncatingRemainder(dividingBy: Double(frames.count)))
        return frames[min(max(0, index), frames.count - 1)]
    }

    private static let cache = NSCache<NSString, CacheBox>()

    private final class CacheBox {
        let value: AnimatedImage
        init(_ value: AnimatedImage) { self.value = value }
    }

    /// Decoding every frame of a large image is expensive, so results are kept
    /// per (file, mode, insets) — the same key the still renderer uses.
    static func load(_ background: BackgroundImage) -> AnimatedImage? {
        let key = background.cacheKey as NSString
        if let cached = cache.object(forKey: key) { return cached.value }

        guard let source = CGImageSourceCreateWithURL(background.url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [NSImage] = []
        var slowest: TimeInterval = 0

        for index in 0..<count {
            guard let raw = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            // Keyed here, once per frame at load, so nothing downstream has to
            // know the file arrived without usable alpha.
            let cgImage = background.removeBackground.map { ImageKeyer.apply($0, to: raw) } ?? raw
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            image.capInsets = background.capInsets
            image.resizingMode = background.mode == .tile ? .tile : .stretch
            frames.append(image)
            slowest = max(slowest, delay(of: source, at: index))
        }

        guard !frames.isEmpty else { return nil }
        let animated = AnimatedImage(
            frames: frames,
            duration: slowest > 0 ? slowest : 1.0 / 12
        )
        cache.setObject(CacheBox(animated), forKey: key)
        return animated
    }

    static func clearCache() {
        cache.removeAllObjects()
    }

    /// Reads frame timing from GIF *or* APNG.
    ///
    /// They keep it in different dictionaries under different keys, and a theme
    /// may legitimately use either — APNG being the way to get an animation
    /// with real 8-bit alpha, which GIF cannot express.
    private static func delay(of source: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [CFString: Any] else { return 0 }

        let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]

        let unclamped = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
            ?? png?[kCGImagePropertyAPNGUnclampedDelayTime] as? TimeInterval
        let clamped = gif?[kCGImagePropertyGIFDelayTime] as? TimeInterval
            ?? png?[kCGImagePropertyAPNGDelayTime] as? TimeInterval
        // Browsers treat anything under 20ms as 100ms; matching that keeps a
        // GIF looking the way its author saw it.
        let delay = unclamped ?? clamped ?? 0
        return delay < 0.02 ? 0.1 : delay
    }
}
