// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
import ImageIO
@testable import GroundControl

/// The shipped themes, checked against their own artwork.
///
/// Every assertion here is a bug that actually happened, and each one cost real
/// time to find by eye:
///
/// - `capInsets: 75` left on a 900px redraw whose corner tower runs 190px deep,
///   so the tower was cut in half and tiled down both edges;
/// - `contentInset` carried over from art with a thicker border, leaving the
///   panel floating inside the frame with desktop showing through;
/// - an animation whose silhouette breathed 17px, which read as the panel
///   changing size while it played;
/// - a loop that grew 2,300 pixels of artwork and snapped back at the wrap;
/// - chroma keying that left magenta speckles along every edge.
///
/// A manifest and its artwork drift apart silently: the theme still loads, the
/// panel still draws, and it simply looks wrong. Nothing else notices.
final class ThemeIntegrityTests: XCTestCase {
    /// Both roots. `Themes/` ships inside the app; the other is demo
    /// weight included only in alpha builds — but an unchecked theme rots, and
    /// the whole point of these tests is that nothing else notices when it does.
    private static var themeRoots: [URL] {
        ThemeLocations.roots
    }

    private struct Shipped {
        let name: String
        let folder: URL
        let theme: Theme
    }

    /// Every theme folder that ships inside the app.
    private func shippedThemes() throws -> [Shipped] {
        let folders = try Self.themeRoots
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .flatMap {
                try FileManager.default.contentsOfDirectory(
                    at: $0,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("theme.json").path) }

        XCTAssertFalse(folders.isEmpty, "no themes found in \(Self.themeRoots.map(\.lastPathComponent))")
        return folders.map {
            Shipped(name: $0.lastPathComponent, folder: $0, theme: ThemeLoader.loadTheme(from: $0))
        }
    }

    // MARK: - The manifest itself

    /// A theme that quietly falls back is the worst outcome — the author sees
    /// "my theme did nothing" with no clue why. `warnings` is how a theme says
    /// what happened, so a shipped one must have nothing to say.
    func testEveryShippedThemeLoadsWithoutComplaint() throws {
        for case let shipped in try shippedThemes() {
            let (name, theme) = (shipped.name, shipped.theme)
            XCTAssertTrue(
                theme.warnings.isEmpty,
                "\(name): \(theme.warnings.joined(separator: " | "))"
            )
        }
    }

