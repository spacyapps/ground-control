// SPDX-License-Identifier: AGPL-3.0-or-later
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
    /// The opening the artwork encloses, and — as a side effect — those pixels
    /// made opaque in `mask`, so the window covers its own middle.
    ///
    /// Only the *largest* enclosed region counts. Decorative artwork traps small
    /// pockets all over the place — between a unicorn's horn and the band it
    /// leans on, say — and those are gaps you should see straight through. Left
    /// in, they bloat the opening to nearly the whole panel and get painted with
    /// the panel's colour, which shows as dark flecks caught in the artwork.
    ///
    /// Returns an empty array when nothing is enclosed, which is every ordinary
    /// skin: a solid one has no holes, and a shape open at one edge has no
    /// inside.
    @discardableResult
    static func fillEnclosed(in mask: NSBitmapImageRep) -> [Bool] {
        let width = mask.pixelsWide, height = mask.pixelsHigh
        guard width > 2, height > 2, let pixels = mask.bitmapData else { return [] }

        let stride = mask.bytesPerRow
        let samples = mask.samplesPerPixel
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[y * stride + x * samples + 3] }

        let outside = reachableFromBorder(width: width, height: height, alpha: alpha)
        guard let opening = largestEnclosedRegion(
            width: width,
            height: height,
            alpha: alpha,
            outside: outside
        ) else { return [] }

        for cell in 0..<(width * height) where opening[cell] {
            let x = cell % width, y = cell / width
            pixels[y * stride + x * samples + 3] = 255
        }
        return opening
    }

    /// The biggest pocket the artwork closes off, found by walking each in turn.
    private static func largestEnclosedRegion(width: Int,
                                              height: Int,
                                              alpha: (Int, Int) -> UInt8,
                                              outside: [Bool]) -> [Bool]? {
        let count = width * height
        var seen = [Bool](repeating: false, count: count)
        var best: [Int] = []

        for start in 0..<count {
            guard !seen[start], !outside[start],
                  alpha(start % width, start / width) <= 128 else { continue }

            var region: [Int] = []
            var stack = [start]
            seen[start] = true
            while let cell = stack.popLast() {
                region.append(cell)
                let x = cell % width, y = cell / width
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let next = ny * width + nx
                    guard !seen[next], !outside[next], alpha(nx, ny) <= 128 else { continue }
                    seen[next] = true
                    stack.append(next)
                }
            }
            if region.count > best.count { best = region }
        }

        guard !best.isEmpty else { return nil }
        var mask = [Bool](repeating: false, count: count)
        for cell in best { mask[cell] = true }
        return mask
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

    /// The body an overlay skin puts behind its rows.
    ///
    /// `enclosed` — from `fillEnclosed` — follows the frame's real inner edge
    /// for the width and the top. The bottom, though, should end with the rows:
    /// below the last one is the frame's own floor and its greebles, and a
    /// panel body carried down there just backs the deck with black and leaks
    /// onto the desktop through its grating. `contentBottom` is where it goes
    /// solid to; the enclosed area is size-dependent and the clip is not, so
    /// the caller keeps the array and re-clips it as the rows grow.
    ///
    /// `fadeOver`, when non-zero, softens that cut: the body ramps from solid
    /// at `contentBottom` to nothing over that many points, so an overlay skin
    /// can keep a solid ground under the analyser and dissolve it into the
    /// frame across the first row.
    static func overlayBody(from enclosed: [Bool],
                            size: NSSize,
                            contentBottom: CGFloat,
                            colour: NSColor,
                            fadeOver: CGFloat = 0) -> NSImage? {
        let width = Int(size.width), height = Int(size.height)
        guard !enclosed.isEmpty, enclosed.count == width * height else { return nil }

        let solid = max(0, contentBottom)
        let clear = solid + max(0, fadeOver)
        var coverage = [CGFloat](repeating: 0, count: width * height)
        for y in 0..<height {
            let scale = verticalScale(y: CGFloat(y), solid: solid, clear: clear)
            guard scale > 0 else { continue }
            for x in 0..<width where enclosed[y * width + x] {
                coverage[y * width + x] = scale
            }
        }
        return render(coverage: coverage, width: width, height: height, colour: colour)
    }

    /// 1 up to `solid`, 0 at `clear` and below, a straight line between.
    /// `clear == solid` is the hard cut.
    private static func verticalScale(y: CGFloat, solid: CGFloat, clear: CGFloat) -> CGFloat {
        if y <= solid { return 1 }
        if y >= clear { return 0 }
        return 1 - (y - solid) / (clear - solid)
    }

    /// The enclosed area as a paintable image, so the panel can put a body
    /// behind its rows without also painting the gaps around the artwork —
    /// where an animated frame has moved and left nothing, and a fill would
    /// show as a dark fringe against the desktop.
    static func body(from enclosed: [Bool],
                     width: Int,
                     height: Int,
                     colour: NSColor) -> NSImage? {
        guard !enclosed.isEmpty else { return nil }
        let coverage: [CGFloat] = enclosed.map { $0 ? 1 : 0 }
        return render(coverage: coverage, width: width, height: height, colour: colour)
    }

    /// Rasterises a per-cell coverage (0…1) as a premultiplied image in
    /// `colour` — a hard 0/1 for the plain body, a vertical ramp for a faded
    /// one.
    private static func render(coverage: [CGFloat],
                               width: Int,
                               height: Int,
                               colour: NSColor) -> NSImage? {
        guard width > 0, height > 0, coverage.count == width * height,
              let srgb = colour.usingColorSpace(.sRGB) else { return nil }

        let base = srgb.alphaComponent
        let red = srgb.redComponent, green = srgb.greenComponent, blue = srgb.blueComponent

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for cell in 0..<(width * height) {
            let alpha = base * coverage[cell]
            guard alpha > 0 else { continue }
            let index = cell * 4
            pixels[index] = UInt8(red * alpha * 255)
            pixels[index + 1] = UInt8(green * alpha * 255)
            pixels[index + 2] = UInt8(blue * alpha * 255)
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
