// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import UniformTypeIdentifiers
@testable import GroundControl

/// An animated skin's silhouette changes from frame to frame, and a mask can
/// only take pixels away. One sampled from a single frame therefore clips
/// whatever a later frame moves into, and goes on swallowing clicks where the
/// art has since moved away.
@MainActor
final class MaskUnionTests: XCTestCase {
    private var dir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mask-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Half an image of solid artwork on a green field, moving from the top of
    /// the frame to the bottom — the same thing the unicorn skin does.
    private func makeMovingSkin() throws -> URL {
        let side = 100
        func frame(fillingTopHalf: Bool) throws -> CGImage {
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            for y in 0..<side {
                for x in 0..<side {
                    let index = (y * side + x) * 4
                    let solid = fillingTopHalf ? y >= side / 2 : y < side / 2
                    pixels[index] = solid ? 220 : 0
                    pixels[index + 1] = solid ? 210 : 255
                    pixels[index + 2] = solid ? 230 : 0
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

        let url = dir.appendingPathComponent("skin.gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            2,
            nil
        ))
        let timing = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]]
        CGImageDestinationAddImage(destination, try frame(fillingTopHalf: true), timing as CFDictionary)
        CGImageDestinationAddImage(destination, try frame(fillingTopHalf: false), timing as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func shapedTheme() throws -> Theme {
        let url = try makeMovingSkin()
        var theme = DefaultTheme.theme
        theme.window = Theme.Window(
            shape: BackgroundImage(
                url: url,
                mode: .stretch,
                capInsets: NSEdgeInsets(),
                removeBackground: .color(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
            ),
            locksAspect: true,
            aspectRatio: 1,
            naturalWidth: 100
        )
        return theme
    }

    /// The silhouette must cover the artwork's whole loop. Sampled from one
    /// frame, half of this skin is masked away for half of its animation.
    func testSilhouetteCoversEveryFrameOfTheLoop() throws {
        let view = PanelBackgroundView()
        view.apply(theme: try shapedTheme())
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        view.layoutSubtreeIfNeeded()

        let mask = try XCTUnwrap(view.shapeMask)
        let quarter = mask.pixelsHigh / 4
        let top = mask.colorAt(x: mask.pixelsWide / 2, y: quarter)?.alphaComponent ?? 0
        let bottom = mask.colorAt(x: mask.pixelsWide / 2, y: quarter * 3)?.alphaComponent ?? 0

        XCTAssertGreaterThan(top, 0.5, "the half drawn in one frame was masked away")
        XCTAssertGreaterThan(bottom, 0.5, "the half drawn in the other frame was masked away")
    }

    /// The layer underneath must not paint a rectangle a shaped theme refuses
    /// to draw — that is what turned the vacated pixels black rather than
    /// leaving them empty.
    func testShapedPanelHasNoOpaqueBackingColour() throws {
        let view = PanelBackgroundView()
        view.apply(theme: try shapedTheme())
        let shaped = NSColor(cgColor: try XCTUnwrap(view.layer?.backgroundColor))
        XCTAssertEqual(shaped?.alphaComponent, 0, "a shaped panel is painting a background it should not")

        view.apply(theme: DefaultTheme.theme)
        let plain = NSColor(cgColor: try XCTUnwrap(view.layer?.backgroundColor))
        XCTAssertEqual(plain?.alphaComponent, 1, "an ordinary panel still needs its background")
    }
}
