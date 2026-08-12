// SPDX-License-Identifier: GPL-3.0-or-later
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

    /// The body is painted only where the frame encloses, never across the gaps
    /// around it — an animated frame leaves those, and a full-layer fill would
    /// show them as a dark fringe against the desktop.
    func testBodyCoversOnlyTheEnclosedArea() throws {
        let rep = try mask { x, y in
            let onBand = (10..<50).contains(x) && (10..<50).contains(y)
                && !((16..<44).contains(x) && (16..<44).contains(y))
            return !onBand
        }
        let enclosed = SkinInterior.fillEnclosed(in: rep)
        let body = try XCTUnwrap(SkinInterior.body(
            from: enclosed,
            width: side,
            height: side,
            colour: NSColor(srgbRed: 0.1, green: 0.08, blue: 0.13, alpha: 1)
        ))

        var rect = NSRect(origin: .zero, size: body.size)
        let cgImage = try XCTUnwrap(body.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let painted = NSBitmapImageRep(cgImage: cgImage)
        XCTAssertGreaterThan(painted.colorAt(x: side / 2, y: side / 2)?.alphaComponent ?? 0, 0.5)
        XCTAssertEqual(painted.colorAt(x: 2, y: 2)?.alphaComponent ?? 1, 0, accuracy: 0.01)
    }

    func testNothingEnclosedMeansNoBody() {
        XCTAssertNil(SkinInterior.body(from: [], width: side, height: side, colour: .black))
    }
}
