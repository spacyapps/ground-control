// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The grip is the only way to resize a shaped panel, so where it lands is
/// load-bearing: a framed skin holds its artwork `contentInset` points clear of
/// the window edge, and a handle sitting out in that margin is a handle on
/// transparent pixels — invisible, and click-through on a shaped theme.
@MainActor
final class ResizeGripTests: XCTestCase {
    /// `PanelRootView`, not `PanelBackgroundView` — the grip lives one level up
    /// now, outside chrome's shape mask (see `PanelRootView`'s doc comment).
    /// Laying out through the real root exercises the whole handoff: chrome
    /// computes `resizeGripFrame` off its own title bar, root reads it back.
    private func laidOut(contentInset: CGFloat, width: CGFloat = 420) -> PanelRootView {
        var theme = DefaultTheme.theme
        theme.layout.contentInset = NSEdgeInsets(
            top: contentInset,
            left: contentInset,
            bottom: contentInset,
            right: contentInset
        )

        let root = PanelRootView()
        root.apply(theme: theme)
        root.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        root.layoutSubtreeIfNeeded()
        return root
    }

    /// The two marks are a matched pair at either end of the title strip, so
    /// the resize handle is placed off the same constants the close mark uses
    /// rather than by eye.
    func testGripMirrorsTheCloseMarkAcrossTheTitleBar() {
        let inset: CGFloat = 14
        let root = laidOut(contentInset: inset)
        let grip = root.resizeGrip.frame
        let titleBar = root.chrome.titleBar.frame

        XCTAssertEqual(grip.width, grip.height, "corner marks are square")
        XCTAssertEqual(grip.minY, titleBar.minY + TitleBarView.markTop, accuracy: 0.5)
        XCTAssertEqual(
            titleBar.maxX - grip.maxX,
            TitleBarView.markInset,
            accuracy: 0.5,
            "grip should sit as far from its end as the close mark does from its own"
        )
    }

    func testGripStaysInsideTheFramedArtwork() {
        for inset in [0.0, 14.0, 75.0] {
            let root = laidOut(contentInset: inset)
            let grip = root.resizeGrip.frame
            XCTAssertLessThanOrEqual(
                grip.maxX,
                root.bounds.width - inset,
                "grip escaped the \(inset)pt frame onto the window edge"
            )
            XCTAssertGreaterThanOrEqual(grip.minX, inset)
            XCTAssertLessThanOrEqual(grip.maxY, root.bounds.height - inset)
            XCTAssertTrue(root.bounds.contains(grip))
        }
    }

    /// A narrow panel with a deep inset must not push the grip off the left
    /// side or invert it.
    func testGripSurvivesAnInsetWiderThanThePanel() {
        let root = laidOut(contentInset: 75, width: 260)
        XCTAssertGreaterThanOrEqual(root.resizeGrip.frame.minX, 0)
        XCTAssertGreaterThan(root.resizeGrip.frame.width, 0)
    }

