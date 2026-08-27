// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import AVFoundation

/// Turning a theme's asset URLs into drawable images, and caching them.
///
/// Split from the drawing code because it is a different job — file loading,
/// keying, a video frame grab — and it shares one `NSCache` across all three
/// kinds of source so `clearCache()` has a single thing to clear.
extension ThemePreviewView {
    static func image(at url: URL) -> NSImage? {
        if let cached = imageCache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// One frame of a video avatar state, for the same static preview a
    /// still image gets. Shares `imageCache` with `image(at:)` — same URL
    /// key, same lifetime, same `clearCache()` — so this costs no new cache
    /// and no new file, just one more kind of thing that can live in it.
    ///
    /// Default time tolerance, deliberately not forced to zero: an exact
    /// frame is not the point, a representative one is, and leaving AVFoundation
    /// free to snap to the nearest keyframe is what keeps a one-off grab fast.
    static func frame(fromVideoAt url: URL) -> NSImage? {
        if let cached = imageCache.object(forKey: url as NSURL) { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// First frame of a background, keyed if the theme asked for it.
    ///
    /// Loaded through `AnimatedImage` so the preview gets the same keyed pixels
    /// the panel does — a skin whose green screen is removed at runtime must not
    /// show up green here. The cap insets those frames carry would nine-slice on
    /// draw, so the frame is re-wrapped as a plain image first.
    static func still(_ background: BackgroundImage) -> NSImage? {
        guard let frame = AnimatedImage.load(background)?.frames.first else { return nil }
        var rect = NSRect(origin: .zero, size: frame.size)
        guard let cgImage = frame.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: frame.size)
    }

    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let output = NSImage(size: image.size)
        output.lockFocus()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        output.unlockFocus()
        return output
    }

    static func clearCache() {
        imageCache.removeAllObjects()
    }
}
