// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Keying cut the background out but left a green rim around everything it cut,
/// so every shaped skin wore a faint outline. The rim is far from the key
/// colour — a grey hull edge lit green sits ~179 away, well past the 130 the key
/// band reaches — so removing it is a question of position, not colour.
final class ImageKeyerSpillTests: XCTestCase {
    private struct Pixel {
        let red: Int
        let green: Int
        let blue: Int
        let alpha: Int

        /// True when the key's colour still shows above the channels it is not
        /// made of — the definition of a green cast on a grey edge.
        var isGreenCast: Bool { green > max(red, blue) }
    }

    private let side = 60
    private let green = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)

    /// Green field, grey block, a green-lit rim on the block, and a green lamp
    /// deep inside it that must survive — the artwork's own colour, not spill.
    private func artwork() throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let inBlock = (15..<45).contains(x) && (15..<45).contains(y)
                let onRim = inBlock && ((15...16).contains(x) || (43...44).contains(x)
                    || (15...16).contains(y) || (43...44).contains(y))
                let isLamp = (28..<32).contains(x) && (28..<32).contains(y)

                let rgb: [UInt8]
                if !inBlock {
                    rgb = [0, 255, 0]
                } else if onRim {
                    rgb = [120, 190, 110]
                } else if isLamp {
                    rgb = [80, 170, 90]
                } else {
                    rgb = [130, 130, 140]
                }
                pixels[index] = rgb[0]
                pixels[index + 1] = rgb[1]
                pixels[index + 2] = rgb[2]
                pixels[index + 3] = 255
            }
        }
        return try XCTUnwrap(context(&pixels)?.makeImage())
    }

    private func context(_ pixels: inout [UInt8]) -> CGContext? {
        CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func keyed() throws -> [UInt8] {
        let image = ImageKeyer.apply(.color(green), to: try artwork())
        var out = [UInt8](repeating: 0, count: side * side * 4)
        try XCTUnwrap(context(&out)).draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return out
    }

    private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int) -> Pixel {
        let index = (y * side + x) * 4
        return Pixel(
            red: Int(pixels[index]),
            green: Int(pixels[index + 1]),
            blue: Int(pixels[index + 2]),
            alpha: Int(pixels[index + 3])
        )
    }

    /// Nothing next to the cut can be greener than the channels the key is not
    /// made of — anything above that line is bleed, and has to go.
    func testRimLosesItsGreenCast() throws {
        let rim = pixel(try keyed(), 16, 30)
        XCTAssertEqual(rim.alpha, 255, "the rim is artwork and must stay opaque")
        XCTAssertFalse(rim.isGreenCast, "rim is still green-tinted")
    }

    /// Suppressing green by colour alone would strip the artwork's own green.
    /// Distance from the cut is what separates the two.
    func testGreenDeepInsideTheArtworkSurvives() throws {
        let lamp = pixel(try keyed(), 30, 30)
        XCTAssertEqual(lamp.alpha, 255)
        XCTAssertTrue(lamp.isGreenCast, "the lamp stopped being green")
    }

    func testNeutralArtworkIsUntouched() throws {
        let body = pixel(try keyed(), 30, 20)
        XCTAssertEqual(body.red, 130)
        XCTAssertEqual(body.green, 130)
        XCTAssertEqual(body.blue, 140)
    }

    func testBackgroundIsStillCutOut() throws {
        XCTAssertEqual(pixel(try keyed(), 2, 2).alpha, 0)
    }

    /// An image with nothing keyed out must come back exactly as it went in.
    func testImageWithNoCutoutIsUnchanged() throws {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 200
            pixels[index + 1] = 40
            pixels[index + 2] = 90
            pixels[index + 3] = 255
        }
        let source = try XCTUnwrap(context(&pixels)?.makeImage())
        let result = ImageKeyer.apply(.color(green), to: source)

        var out = [UInt8](repeating: 0, count: side * side * 4)
        try XCTUnwrap(context(&out)).draw(result, in: CGRect(x: 0, y: 0, width: side, height: side))
        XCTAssertEqual(pixel(out, 30, 30).red, 200)
        XCTAssertEqual(pixel(out, 30, 30).green, 40)
        XCTAssertEqual(pixel(out, 30, 30).alpha, 255)
    }
}

/// The first version of the suppressor reached 4px and passed every test in the
/// suite above while leaving a visible green glow on a real station hull. Thin
/// artwork — solar panels, antenna mounts — picks up spill across its whole
/// width, not just along its outline, and that spill measured 10px deep.
final class DeepSpillTests: XCTestCase {
    private let side = 80

    /// A grey block whose outer 8px carry a strong green cast, on a green field.
    private func artwork() throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let inBlock = (20..<60).contains(x) && (20..<60).contains(y)
                let inCore = (28..<52).contains(x) && (28..<52).contains(y)

                let rgb: [UInt8]
                if !inBlock {
                    rgb = [0, 255, 0]
                } else if !inCore {
                    rgb = [110, 200, 100]      // strong spill, 8px deep
                } else {
                    rgb = [130, 130, 140]
                }
                pixels[index] = rgb[0]
                pixels[index + 1] = rgb[1]
                pixels[index + 2] = rgb[2]
                pixels[index + 3] = 255
            }
        }
        let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return try XCTUnwrap(context?.makeImage())
    }

    func testSpillIsCleanedThroughItsWholeDepth() throws {
        let keyed = ImageKeyer.apply(
            .color(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)),
            to: try artwork()
        )
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(keyed, in: CGRect(x: 0, y: 0, width: side, height: side))

        func excess(atRow row: Int) -> Int {
            let index = ((side - 1 - row) * side + side / 2) * 4
            return Int(pixels[index + 1]) - max(Int(pixels[index]), Int(pixels[index + 2]))
        }

        // The block starts at row 20, so row 20 + n sits n + 1 pixels from the
        // cut. Inside the full-strength core, nothing green may remain.
        for row in [21, 23, 25] {
            XCTAssertLessThanOrEqual(
                excess(atRow: row),
                8,
                "green survived \(row - 19)px from the cut, inside the core"
            )
        }

        // Beyond it the correction fades rather than stopping, so what matters
        // is that most of a strong cast (90 here) is still taken off.
        XCTAssertLessThanOrEqual(excess(atRow: 27), 25, "the fade gave up too early")

        // The grey core is far from the cut and must be untouched.
        let core = ((side - 1 - 40) * side + side / 2) * 4
        XCTAssertEqual(Int(pixels[core]), 130)
        XCTAssertEqual(Int(pixels[core + 1]), 130)
    }
}