    /// A manifest naming a file that is not there draws nothing and says
    /// nothing. Deleting an unused asset is easy; deleting a used one should
    /// not be.
    func testEveryReferencedAssetExists() throws {
        for case let shipped in try shippedThemes() {
            let (name, folder) = (shipped.name, shipped.folder)
            let manifest = folder.appendingPathComponent("theme.json")
            let text = try String(contentsOf: manifest, encoding: .utf8)
            let names = try NSRegularExpression(pattern: #""([^"]+\.(?:png|gif|jpg|jpeg|mp4|mov|webp))""#)
                .matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }

            for asset in Set(names) {
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: folder.appendingPathComponent(asset).path),
                    "\(name) names \(asset), which is not in the folder"
                )
            }
        }
    }

    // MARK: - Nine-grid geometry

    /// Caps are points, drawn 1:1. A cap that stops short of the ornament sends
    /// the rest of it into the *tiled* strip, which then repeats it along the
    /// edge — the single most expensive mistake this project has made.
    func testCapsClearTheOrnament() throws {
        for case let shipped in try shippedThemes() {
            let (name, theme) = (shipped.name, shipped.theme)
            guard let shape = theme.window.shape, !theme.window.locksAspect else { continue }
            let caps = shape.capInsets
            guard caps.left > 0 else { continue }
            guard let art = try frame(of: shape, at: 0) else { continue }

            let ornament = ornamentEnd(in: art)
            XCTAssertGreaterThanOrEqual(
                Int(caps.left),
                ornament,
                "\(name): caps are \(Int(caps.left)) but the ornament runs to \(ornament)px — "
                    + "the remainder will tile down the edge"
            )
            // And not so far past it that the frame swallows the panel.
            XCTAssertLessThanOrEqual(
                caps.left * 2,
                400,
                "\(name): \(Int(caps.left))pt caps need a \(Int(caps.left * 2))pt panel to draw in"
            )
        }
    }

    // MARK: - Animation

    /// Every frame must have the same outer bounds. Frames generated one from
    /// the next drift, and on screen that reads as the panel changing size.
    func testAnimatedArtHoldsItsSilhouette() throws {
        for case let shipped in try shippedThemes() {
            let (name, theme) = (shipped.name, shipped.theme)
            guard let shape = theme.window.shape else { continue }
            let boxes = try silhouettes(of: shape)
            guard boxes.count > 1 else { continue }

            let widths = boxes.map(\.width), heights = boxes.map(\.height)
            let spread = max((widths.max() ?? 0) - (widths.min() ?? 0),
                             (heights.max() ?? 0) - (heights.min() ?? 0))
            XCTAssertLessThanOrEqual(
                spread,
                20,
                "\(name): the silhouette varies by \(spread)px across frames — it will look "
                + "like the panel is resizing itself"
            )
        }
    }

    /// The last frame has to flow into the first. A loop that grows and snaps
    /// back is the signature of frames made in sequence rather than as a cycle.
    func testAnimatedArtClosesItsLoop() throws {
        for case let shipped in try shippedThemes() {
            let (name, theme) = (shipped.name, shipped.theme)
            guard let shape = theme.window.shape else { continue }
            let inks = try inkCounts(of: shape)
            guard let first = inks.first, let last = inks.last, inks.count > 1, first > 0 else { continue }

            let drift = Double(abs(first - last)) / Double(first)
            XCTAssertLessThan(
                drift,
                0.03,
                "\(name): the loop ends \(Int(drift * 100))% heavier than it starts"
            )
        }
    }

    // MARK: - Keying

    /// Keying leaves two kinds of mess: green the key missed, and magenta where
    /// the un-multiply amplified what was left. Both show as speckles along
    /// every edge, and both are invisible until the artwork is on a dark panel.
    func testKeyedArtIsClean() throws {
        for case let shipped in try shippedThemes() {
            let (name, theme) = (shipped.name, shipped.theme)
            guard let shape = theme.window.shape, shape.removeBackground != nil else { continue }
            guard let art = try frame(of: shape, at: 0) else { continue }

            // Only the soft edge band. Keying artefacts live where alpha is
            // partial — that is where the un-multiply divides a pixel's colour
            // by a small number and amplifies whatever was left. Judging opaque
            // pixels instead flagged the unicorn frame's own purple as residue,
            // because purple *is* red and blue against low green.
            var edge = 0, fringe = 0
            forEachPixel(art) { red, green, blue, alpha in
                guard alpha > 60, alpha < 200 else { return }
                edge += 1
                // Un-multiplied, so a faint edge pixel is judged on its colour
                // rather than on how little of it there is.
                let scale = 255.0 / Double(alpha)
                let unlitRed = Double(red) * scale
                let unlitGreen = Double(green) * scale
                let unlitBlue = Double(blue) * scale
                if unlitGreen > unlitRed + 60, unlitGreen > unlitBlue + 60 {
                    fringe += 1                                      // key left behind
                }
                if unlitRed > unlitGreen + 60, unlitBlue > unlitGreen + 60 {
                    fringe += 1                                      // its opposite
                }
            }
            guard edge > 200 else { continue }
            let share = Double(fringe) / Double(edge)
            XCTAssertLessThan(
                share,
                0.08,
                "\(name): \(fringe) of \(edge) soft-edge pixels are keying residue"
            )
        }
    }

    // MARK: - Measuring

    /// The keyed frame at `index`, as premultiplied RGBA.
    private func frame(of shape: BackgroundImage, at index: Int) throws -> (CGImage, [UInt8])? {
        guard let source = CGImageSourceCreateWithURL(shape.url as CFURL, nil),
              index < CGImageSourceGetCount(source),
              let raw = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
        let keyed = shape.removeBackground.map { ImageKeyer.apply($0, to: raw) } ?? raw
        return (keyed, pixels(of: keyed))
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    private func forEachPixel(_ art: (CGImage, [UInt8]), _ body: (UInt8, UInt8, UInt8, UInt8) -> Void) {
        let (image, data) = art
        for cell in 0..<(image.width * image.height) {
            let index = cell * 4
            body(data[index], data[index + 1], data[index + 2], data[index + 3])
        }
    }

    /// Where the ornate corner ends and the plain girder begins, measured by how
    /// deep the artwork hangs in each column rather than by its outline — a
    /// tower with a flat top fools the outline and reads as column 10.
    private func ornamentEnd(in art: (CGImage, [UInt8])) -> Int {
        let (image, data) = art
        let width = image.width, height = image.height
        func solid(_ x: Int, _ y: Int) -> Bool { data[((height - 1 - y) * width + x) * 4 + 3] > 120 }

        var depth = [Int](repeating: 0, count: width)
        for x in 0..<width {
            for y in 0..<(height / 2) where solid(x, y) { depth[x] = y }
        }
        let middle = width / 2
        let girder = depth[(middle - 10)...(middle + 10)].min() ?? 0
        guard girder > 0 else { return 0 }
        let last = (0..<(width / 2)).last { depth[$0] > girder + 8 }
        return (last ?? 0) + 1
    }

    private func silhouettes(of shape: BackgroundImage) throws -> [(width: Int, height: Int)] {
        try eachFrame(of: shape) { image, data in
            let width = image.width, height = image.height
            var minX = width, maxX = -1, minY = height, maxY = -1
            for y in 0..<height {
                for x in 0..<width where data[(y * width + x) * 4 + 3] > 120 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            return (max(0, maxX - minX), max(0, maxY - minY))
        }
    }

    private func inkCounts(of shape: BackgroundImage) throws -> [Int] {
        try eachFrame(of: shape) { image, data in
            var ink = 0
            for cell in 0..<(image.width * image.height) where data[cell * 4 + 3] > 120 { ink += 1 }
            return ink
        }
    }

    /// Samples rather than every frame: a 60-frame skin measured whole makes
    /// this the slowest test in the suite for no extra confidence.
    private func eachFrame<T>(of shape: BackgroundImage,
                              _ body: (CGImage, [UInt8]) -> T) throws -> [T] {
        guard let source = CGImageSourceCreateWithURL(shape.url as CFURL, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return [] }
        let wanted = Set([0] + stride(from: 0, to: count, by: max(1, count / 6)).map { $0 } + [count - 1])
        return wanted.sorted().compactMap { index in
            guard let raw = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            let keyed = shape.removeBackground.map { ImageKeyer.apply($0, to: raw) } ?? raw
            return body(keyed, pixels(of: keyed))
        }
    }
}
