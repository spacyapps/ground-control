// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Works out which transparent pixels a skin *encloses*, as opposed to which
/// ones are simply outside it.
///
/// A window's silhouette comes from its artwork's alpha, which is right until
/// the artwork is a picture frame. Its middle is transparent on purpose — that
/// is what lets the rows show through — but the silhouette then has a hole
/// exactly where the rows live, and the mask cuts them away. The panel comes up
/// as a frame around nothing.
///
/// Outside and inside are both transparent, so colour cannot tell them apart.
/// Reachability can: anything you can walk to from the border is outside, and
/// anything you cannot is enclosed.
enum SkinInterior {
    /// Pixels the artwork encloses, and — as a side effect — those pixels made
    /// opaque in `mask`, so the window covers its own middle.
    ///
    /// Returns an empty array when nothing is enclosed, which is every ordinary
    /// skin: a solid one has no holes, and a shape open at one edge has no
    /// inside.
    @discardableResult
    static func fillEnclosed(in mask: NSBitmapImageRep) -> [Bool] {
        let width = mask.pixelsWide, height = mask.pixelsHigh
        guard width > 2, height > 2, let pixels = mask.bitmapData else { return [] }

        let count = width * height
        let stride = mask.bytesPerRow
        let samples = mask.samplesPerPixel
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[y * stride + x * samples + 3] }

        let outside = reachableFromBorder(width: width, height: height, alpha: alpha)

        var enclosed = [Bool](repeating: false, count: count)
        var found = false
        for y in 0..<height {
            for x in 0..<width {
                let cell = y * width + x
                guard !outside[cell], alpha(x, y) <= 128 else { continue }
                enclosed[cell] = true
                found = true
                pixels[y * stride + x * samples + 3] = 255
            }
        }
        return found ? enclosed : []
    }

    /// Everything a walk from the border can reach without crossing the
    /// artwork — which is the definition of "outside it".
    private static func reachableFromBorder(width: Int,
                                            height: Int,
                                            alpha: (Int, Int) -> UInt8) -> [Bool] {
        var outside = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        for x in 0..<width {
            stack.append(x)
            stack.append((height - 1) * width + x)
        }
        for y in 0..<height {
            stack.append(y * width)
            stack.append(y * width + width - 1)
        }

        while let cell = stack.popLast() {
            if outside[cell] { continue }
            let x = cell % width, y = cell / width
            guard alpha(x, y) <= 128 else { continue }
            outside[cell] = true

            if x > 0 { stack.append(cell - 1) }
            if x < width - 1 { stack.append(cell + 1) }
            if y > 0 { stack.append(cell - width) }
            if y < height - 1 { stack.append(cell + width) }
        }
        return outside
    }

    /// The enclosed area as a paintable image, so the panel can put a body
    /// behind its rows without also painting the gaps around the artwork —
    /// where an animated frame has moved and left nothing, and a fill would
    /// show as a dark fringe against the desktop.
    static func body(from enclosed: [Bool],
                     width: Int,
                     height: Int,
                     colour: NSColor) -> NSImage? {
        guard !enclosed.isEmpty, width > 0, height > 0,
              let srgb = colour.usingColorSpace(.sRGB) else { return nil }

        let alpha = srgb.alphaComponent
        let red = UInt8(srgb.redComponent * alpha * 255)
        let green = UInt8(srgb.greenComponent * alpha * 255)
        let blue = UInt8(srgb.blueComponent * alpha * 255)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for cell in 0..<(width * height) where enclosed[cell] {
            let index = cell * 4
            pixels[index] = red
            pixels[index + 1] = green
            pixels[index + 2] = blue
            pixels[index + 3] = UInt8(alpha * 255)
        }

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else { return nil }

        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }
}
