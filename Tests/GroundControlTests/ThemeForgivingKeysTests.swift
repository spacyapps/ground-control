// SPDX-License-Identifier: GPL-3.0-or-later
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
        theme.layout.contentInset = 160

        let view = PanelBackgroundView()
        view.apply(theme: theme)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 400)
        view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(view.list.frame.width, 60, "rows were squeezed out of existence")
        XCTAssertGreaterThan(view.titleBar.frame.width, 60)
    }

    /// A sane inset is still passed through untouched.
    func testReasonableContentInsetIsUnchanged() {
        var theme = DefaultTheme.theme
        theme.layout.contentInset = 24

        let view = PanelBackgroundView()
        view.apply(theme: theme)
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 400)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.titleBar.frame.minX, 24, accuracy: 0.5)
    }
}
