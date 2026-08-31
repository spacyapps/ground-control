// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Themes are written by language models, and two mistakes showed up the first
/// time one produced a skin unaided: it reached for `assets.windowBackground`
/// instead of `window.image`, and it sized the insets in the artwork's pixels
/// rather than the panel's points. Neither should end in a broken panel.
@MainActor
final class ThemeForgivingKeysTests: XCTestCase {
    private var dir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("forgiving-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// `removeBackground` existed only on `window`, so a theme that put its art
    /// under `assets` had no way to get transparency at all — the green stayed
    /// and nothing in the manifest could remove it.
    func testBackgroundAssetsCanBeKeyedToo() throws {
        try Data().write(to: dir.appendingPathComponent("panel.png"))
        try """
        {
          "assets": {
            "windowBackground": { "image": "panel.png", "removeBackground": "#00FF00" }
          }
        }
        """.write(to: dir.appendingPathComponent("theme.json"), atomically: true, encoding: .utf8)

        let theme = ThemeLoader.loadTheme(from: dir)
        XCTAssertEqual(
            theme.backgrounds.window?.removeBackground,
            .color(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        )
    }

    /// An inset read off a 1408px artwork lands around 160, which on a 320pt
    /// panel is the whole width twice over: rows get zero space and the panel
    /// looks empty. The intent is honoured as far as it fits.
    func testAbsurdContentInsetStillLeavesRoomForRows() {
        var theme = DefaultTheme.theme
        theme.layout.contentInset = NSEdgeInsets(top: 160, left: 160, bottom: 160, right: 160)

        let view = PanelBackgroundView()
        view.apply(theme: theme)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 400)
        view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(view.list.frame.width, 60, "rows were squeezed out of existence")
        XCTAssertGreaterThan(view.titleBar.frame.width, 60)
    }

    /// A vertical resize must not move the content sideways. The side insets
    /// are fitted against the width alone, so dragging only the height leaves
    /// them where they were — Skybird's left 114 / right 35 used to slide left
    /// as the panel got shorter, because both pairs were clamped to
    /// `min(width, height)`.
    func testVerticalResizeLeavesTheSideInsetsAlone() {
        var theme = DefaultTheme.theme
        theme.layout.contentInset = NSEdgeInsets(top: 60, left: 114, bottom: 65, right: 35)

        let view = PanelBackgroundView()
        view.apply(theme: theme)

        view.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        view.layoutSubtreeIfNeeded()
        let tall = view.effectiveInsets

        view.frame = NSRect(x: 0, y: 0, width: 760, height: 300)
        view.layoutSubtreeIfNeeded()
        let short = view.effectiveInsets

        XCTAssertEqual(short.left, tall.left, accuracy: 0.5, "the left inset moved on a vertical resize")
        XCTAssertEqual(short.right, tall.right, accuracy: 0.5)
        XCTAssertEqual(tall.left, 114, accuracy: 0.5, "and it is the declared value, unclamped")
    }

    /// A sane inset is still passed through untouched.
    func testReasonableContentInsetIsUnchanged() {
        var theme = DefaultTheme.theme
        theme.layout.contentInset = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

        let view = PanelBackgroundView()
        view.apply(theme: theme)
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 400)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.titleBar.frame.minX, 24, accuracy: 0.5)
    }
}

/// `contentInset` takes one number or four. A frame is rarely as thick at the
/// top as at the sides, so a single value means clearing the thickest side
/// everywhere — and the ✕ and ↔ marks sit at the ends of the title strip, so
/// which sides clear the artwork decides whether they can be seen.
@MainActor
final class ContentInsetSidesTests: XCTestCase {
    private var dir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sides-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func theme(_ json: String) throws -> Theme {
        let manifest = dir.appendingPathComponent("theme.json")
        try json.write(to: manifest, atomically: true, encoding: .utf8)
        return ThemeLoader.loadTheme(from: dir)
    }

    func testOneNumberStillMeansAllFourSides() throws {
        let inset = try theme(##"{ "layout": { "contentInset": 24 } }"##).layout.contentInset
        XCTAssertEqual(inset.top, 24)
        XCTAssertEqual(inset.left, 24)
        XCTAssertEqual(inset.bottom, 24)
        XCTAssertEqual(inset.right, 24)
    }

    func testEachSideCanDifferFromTheOthers() throws {
        let inset = try theme(##"""
        { "layout": { "contentInset": { "top": 140, "left": 152, "bottom": 80, "right": 152 } } }
        """##).layout.contentInset
        XCTAssertEqual(inset.top, 140)
        XCTAssertEqual(inset.left, 152)
        XCTAssertEqual(inset.bottom, 80)
        XCTAssertEqual(inset.right, 152)
    }

    /// A side left unnamed keeps the built-in default rather than collapsing
    /// to zero, which is how every other key in a manifest behaves.
    func testUnnamedSidesFallBackRatherThanZeroing() throws {
        let inset = try theme(##"{ "layout": { "contentInset": { "top": 90 } } }"##).layout.contentInset
        XCTAssertEqual(inset.top, 90)
        XCTAssertEqual(inset.left, DefaultTheme.layout.contentInset.left)
        XCTAssertEqual(inset.bottom, DefaultTheme.layout.contentInset.bottom)
    }

    /// The sides are honoured independently all the way to the layout.
    func testPanelLaysOutEachSideSeparately() {
        var theme = DefaultTheme.theme
        theme.layout.contentInset = NSEdgeInsets(top: 60, left: 20, bottom: 10, right: 40)

        let view = PanelBackgroundView()
        view.apply(theme: theme)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        view.layoutSubtreeIfNeeded()

        // No frame offset or backdrop, so the strip still starts at the inset.
        XCTAssertEqual(view.titleBar.frame.minY, 60, accuracy: 0.5)
        XCTAssertEqual(view.titleBar.frame.minX, 20, accuracy: 0.5)
        XCTAssertEqual(view.titleBar.frame.maxX, 360, accuracy: 0.5)
        XCTAssertEqual(view.list.frame.maxY, 390, accuracy: 0.5)
    }

    /// `titleBackdropTop` raises the strip's top above the title row so a deep
    /// decoration has an opaque ground; `frameOffsetTop` pushes the frame down.
    func testTopStripReachesUpWhenAsked() {
        var theme = DefaultTheme.theme
        theme.layout.contentInset = NSEdgeInsets(top: 120, left: 20, bottom: 10, right: 40)
        theme.layout.titleBackdropTop = 80
        theme.window = Theme.Window(
            shape: BackgroundImage(url: URL(fileURLWithPath: "/x.gif"), mode: .tile, capInsets: NSEdgeInsets()),
            locksAspect: false,
            aspectRatio: 1
        )
        theme.layout.frameOffsetTop = 30

        let view = PanelBackgroundView()
        view.apply(theme: theme)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.frameTopOffset, 30, accuracy: 0.5, "the frame drops")
        XCTAssertEqual(view.titleStripTop, 40, accuracy: 0.5, "strip top = inset.top − backdrop")
        XCTAssertEqual(view.titleBar.frame.minY, 40, accuracy: 0.5)
        XCTAssertEqual(view.titleRowTop, 120, accuracy: 0.5, "the content still sits at the inset")
    }
}
