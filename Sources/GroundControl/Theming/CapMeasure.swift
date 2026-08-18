// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import ImageIO

/// Measures where a frame's corner artwork ends, which is the one number a
/// theme author cannot guess and cannot see.
///
/// `capInsets` decides which parts of the picture never scale. Set them short
/// and the rest of the corner falls into the *tiled* strip, which then repeats
/// it along the edge — a mascot marching down the side of the panel. It has
/// happened, with a space station's tower.
///
/// The repo's `fit-frame-art.swift` measured this by scanning columns in the
/// left half only, which is right for symmetrical art and silently wrong for
/// anything else: on a frame whose deepest ornament sat top-right it reported
/// 69 where the true answer was 100. This measures all four edges from both
/// ends, so where the ornament happens to live cannot change the answer.
enum CapMeasure {
    /// What each side needs, in artwork pixels.
    struct Result: Equatable {
        var top: Int
        var left: Int
        var bottom: Int
        var right: Int
    }

    /// Ornament is anything whose artwork profile differs from the middle of
    /// that edge — the middle being, by construction, the plain repeating part.
    static func measure(_ image: CGImage) -> Result? {
        guard let pixels = Pixels(image) else { return nil }
        let horizontal = pixels.edge(vertical: false)
        let vertical = pixels.edge(vertical: true)
        return Result(
            top: vertical.lead,
            left: horizontal.lead,
            bottom: vertical.trail,
            right: horizontal.trail
        )
    }

    /// First frame of whatever the theme points at, animated or not.
    static func measure(contentsOf url: URL) -> Result? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return measure(image)
    }

    private struct Pixels {
        let width: Int
        let height: Int
        private let data: [UInt8]

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            data = buffer
        }

        /// Transparent, or the flat key colour the app cuts out at load, both
        /// count as "not artwork" — the key is still present at this stage.
        func isArtwork(_ x: Int, _ y: Int) -> Bool {
            let base = (y * width + x) * 4
            guard data[base + 3] >= 40 else { return false }
            let red = Int(data[base]), green = Int(data[base + 1]), blue = Int(data[base + 2])
            let keyed = green > 150 && red < 120 && blue < 120
            return !keyed
        }

        /// How far ornament reaches in from each end of one pair of edges.
        ///
        /// `vertical: false` walks the top and bottom edges left-to-right and
        /// answers for the left and right caps; `true` walks the sides and
        /// answers for top and bottom.
        func edge(vertical: Bool) -> (lead: Int, trail: Int) {
            let along = vertical ? height : width
            let strips = [true, false]
            var lead = 0, trail = 0
            for near in strips {
                let (first, last) = reach(vertical: vertical, near: near, along: along)
                lead = max(lead, first)
                trail = max(trail, last)
            }
            return (lead, trail)
        }

        private func reach(vertical: Bool, near: Bool, along: Int) -> (Int, Int) {
            let across = vertical ? width : height
            let depth = across / 3
            func span(_ position: Int) -> (Int, Int)? {
                var lo = -1, hi = -1
                for step in 0..<depth {
                    let offset = near ? step : across - 1 - step
                    let isArt = vertical
                        ? isArtwork(offset, position)
                        : isArtwork(position, offset)
                    if isArt {
                        if lo < 0 { lo = step }
                        hi = step
                    }
                }
                return lo < 0 ? nil : (lo, hi)
            }
            // The middle third is the repeating strip by construction, so it
            // defines both what "plain" looks like and how much a plain edge is
            // allowed to vary. A decorated edge whose motif rises and falls is
            // still plain; measuring against a single middle column called all
            // of that variation ornament, and reported 171 on a frame that
            // works at 129.
            let sampleStart = along / 3, sampleEnd = along - along / 3
            let samples = (sampleStart..<sampleEnd).compactMap(span)
            guard !samples.isEmpty else { return (0, 0) }
            let lows = samples.map(\.0).sorted(), highs = samples.map(\.1).sorted()
            let reference = (lows[lows.count / 2], highs[highs.count / 2])
            let natural = max(
                lows.map { abs($0 - reference.0) }.max() ?? 0,
                highs.map { abs($0 - reference.1) }.max() ?? 0
            )
            let tolerance = natural + 4

            func plain(_ position: Int) -> Bool {
                guard let found = span(position) else { return false }
                return abs(found.0 - reference.0) <= tolerance
                    && abs(found.1 - reference.1) <= tolerance
            }
            var first = 0, last = 0
            for position in 0..<(along / 2) where !plain(position) { first = position + 1 }
            for position in stride(from: along - 1, through: along / 2, by: -1)
            where !plain(position) { last = along - position }
            return (first, last)
        }
    }
}
