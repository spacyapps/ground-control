// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// A window's silhouette comes from its artwork's alpha, which is right until
/// the artwork is a picture frame: its middle is transparent on purpose, so the
/// silhouette has a hole exactly where the rows live and the mask cuts them
/// away. The panel comes up as a frame around nothing.
final class SkinInteriorTests: XCTestCase {
    private let side = 60

    /// `carve` decides which pixels are transparent.
    private func mask(_ carve: (Int, Int) -> Bool) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let pixels = try XCTUnwrap(rep.bitmapData)
        for y in 0..<side {
            for x in 0..<side {
                let index = y * rep.bytesPerRow + x * rep.samplesPerPixel
                let clear = carve(x, y)
                pixels[index] = clear ? 0 : 180
                pixels[index + 1] = clear ? 0 : 180
                pixels[index + 2] = clear ? 0 : 180
                pixels[index + 3] = clear ? 0 : 255
            }
        }
        return rep
    }

    private func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> UInt8 {
        let pixels = try XCTUnwrap(rep.bitmapData)
        return pixels[y * rep.bytesPerRow + x * rep.samplesPerPixel + 3]
    }

    /// A picture frame: transparent outside, transparent middle, solid band.
    func testFrameMiddleIsFilledIn() throws {
        let rep = try mask { x, y in
            let onBand = (10..<50).contains(x) && (10..<50).contains(y)
                && !((16..<44).contains(x) && (16..<44).contains(y))
            return !onBand
        }
        XCTAssertEqual(try alpha(rep, side / 2, side / 2), 0, "the middle starts out empty")

        let enclosed = SkinInterior.fillEnclosed(in: rep)
        XCTAssertFalse(enclosed.isEmpty)
        XCTAssertEqual(try alpha(rep, side / 2, side / 2), 255, "the middle was not filled in")
        XCTAssertEqual(try alpha(rep, 2, 2), 0, "the outside must stay outside")
    }

    /// Outside and inside are both transparent, so only reachability separates
    /// them: a band broken at one edge has no inside at all.
    func testAnOpenShapeEnclosesNothing() throws {
        let rep = try mask { x, y in
            let onBand = (10..<50).contains(x) && (10..<50).contains(y)
                && !((16..<44).contains(x) && (16..<44).contains(y))
            let gap = (26..<34).contains(x) && y >= 44      // a doorway in the bottom edge
            return !onBand || gap
        }
        XCTAssertTrue(SkinInterior.fillEnclosed(in: rep).isEmpty, "an open shape has no inside")
        XCTAssertEqual(try alpha(rep, side / 2, side / 2), 0, "and nothing should have been filled")
    }

    func testSolidArtworkEnclosesNothing() throws {
        let rep = try mask { _, _ in false }
        XCTAssertTrue(SkinInterior.fillEnclosed(in: rep).isEmpty)
    }

    /// The centre-column alpha at row `y` of a rendered body.
    private func coverage(_ image: NSImage, at y: Int) throws -> CGFloat {
        var rect = NSRect(origin: .zero, size: image.size)
        let painted = NSBitmapImageRep(
            cgImage: try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        )
        return painted.colorAt(x: side / 2, y: y)?.alphaComponent ?? -1
    }

    private func aBody(top: CGFloat, bottom: CGFloat, fade: CGFloat = 0) throws -> NSImage {
        try XCTUnwrap(SkinInterior.solidBody(
            size: NSSize(width: side, height: side),
            contentTop: top,
            contentBottom: bottom,
            colour: NSColor(srgbRed: 0.1, green: 0.08, blue: 0.13, alpha: 1),
            fadeOver: fade
        ))
    }

    /// The body ends with the rows — `contentBottom` — not with the frame, so
    /// it never backs the deck below them.
    func testSolidBodyEndsWithTheRows() throws {
        let body = try aBody(top: 0, bottom: 30)
        XCTAssertGreaterThan(try coverage(body, at: 22), 0.5, "backed while the rows are")
        XCTAssertEqual(try coverage(body, at: 38), 0, accuracy: 0.05, "nothing past the rows")
    }

    /// `contentTop` holds the fill below the band where a corner decoration
    /// sits — nothing is painted above it.
    func testSolidBodyStartsAtContentTop() throws {
        let body = try aBody(top: 20, bottom: 50)
        XCTAssertEqual(try coverage(body, at: 10), 0, accuracy: 0.05, "clear above contentTop")
        XCTAssertGreaterThan(try coverage(body, at: 30), 0.5, "solid below it")
    }

    /// A taller `contentBottom` fills more of the panel — the body follows the
    /// rows as they grow.
    func testSolidBodyFollowsTheRows() throws {
        let short = try aBody(top: 0, bottom: 20)
        let tall = try aBody(top: 0, bottom: CGFloat(side))
        XCTAssertNotEqual(short.tiffRepresentation, tall.tiffRepresentation)
    }

    /// `fadeOver` softens the cut: solid at `contentBottom`, half way at the
    /// band's midpoint, gone by its end.
    func testSolidBodyRampsAcrossTheFadeBand() throws {
        let body = try aBody(top: 0, bottom: 20, fade: 16)
        XCTAssertEqual(try coverage(body, at: 18), 1, accuracy: 0.05, "solid to contentBottom")
        XCTAssertEqual(try coverage(body, at: 28), 0.5, accuracy: 0.2, "half way across the band")
        XCTAssertEqual(try coverage(body, at: 40), 0, accuracy: 0.05, "gone past the band")
    }

    func testSolidBodyRejectsAZeroSize() {
        XCTAssertNil(SkinInterior.solidBody(
            size: .zero, contentTop: 0, contentBottom: 10, colour: .black
        ))
    }
}
