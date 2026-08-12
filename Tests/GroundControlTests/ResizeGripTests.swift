// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The grip is the only way to resize a shaped panel, so where it lands is
/// load-bearing: a framed skin holds its artwork `contentInset` points clear of
/// the window edge, and a handle sitting out in that margin is a handle on
/// transparent pixels — invisible, and click-through on a shaped theme.
@MainActor
final class ResizeGripTests: XCTestCase {
    private func laidOut(contentInset: CGFloat, width: CGFloat = 420) -> PanelBackgroundView {
        var theme = DefaultTheme.theme
        theme.layout.contentInset = NSEdgeInsets(
            top: contentInset,
            left: contentInset,
            bottom: contentInset,
            right: contentInset
        )

        let view = PanelBackgroundView()
        view.apply(theme: theme)
        view.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// The two marks are a matched pair at either end of the title strip, so
    /// the resize handle is placed off the same constants the close mark uses
    /// rather than by eye.
    func testGripMirrorsTheCloseMarkAcrossTheTitleBar() {
        let inset: CGFloat = 14
        let view = laidOut(contentInset: inset)
        let grip = view.resizeGrip.frame
        let titleBar = view.titleBar.frame

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
            let view = laidOut(contentInset: inset)
            let grip = view.resizeGrip.frame
            XCTAssertLessThanOrEqual(
                grip.maxX,
                view.bounds.width - inset,
                "grip escaped the \(inset)pt frame onto the window edge"
            )
            XCTAssertGreaterThanOrEqual(grip.minX, inset)
            XCTAssertLessThanOrEqual(grip.maxY, view.bounds.height - inset)
            XCTAssertTrue(view.bounds.contains(grip))
        }
    }

    /// A narrow panel with a deep inset must not push the grip off the left
    /// side or invert it.
    func testGripSurvivesAnInsetWiderThanThePanel() {
        let view = laidOut(contentInset: 75, width: 260)
        XCTAssertGreaterThanOrEqual(view.resizeGrip.frame.minX, 0)
        XCTAssertGreaterThan(view.resizeGrip.frame.width, 0)
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
}
