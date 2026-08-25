// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// Parsing the `cornerDecorations` manifest block into `Theme.CornerDecorations`.
final class CornerDecorationAssetTests: XCTestCase {
    private var folder = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CornerDecorationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func touch(_ name: String) throws {
        try Data("x".utf8).write(to: folder.appendingPathComponent(name))
    }

    private func resolve(_ json: String) throws -> Theme.CornerDecorations {
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: Data(json.utf8))
        return AssetResolver.cornerDecorations(from: manifest.cornerDecorations, folder: folder)
    }

    func testImageParsesWithOffsetAndKeying() throws {
        try touch("chest.gif")
        let decorations = try resolve("""
        {"cornerDecorations":{"bottomRight":{"image":"chest.gif","removeBackground":"#FF00FF",
        "offset":{"x":-12,"y":8}}}}
        """)
        let decoration = try XCTUnwrap(decorations.bottomRight)
        guard case .image(let background) = decoration.asset else {
            return XCTFail("expected an image asset")
        }
        XCTAssertEqual(background.removeBackground, .color(NSColor(hex: "#FF00FF")!))
        XCTAssertEqual(decoration.offset, CGSize(width: -12, height: 8))
    }

    func testOffsetDefaultsToZeroWhenOmitted() throws {
        try touch("palm.png")
        let decorations = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"palm.png"}}}"#)
        XCTAssertEqual(decorations.topLeft?.offset, .zero)
    }

    func testScaleParses() throws {
        try touch("ship.apng")
        let decorations = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"ship.apng","scale":0.5}}}"#)
        XCTAssertEqual(decorations.topLeft?.scale, 0.5)
    }

    func testScaleDefaultsToOneWhenOmitted() throws {
        try touch("palm.png")
        let decorations = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"palm.png"}}}"#)
        XCTAssertEqual(decorations.topLeft?.scale, 1)
    }

    /// 0 or negative would hide or invert the art — neither is a meaningful
    /// "scale", so both fall back to the real size rather than do that.
    func testScaleFallsBackToOneWhenZeroOrNegative() throws {
        try touch("a.png")
        try touch("b.png")
        let zero = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"a.png","scale":0}}}"#)
        let negative = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"b.png","scale":-2}}}"#)
        XCTAssertEqual(zero.topLeft?.scale, 1)
        XCTAssertEqual(negative.topLeft?.scale, 1)
    }

    func testVideoWinsOverImageWhenBothAreSet() throws {
        try touch("clip.mp4")
        try touch("fallback.png")
        let decorations = try resolve("""
        {"cornerDecorations":{"topRight":{"image":"fallback.png","video":"clip.mp4",
        "loop":false,"muted":false}}}
        """)
        guard case .video(let url, let loop, let muted) = decorations.topRight?.asset else {
            return XCTFail("expected a video asset")
        }
        XCTAssertEqual(url.lastPathComponent, "clip.mp4")
        XCTAssertFalse(loop)
        XCTAssertFalse(muted)
    }

    func testVideoLoopAndMutedDefaultToTrue() throws {
        try touch("clip.mov")
        let decorations = try resolve(#"{"cornerDecorations":{"topRight":{"video":"clip.mov"}}}"#)
        guard case .video(_, let loop, let muted) = decorations.topRight?.asset else {
            return XCTFail("expected a video asset")
        }
        XCTAssertTrue(loop)
        XCTAssertTrue(muted)
    }

    func testUnsupportedVideoExtensionResolvesToNothing() throws {
        try touch("clip.webm")
        let decorations = try resolve(#"{"cornerDecorations":{"topRight":{"video":"clip.webm"}}}"#)
        XCTAssertNil(decorations.topRight)
    }

    /// One corner's typo must not poison the other three.
    func testMissingFileResolvesToNothingRatherThanFailingTheOthers() throws {
        try touch("real.png")
        let decorations = try resolve("""
        {"cornerDecorations":{"topLeft":{"image":"typo.png"},"bottomLeft":{"image":"real.png"}}}
        """)
        XCTAssertNil(decorations.topLeft)
        XCTAssertNotNil(decorations.bottomLeft)
    }

    func testAllFourCornersAreIndependentlyAddressable() throws {
        for name in ["a.png", "b.png", "c.png", "d.png"] { try touch(name) }
        let decorations = try resolve("""
        {"cornerDecorations":{
            "topLeft":{"image":"a.png"},"topRight":{"image":"b.png"},
            "bottomLeft":{"image":"c.png"},"bottomRight":{"image":"d.png"}
        }}
        """)
        XCTAssertNotNil(decorations.topLeft)
        XCTAssertNotNil(decorations.topRight)
        XCTAssertNotNil(decorations.bottomLeft)
        XCTAssertNotNil(decorations.bottomRight)
        XCTAssertFalse(decorations.isEmpty)
    }

    func testNoBlockMeansNoDecorations() throws {
        let decorations = try resolve("{}")
        XCTAssertEqual(decorations, .none)
        XCTAssertTrue(decorations.isEmpty)
    }
}

/// Where each corner's artwork actually lands, drawn through the real view.
@MainActor
final class CornerDecorationGeometryTests: XCTestCase {
    /// A small solid-colour square, opaque, no keying needed — geometry tests
    /// only care where it lands, not what it looks like.
    private func swatch(side: Int = 20, red: UInt8, green: UInt8, blue: UInt8) throws -> URL {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            pixels[pixel] = red; pixels[pixel + 1] = green; pixels[pixel + 2] = blue; pixels[pixel + 3] = 255
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
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "swatch-\(UUID().uuidString).png")
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: url)
        return url
    }

    private func decoration(url: URL, offset: CGSize = .zero, scale: CGFloat = 1) -> Theme.CornerDecoration {
        Theme.CornerDecoration(
            asset: .image(BackgroundImage(url: url, mode: .center, capInsets: NSEdgeInsets())),
            offset: offset,
            scale: scale
        )
    }

    private func rendered(_ decorations: Theme.CornerDecorations, size: NSSize = NSSize(width: 200, height: 200))
        throws -> NSBitmapImageRep {
        var theme = DefaultTheme.theme
        theme.cornerDecorations = decorations
        let view = CornerDecorationsView()
        view.apply(theme: theme)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func isSwatch(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int, red: UInt8) throws -> Bool {
        let colour = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        return colour.redComponent > CGFloat(red) / 255 - 0.1 && colour.alphaComponent > 0.5
    }

    /// {0,0} means the artwork's own matching corner sits exactly on the
    /// window's — bottomRight's bottom-right pixel on the window's.
    func testZeroOffsetPutsTheMatchingCornersTogether() throws {
        let url = try swatch(red: 255, green: 0, blue: 0)
        let rep = try rendered(Theme.CornerDecorations(bottomRight: decoration(url: url)))
        let scale = rep.pixelsWide / 200

        // A point 5pt in from the true bottom-right corner: inside the 20pt
        // swatch either way you draw the y axis, so this does not depend on
        // getting the flip direction right by luck.
        XCTAssertTrue(try isSwatch(rep, 195 * scale, 195 * scale, red: 255))
        // Far from that corner: must not have smeared or tiled elsewhere.
        XCTAssertFalse(try isSwatch(rep, 5 * scale, 5 * scale, red: 255))
        XCTAssertFalse(try isSwatch(rep, 100 * scale, 100 * scale, red: 255))
    }

    /// Screen direction: x moves it right, y moves it down, regardless of
    /// which corner it is anchored to.
    func testOffsetMovesInScreenDirection() throws {
        let url = try swatch(red: 0, green: 255, blue: 0)
        let pushedIn = try rendered(Theme.CornerDecorations(
            topLeft: decoration(url: url, offset: CGSize(width: 40, height: 40))
        ))
        let scale = pushedIn.pixelsWide / 200

        // Not at the literal corner any more...
        XCTAssertFalse(try isSwatch(pushedIn, 2 * scale, 2 * scale, red: 0))
        // ...but at (40,40)-ish, pushed right and down from it.
        XCTAssertTrue(try isSwatch(pushedIn, 45 * scale, 45 * scale, red: 0))
    }

    /// Scale shrinks (or grows) the drawn footprint itself, not just how it's
    /// positioned — and the corner anchor is computed against the *scaled*
    /// size, so shrinking brings the art in from the corner rather than
    /// leaving a gap where the unscaled footprint used to be.
    func testScaleChangesTheDrawnFootprint() throws {
        let url = try swatch(side: 20, red: 255, green: 0, blue: 0)
        let full = try rendered(Theme.CornerDecorations(bottomRight: decoration(url: url)))
        let half = try rendered(Theme.CornerDecorations(bottomRight: decoration(url: url, scale: 0.5)))
        let fullScale = full.pixelsWide / 200
        let halfScale = half.pixelsWide / 200

        // At full scale (20pt swatch), a point 15pt in from the corner is
        // still inside it.
        XCTAssertTrue(try isSwatch(full, 185 * fullScale, 185 * fullScale, red: 255))
        // At half scale (10pt swatch), that same point is now past the
        // shrunk footprint entirely — proving the anchor moved with the size
        // rather than just clipping the same-sized draw.
        XCTAssertFalse(try isSwatch(half, 185 * halfScale, 185 * halfScale, red: 255))
        // But right at the true corner, the shrunk swatch is still there.
        XCTAssertTrue(try isSwatch(half, 195 * halfScale, 195 * halfScale, red: 255))
    }

    /// All four corners at once, independent of one another.
    func testAllFourCornersDrawIndependently() throws {
        let red = try swatch(red: 255, green: 0, blue: 0)
        let green = try swatch(red: 0, green: 255, blue: 0)
        let decorations = Theme.CornerDecorations(
            topLeft: decoration(url: red),
            bottomRight: decoration(url: green)
        )
        let rep = try rendered(decorations)
        let scale = rep.pixelsWide / 200

        XCTAssertTrue(try isSwatch(rep, 5 * scale, 5 * scale, red: 255), "topLeft should be red")
        XCTAssertTrue(try isSwatch(rep, 195 * scale, 195 * scale, red: 0), "bottomRight should not read as red")
        let bottomRight = try XCTUnwrap(rep.colorAt(x: 195 * scale, y: 195 * scale)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(bottomRight.greenComponent, 0.5, "bottomRight should be green")
    }

    /// A two-frame animated gif: red, then blue, a fast 0.03s apart — fast
    /// enough that a real, short wait reliably crosses a frame boundary.
    private func animatedSwatch(side: Int = 20) throws -> URL {
        func frame(red: UInt8, blue: UInt8) throws -> CGImage {
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            for pixel in stride(from: 0, to: pixels.count, by: 4) {
                pixels[pixel] = red; pixels[pixel + 2] = blue; pixels[pixel + 3] = 255
            }
            let context = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            return try XCTUnwrap(context?.makeImage())
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "animated-\(UUID().uuidString).gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, "com.compuserve.gif" as CFString, 2, nil
        ))
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        for image in [try frame(red: 255, blue: 0), try frame(red: 0, blue: 255)] {
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: 0.03,
                    kCGImagePropertyGIFUnclampedDelayTime: 0.03
                ]
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// Attached to a real (offscreen) window: `updateAnimation` only starts
    /// its timer once `window != nil`, matching every other animated surface
    /// in the panel — a bare, unattached view would never actually animate.
    private func hosted(_ view: NSView, size: NSSize) {
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = view
    }

    private func redComponent(_ view: CornerDecorationsView) throws -> CGFloat {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = rep.pixelsWide / Int(view.bounds.width)
        let colour = try XCTUnwrap(rep.colorAt(x: 195 * scale, y: 195 * scale)?.usingColorSpace(.sRGB))
        return colour.redComponent
    }

    /// Motion means work: idle, a corner gif must sit dead still on its first
    /// frame no matter how long you wait.
    func testStaysOnFirstFrameWhileIdle() throws {
        let view = CornerDecorationsView()
        hosted(view, size: NSSize(width: 200, height: 200))
        var theme = DefaultTheme.theme
        theme.cornerDecorations = Theme.CornerDecorations(bottomRight: decoration(url: try animatedSwatch()))
        view.apply(theme: theme)
        view.layoutSubtreeIfNeeded()

        let before = try redComponent(view)
        XCTAssertGreaterThan(before, 0.5, "should start on the red first frame")

        let settled = expectation(description: "a moment passes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        XCTAssertEqual(try redComponent(view), before, "an idle corner must not have moved on")
    }

    /// Working, the same gif must actually advance past its first frame at
    /// some point — sampled repeatedly rather than at one predicted instant,
    /// since the exact frame at an exact millisecond is timing-sensitive in a
    /// way "did it ever move at all" is not.
    func testAdvancesPastFirstFrameWhileWorking() throws {
        let view = CornerDecorationsView()
        hosted(view, size: NSSize(width: 200, height: 200))
        var theme = DefaultTheme.theme
        theme.cornerDecorations = Theme.CornerDecorations(bottomRight: decoration(url: try animatedSwatch()))
        view.apply(theme: theme)
        view.layoutSubtreeIfNeeded()
        view.update(isWorking: true)

        var sawBlue = false
        for _ in 0..<10 {
            let settled = expectation(description: "one tick")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { settled.fulfill() }
            wait(for: [settled], timeout: 2)
            if try redComponent(view) < 0.5 { sawBlue = true; break }
        }
        XCTAssertTrue(sawBlue, "working, the gif should have moved past its first frame at some point")
    }

    /// Never a click target, at any point, decorated or not.
    func testNeverTakesAClick() throws {
        let url = try swatch(red: 255, green: 255, blue: 255)
        let view = CornerDecorationsView()
        var theme = DefaultTheme.theme
        theme.cornerDecorations = Theme.CornerDecorations(bottomRight: decoration(url: url))
        view.apply(theme: theme)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        view.layoutSubtreeIfNeeded()

        XCTAssertNil(view.hitTest(NSPoint(x: 195, y: 195)))
        XCTAssertNil(view.hitTest(NSPoint(x: 100, y: 100)))
    }

    /// Above the frame, below the two controls — the same "marks, then
    /// frame, then panel" order `PanelRootView` already guarantees for
    /// close/resize; corner decorations join it in the middle.
    func testSitsAboveChromeAndBelowTheControls() {
        let root = PanelRootView()
        root.apply(theme: DefaultTheme.theme)
        root.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        root.layoutSubtreeIfNeeded()

        func depth(_ subview: NSView) -> Int {
            root.subviews.firstIndex(of: subview) ?? -1
        }
        XCTAssertGreaterThan(depth(root.cornerDecorations), depth(root.chrome))
        XCTAssertGreaterThan(depth(root.closeMark), depth(root.cornerDecorations))
        XCTAssertGreaterThan(depth(root.resizeGrip), depth(root.cornerDecorations))
    }
}
