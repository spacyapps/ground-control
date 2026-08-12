// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// `window.overlay` draws the skin over the rows instead of behind them, so a
/// frame covers whatever it overlaps and the rows need no pixel-accurate fit to
/// its opening.
@MainActor
final class OverlaySkinTests: XCTestCase {
    private var dir = FileManager.default.temporaryDirectory
    private let border = 20

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A magenta frame with a green — that is, keyed to transparent — middle.
    private func makeFrame() throws -> URL {
        let side = 100
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let onFrame = x < border || y < border || x >= side - border || y >= side - border
                pixels[index] = onFrame ? 255 : 0
                pixels[index + 1] = onFrame ? 0 : 255
                pixels[index + 2] = onFrame ? 255 : 0
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
        let url = dir.appendingPathComponent("frame.png")
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

    private func theme(overlay: Bool) throws -> Theme {
        var theme = DefaultTheme.theme
        theme.window = Theme.Window(
            shape: BackgroundImage(
                url: try makeFrame(),
                mode: .stretch,
                capInsets: NSEdgeInsets(),
                removeBackground: .color(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
            ),
            locksAspect: true,
            aspectRatio: 1,
            drawsOverContent: overlay,
            naturalWidth: 100
        )
        theme.layout.contentInset = 0        // rows run right to the edge on purpose
        return theme
    }

    private func rendered(overlay: Bool) throws -> NSBitmapImageRep {
        let view = PanelBackgroundView()
        view.apply(theme: try theme(overlay: overlay))
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        view.update(sessions: [], renames: [:])
        view.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func isMagenta(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        return colour.redComponent > 0.7 && colour.greenComponent < 0.3
            && colour.blueComponent > 0.7 && colour.alphaComponent > 0.5
    }

    /// The point of the mode: rows run to the panel edge with `contentInset: 0`,
    /// and the frame still shows, because it is painted afterwards.
    func testOverlayFrameCoversTheRowsBeneathIt() throws {
        let rep = try rendered(overlay: true)
        let scale = rep.pixelsWide / 200
        XCTAssertTrue(isMagenta(rep, 10 * scale, 100 * scale), "the frame is not on top")
        XCTAssertFalse(isMagenta(rep, 100 * scale, 100 * scale), "the frame's middle is not transparent")
    }

    /// Behind the rows, the same artwork and the same zero inset put the frame
    /// under the title strip, where it cannot be seen — the situation the mode
    /// exists to avoid.
    func testBehindTheRowsTheSameFrameIsHidden() throws {
        let rep = try rendered(overlay: false)
        let scale = rep.pixelsWide / 200
        XCTAssertFalse(isMagenta(rep, 10 * scale, 30 * scale), "the strip should be covering it")
    }

    /// A frame is decoration. It must never intercept a click meant for a row.
    func testOverlayNeverTakesAClick() throws {
        let view = PanelBackgroundView()
        view.apply(theme: try theme(overlay: true))
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        view.layoutSubtreeIfNeeded()

        XCTAssertNil(view.skinOverlay.hitTest(NSPoint(x: 10, y: 100)))
        XCTAssertNil(view.skinOverlay.hitTest(NSPoint(x: 100, y: 100)))
        XCTAssertIdentical(view.subviews.last, view.skinOverlay, "the overlay must be topmost")
    }

    func testOrdinaryThemesAreUnaffected() throws {
        let view = PanelBackgroundView()
        view.apply(theme: try theme(overlay: false))
        XCTAssertTrue(view.skinOverlay.isHidden)

        view.apply(theme: try theme(overlay: true))
        XCTAssertFalse(view.skinOverlay.isHidden)
    }
}
