// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import GroundControl

/// Animation frames parked on disk. Every test points the store at its own temp
/// folder: the real one is `~/Library/Caches/GroundControl`, and a test that
/// sweeps or fills that is a test that damages a running app's frames.
final class FrameStoreTests: XCTestCase {
    private var root = FileManager.default.temporaryDirectory
    private let realRoot = FrameStore.root

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameStoreTests-\(UUID().uuidString)")
        FrameStore.root = root
        AnimatedImage.clearCache()
    }

    override func tearDownWithError() throws {
        AnimatedImage.clearCache()
        FrameStore.root = realRoot
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixtures

    private func solid(red: UInt8, green: UInt8 = 0, blue: UInt8, side: Int = 16) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            pixels[pixel] = red; pixels[pixel + 1] = green; pixels[pixel + 2] = blue; pixels[pixel + 3] = 255
        }
        return try bitmap(&pixels, side: side)
    }

    /// Per-byte noise LZ4 cannot shrink, so the store has to write it raw.
    private func noise(side: Int = 16) throws -> CGImage {
        var generator = SystemRandomNumberGenerator()
        var pixels = (0..<side * side * 4).map { _ in UInt8.random(in: 0...255, using: &generator) }
        // Premultiplied: colour may not exceed alpha, so pin alpha opaque.
        for pixel in stride(from: 3, to: pixels.count, by: 4) { pixels[pixel] = 255 }
        return try bitmap(&pixels, side: side)
    }

    private func bitmap(_ pixels: inout [UInt8], side: Int) throws -> CGImage {
        let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return try XCTUnwrap(context?.makeImage())
    }

    /// RGBA of the pixel at (0, 0), read back through a bitmap context.
    private func firstPixel(_ image: CGImage) throws -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixel
    }

    private func animatedAPNG(frames: [CGImage]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fs-\(UUID().uuidString).apng")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, frames.count, nil
        ))
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
        ] as CFDictionary)
        for image in frames {
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGDelayTime: 0.1,
                    kCGImagePropertyAPNGUnclampedDelayTime: 0.1
                ]
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func folders() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    }

    // MARK: - Store

    func testFramesComeBackWithTheirPixels() throws {
        let red = try solid(red: 255, blue: 0)
        let blue = try solid(red: 0, blue: 255)
        let store = try XCTUnwrap(FrameStore.build(name: "t", frameCount: 2, frame: { [red, blue][$0] }))

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(try firstPixel(XCTUnwrap(store.image(at: 0))), [255, 0, 0, 255])
        XCTAssertEqual(try firstPixel(XCTUnwrap(store.image(at: 1))), [0, 0, 255, 255])
    }

    func testIncompressibleFrameIsStoredAsItCame() throws {
        let noisy = try noise()
        let store = try XCTUnwrap(FrameStore.build(name: "noise", frameCount: 1, frame: { _ in noisy }))

        let back = try XCTUnwrap(store.image(at: 0))
        XCTAssertEqual(try firstPixel(back), try firstPixel(noisy))
        let file = root.appendingPathComponent(try XCTUnwrap(folders().first)).appendingPathComponent("0.lz4")
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        XCTAssertEqual(size, 16 * 16 * 4, "noise should have been written raw, not 'compressed'")
    }

    func testSkippedFramesLeaveConsecutiveIndices() throws {
        let red = try solid(red: 255, blue: 0)
        let blue = try solid(red: 0, blue: 255)
        let store = try XCTUnwrap(FrameStore.build(name: "skip", frameCount: 3, frame: { [red, nil, blue][$0] }))

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(try firstPixel(XCTUnwrap(store.image(at: 1))), [0, 0, 255, 255])
    }

    func testMismatchedFrameSizeRefusesAndLeavesNothingBehind() throws {
        let small = try solid(red: 1, blue: 1, side: 8)
        let large = try solid(red: 1, blue: 1, side: 16)
        let store = FrameStore.build(name: "bad", frameCount: 2, frame: { [small, large][$0] })

        XCTAssertNil(store)
        XCTAssertTrue(folders().isEmpty, "a refused build must not leave its half-written folder")
    }

    func testOutOfRangeAndMissingFilesAreNilNotACrash() throws {
        let red = try solid(red: 255, blue: 0)
        let store = try XCTUnwrap(FrameStore.build(name: "gone", frameCount: 1, frame: { _ in red }))

        XCTAssertNil(store.image(at: -1))
        XCTAssertNil(store.image(at: 1))
        FrameStore.removeAll()
        XCTAssertNil(store.image(at: 0), "a reload sweeping the folder must not take a late caller down")
    }

    func testStoreDeletesItsFolderWhenItGoes() throws {
        let red = try solid(red: 255, blue: 0)
        var store = FrameStore.build(name: "owned", frameCount: 1, frame: { _ in red })
        XCTAssertEqual(folders().count, 1)

        store = nil
        XCTAssertTrue(folders().isEmpty)
    }

    func testFirstBuildSweepsWhatAPreviousRunLeft() throws {
        let stale = root.appendingPathComponent("crashed-run")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data([1]).write(to: stale.appendingPathComponent("0.lz4"))
        let red = try solid(red: 255, blue: 0)

        let store = FrameStore.build(name: "fresh", frameCount: 1, frame: { _ in red })

        XCTAssertNotNil(store)
        XCTAssertFalse(folders().contains("crashed-run"))
        XCTAssertEqual(folders().count, 1)
    }

    // MARK: - AnimatedImage on top of it

    func testAnimatedImageServesFramesFromDiskWithTheirInsets() throws {
        let url = try animatedAPNG(frames: [try solid(red: 255, blue: 0), try solid(red: 0, blue: 255)])
        let insets = NSEdgeInsets(top: 3, left: 4, bottom: 5, right: 6)
        let background = BackgroundImage(url: url, mode: .tile, capInsets: insets)

        let animated = try XCTUnwrap(AnimatedImage.load(background))

        XCTAssertEqual(animated.count, 2)
        XCTAssertEqual(folders().count, 1, "an animation should be parked on disk")
        let second = try XCTUnwrap(animated.frame(at: 0.15))
        XCTAssertEqual(second.capInsets.left, 4)
        XCTAssertEqual(second.resizingMode, .tile)
        var rect = NSRect(origin: .zero, size: second.size)
        let cg = try XCTUnwrap(second.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        XCTAssertEqual(try firstPixel(cg), [0, 0, 255, 255], "0.15s in is the second frame")
    }

    func testClearingTheCacheClearsTheFrames() throws {
        let url = try animatedAPNG(frames: [try solid(red: 255, blue: 0), try solid(red: 0, blue: 255)])
        let background = BackgroundImage(url: url, mode: .tile, capInsets: NSEdgeInsets())
        XCTAssertNotNil(AnimatedImage.load(background))
        XCTAssertEqual(folders().count, 1)

        BackgroundRenderer.clearCache()

        XCTAssertTrue(folders().isEmpty, "a theme change must not leave the old theme's frames on disk")
    }

    func testAStillStaysInMemory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("still-\(UUID().uuidString).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, try solid(red: 9, blue: 9), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let background = BackgroundImage(url: url, mode: .center, capInsets: NSEdgeInsets())
        let animated = try XCTUnwrap(AnimatedImage.load(background))

        XCTAssertFalse(animated.isAnimated)
        XCTAssertNotNil(animated.first)
        XCTAssertTrue(folders().isEmpty)
    }
}
