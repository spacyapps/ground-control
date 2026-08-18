// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The measurement that decides whether a nine-grid theme works.
final class CapMeasureTests: XCTestCase {
    /// The unicorn frame is the case the old script got wrong: its deepest
    /// ornament sits top-right, and a left-half scan reported 69 where the
    /// true answer is 100.
    func testItFindsOrnamentOnTheFarSideToo() throws {
        let url = URL(fileURLWithPath: "ExtraThemes/spacyAppsUnicornOverlord/frame.gif")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "ExtraThemes is licensed separately and not in the repository")
        let caps = try XCTUnwrap(CapMeasure.measure(contentsOf: url))
        XCTAssertGreaterThanOrEqual(caps.right, 90, "the unicorn and its chain sit on the right")
        XCTAssertLessThanOrEqual(caps.right, 110)
        XCTAssertGreaterThan(caps.right, caps.left, "this artwork is deliberately asymmetric")
    }

    /// The shipped theme, whose caps are known good, must not measure larger
    /// than the caps it actually ships with.
    func testTheShippedFrameAgreesWithItsManifest() throws {
        let theme = ThemeLoader.loadTheme(from: URL(fileURLWithPath: "Themes/spacyAppsLunarAvatar"))
        let shipped = try XCTUnwrap(theme.window.shape?.capInsets)
        let url = URL(fileURLWithPath: "Themes/spacyAppsLunarAvatar/frame.gif")
        let caps = try XCTUnwrap(CapMeasure.measure(contentsOf: url))
        XCTAssertLessThanOrEqual(caps.left, Int(shipped.left), "shipped caps should clear the ornament")
        XCTAssertLessThanOrEqual(caps.right, Int(shipped.right))
    }
}
