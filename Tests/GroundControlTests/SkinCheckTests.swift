// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// An overlay skin whose centre does not key out covers the panel completely:
/// no error, nothing on screen, and no way to tell why. So the centre is
/// measured before the skin is trusted to be drawn in front.
@MainActor
final class SkinCheckTests: XCTestCase {
    private var dir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skincheck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// `centreFill` is what the author painted in the middle: the key colour if
    /// they got it right, anything else if they did not.
    private func makeTheme(centreFill: [UInt8], overlay: Bool = true) throws -> Theme {
        let side = 100
        let border = 20
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let onFrame = x < border || y < border || x >= side - border || y >= side - border
                let rgb: [UInt8] = onFrame ? [200, 40, 200] : centreFill
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
        let image = try XCTUnwrap(context?.makeImage())
        let url = dir.appendingPathComponent("frame-\(UUID().uuidString).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        try """
        {
          "window": {
            "image": "\(url.lastPathComponent)",
            "overlay": \(overlay),
            "removeBackground": "#00FF00"
          }
        }
        """.write(to: dir.appendingPathComponent("theme.json"), atomically: true, encoding: .utf8)
        return ThemeLoader.loadTheme(from: dir)
    }

    /// The centre filled with the key colour, as the edges are: it keys out, the
    /// rows show through, overlay stands.
    func testMatchingCentreKeepsOverlay() throws {
        let theme = try makeTheme(centreFill: [0, 255, 0])
        XCTAssertTrue(theme.window.drawsOverContent)
        XCTAssertTrue(theme.warnings.isEmpty)
    }

    /// A centre filled with something else — the exact mistake this guards.
    func testSolidCentreIsDemotedRatherThanHidingThePanel() throws {
        let theme = try makeTheme(centreFill: [20, 20, 30])
        XCTAssertFalse(theme.window.drawsOverContent, "this skin would have hidden the panel")
        XCTAssertTrue(theme.window.isShaped, "it is still a perfectly good background")
        XCTAssertEqual(theme.warnings.count, 1, "and it has to say so")
    }

    /// Nearly right is still wrong: a centre keyed to a *different* green is
    /// exactly what a second pass at the artwork produces.
    func testNearMissGreenIsStillCaught() throws {
        let theme = try makeTheme(centreFill: [0, 180, 60])
        XCTAssertFalse(theme.window.drawsOverContent)
    }

    /// Artwork may legitimately reach inward — a bevel, a mascot leaning in — so
    /// the test is whether enough of the middle is clear, not all of it.
    func testPartialIntrusionIsAllowed() throws {
        let background = BackgroundImage(
            url: try XCTUnwrap(makeIntruding()),
            mode: .stretch,
            capInsets: NSEdgeInsets(),
            removeBackground: .color(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        )
        let coverage = try XCTUnwrap(SkinCheck.centreCoverage(background))
        XCTAssertGreaterThan(coverage, 0, "the intruding art should register")
        XCTAssertFalse(SkinCheck.hidesContent(background), "a bevel is not a blocked panel")
    }

    /// A frame whose art crosses a quarter of the middle.
    private func makeIntruding() throws -> URL {
        let side = 100
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let solid = x < 20 || y < 20 || x >= 80 || y >= 80 || x < 38
                pixels[index] = solid ? 200 : 0
                pixels[index + 1] = solid ? 40 : 255
                pixels[index + 2] = solid ? 200 : 0
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
        let image = try XCTUnwrap(context?.makeImage())
        let url = dir.appendingPathComponent("intruding.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// A skin that never asked to be in front is not judged at all.
    func testBackgroundSkinsAreNotChecked() throws {
        let theme = try makeTheme(centreFill: [20, 20, 30], overlay: false)
        XCTAssertTrue(theme.warnings.isEmpty)
    }
}