    /// The grip drew itself in palette colours once, which on a dark skin put a
    /// near-black capsule on a near-black hull: present, hit-testable, working,
    /// and completely invisible. Placement tests all passed while it could not
    /// be seen, so visibility needs its own check — render it and look.
    func testGripContrastsWithTheBackgroundItSitsOn() throws {
        for background in [NSColor(srgbRed: 0.04, green: 0.04, blue: 0.07, alpha: 1),
                           NSColor(srgbRed: 0.96, green: 0.96, blue: 0.94, alpha: 1)] {
            var theme = DefaultTheme.theme
            theme.colors.windowBackground = background

            let grip = ResizeGripView()
            grip.apply(theme: theme)
            grip.frame = NSRect(origin: .zero, size: ResizeGripView.size)

            let rep = try XCTUnwrap(grip.bitmapImageRepForCachingDisplay(in: grip.bounds))
            grip.cacheDisplay(in: grip.bounds, to: rep)

            var best = 0.0
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                          pixel.alphaComponent > 0.5 else { continue }
                    best = max(best, abs(luminance(of: pixel) - luminance(of: background)))
                }
            }
            XCTAssertGreaterThan(best, 0.3, "grip is invisible on \(background)")
        }
    }

    private func luminance(of color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        return 0.2126 * rgb.redComponent
            + 0.7152 * rgb.greenComponent
            + 0.0722 * rgb.blueComponent
    }

    /// Dragging the grip must not be stolen by drag-to-move-the-window.
    func testGripDoesNotMoveTheWindow() {
        XCTAssertFalse(ResizeGripView().mouseDownCanMoveWindow)
    }

    // MARK: - Surviving an irregular silhouette

    /// A circle inscribed in a square canvas, green-keyed outside it — the
    /// literal bounding-box corners are transparent by construction, which is
    /// exactly the shape a tapered silhouette (a station hull, a rounded hull
    /// with no square corners) produces in practice.
    private func circularArtwork() throws -> URL {
        let side = 200
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let radius = 70.0
        let center = Double(side) / 2
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let inside = (Double(x) - center) * (Double(x) - center)
                    + (Double(y) - center) * (Double(y) - center) < radius * radius
                pixels[index] = inside ? 255 : 0
                pixels[index + 1] = inside ? 255 : 255
                pixels[index + 2] = inside ? 255 : 0
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
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "circular-hull.png")
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: url)
        return url
    }

    /// The case `PanelRootView` exists to fix: with zero `contentInset`, the
    /// title strip — and both marks — sit right at the literal top corners of
    /// the 200x200 canvas above, a good 100+pt from the inscribed circle's
    /// edge. Under the old nesting, `chrome`'s own shape mask would have
    /// swallowed a click there; promoted out to `PanelRootView`, it must not.
    func testMarksSurviveASilhouetteThatDoesNotReachTheCorner() throws {
        var theme = DefaultTheme.theme
        theme.window = Theme.Window(
            shape: BackgroundImage(
                url: try circularArtwork(),
                mode: .stretch,
                capInsets: NSEdgeInsets(),
                removeBackground: .color(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
            ),
            locksAspect: false,
            aspectRatio: 1
        )
        theme.layout.contentInset = NSEdgeInsets()

        let root = PanelRootView()
        root.apply(theme: theme)
        root.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        root.layoutSubtreeIfNeeded()

        // A real, if offscreen, window: `hitTest` on a content view expects
        // window-base coordinates, not the view's own bounds space — `root`
        // has no real superview, so that's the only coordinate system it can
        // mean. Real mouse events already arrive this way via
        // `event.locationInWindow`; a bare view with no window would not.
        let testWindow = NSWindow(
            contentRect: root.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        testWindow.contentView = root

        let closeCenter = NSPoint(x: root.closeMark.frame.midX, y: root.closeMark.frame.midY)
        let gripCenter = NSPoint(x: root.resizeGrip.frame.midX, y: root.resizeGrip.frame.midY)

        // Prove the mask really is what it claims: chrome on its own says
        // nothing is here. Chrome is not the content view, so its own bounds
        // space (root's, since that is chrome's real superview) is correct
        // as-is — no window-base conversion needed for this call.
        XCTAssertNil(root.chrome.hitTest(closeCenter), "test setup: point should be outside the hull")
        XCTAssertNil(root.chrome.hitTest(gripCenter), "test setup: point should be outside the hull")

        // The actual fix: promoted out of chrome, the marks are hit-testable
        // regardless of what chrome's own silhouette says underneath them.
        let closeBase = root.convert(closeCenter, to: nil)
        let gripBase = root.convert(gripCenter, to: nil)
        XCTAssertTrue(root.hitTest(closeBase) === root.closeMark)
        XCTAssertTrue(root.hitTest(gripBase) === root.resizeGrip)
    }
}
