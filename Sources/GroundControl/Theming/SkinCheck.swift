// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Checks a skin can actually be seen through, before it is trusted to be.
///
/// `window.overlay` paints the artwork over the rows, which only works if the
/// artwork's middle keys out to nothing. Get that wrong — fill the centre with a
/// slightly different green, or forget to fill it at all — and the frame covers
/// the whole panel. Not "looks a bit off": the app disappears, with no error and
/// nothing on screen to explain it.
///
/// So the centre is measured rather than assumed, and a skin that would blank
/// the panel is drawn behind the rows instead, which is merely imperfect.
enum SkinCheck {
    /// Fraction of the middle that must key out for an overlay to be usable.
    ///
    /// Not all of it: artwork legitimately reaches inward — a bevel, a mascot
    /// leaning across a corner, a vignette — and a hard "must be completely
    /// clear" would reject exactly the skins the mode exists for.
    private static let requiredClearance = 0.5

    /// The middle half, which is where the rows and their text live.
    private static let sampled = 0.25...0.75

    /// True when the skin's centre is solid enough that drawing it over the
    /// rows would hide them.
    static func hidesContent(_ background: BackgroundImage) -> Bool {
        guard let coverage = centreCoverage(background) else { return false }
        return coverage > (1 - requiredClearance)
    }

    /// Proportion of the middle that survives keying, 0 (all clear) to 1 (solid).
    /// Nil when the artwork cannot be read, where refusing to judge is right.
    static func centreCoverage(_ background: BackgroundImage) -> Double? {
        guard let frame = AnimatedImage.load(background)?.frames.first else { return nil }
        var rect = NSRect(origin: .zero, size: frame.size)
        guard let image = frame.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              image.width > 8, image.height > 8 else { return nil }

        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let columns = Int(Double(image.width) * sampled.lowerBound)
            ..< Int(Double(image.width) * sampled.upperBound)
        let rows = Int(Double(image.height) * sampled.lowerBound)
            ..< Int(Double(image.height) * sampled.upperBound)
        guard !columns.isEmpty, !rows.isEmpty else { return nil }

        var solid = 0
        for y in rows {
            for x in columns where pixels[(y * image.width + x) * 4 + 3] > 128 {
                solid += 1
            }
        }
        return Double(solid) / Double(columns.count * rows.count)
    }
}
