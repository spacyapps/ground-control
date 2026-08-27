// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import GroundControl

/// `window.image` — the frame skin — has always accepted `.apng` in
/// `AssetResolver.imageExtensions`, and the nine-slice/animation pipeline
/// never branches on file format, only on `CGImageSourceGetCount`. So APNG
/// was already usable for the frame, in principle, the whole time it took
/// GIF-only test coverage — this proves the one fact that actually matters:
/// `AnimatedImage` recognises a real multi-frame APNG as animated, the same
/// way it already does for GIF. Everything downstream (tiling, elapsed-based
/// frame selection, orientation) is proven format-agnostic by the existing
/// GIF-based tests, since none of that code reads the file's extension.
final class AnimatedImageFormatTests: XCTestCase {
    /// Two frames, red then blue, written as a genuine multi-frame PNG —
    /// not a `.gif` renamed to `.apng`, the actual APNG chunks ImageIO
    /// produces from multiple `CGImageDestinationAddImage` calls.
    private func animatedAPNG(side: Int = 20) throws -> URL {
        func frame(red: UInt8, blue: UInt8) throws -> CGImage {
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            for pixel in stride(from: 0, to: pixels.count, by: 4) {
                pixels[pixel] = red; pixels[pixel + 2] = blue; pixels[pixel + 3] = 255
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
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "animated-\(UUID().uuidString).apng")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 2, nil
        ))
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
        ] as CFDictionary)
        for image in [try frame(red: 255, blue: 0), try frame(red: 0, blue: 255)] {
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGDelayTime: 0.1,
                    kCGImagePropertyAPNGUnclampedDelayTime: 0.1
                ]
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testAPNGIsRecognisedAsAnimated() throws {
        let url = try animatedAPNG()
        // Confirm the fixture is genuinely multi-frame before trusting the
        // rest of the test — a mistake here would silently prove nothing.
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2, "fixture must actually be multi-frame")

        let background = BackgroundImage(url: url, mode: .tile, capInsets: NSEdgeInsets())
        let animated = try XCTUnwrap(AnimatedImage.load(background))
        XCTAssertTrue(animated.isAnimated)
        XCTAssertEqual(animated.frames.count, 2)
        XCTAssertTrue(BackgroundRenderer.isAnimated(background))
    }

    /// The delay comes off the APNG's own timing, same as GIF — a theme
    /// author's animation speed should not silently change with the format.
    func testAPNGFrameTimingIsHonoured() throws {
        let background = BackgroundImage(url: try animatedAPNG(), mode: .tile, capInsets: NSEdgeInsets())
        let animated = try XCTUnwrap(AnimatedImage.load(background))
        XCTAssertEqual(animated.duration, 0.1, accuracy: 0.01)
    }

    /// `imageExtensions` — the actual gate `AssetResolver` checks before
    /// accepting a `window.image` filename — already names apng alongside
    /// gif. Pinned here so removing it later fails a test, not silently.
    func testAPNGIsAnAcceptedImageExtension() {
        XCTAssertTrue(AssetResolver.imageExtensions.contains("apng"))
    }
}
