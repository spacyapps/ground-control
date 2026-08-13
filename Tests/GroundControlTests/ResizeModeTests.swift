// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// A skin and a container want opposite things from a resize, and a person
/// wants a third: the window at the size they chose. `layout.resize` is that
/// choice, and `window.lockAspect` was the older spelling that could only say
/// two of the three.
@MainActor
final class ResizeModeTests: XCTestCase {
    private var dir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("resize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func mode(_ json: String) throws -> Theme.Resize {
        let manifest = dir.appendingPathComponent("theme.json")
        try json.write(to: manifest, atomically: true, encoding: .utf8)
        return ThemeLoader.loadTheme(from: dir).layout.resize
    }

    func testEachModeIsNamed() throws {
        XCTAssertEqual(try mode(##"{ "layout": { "resize": "free" } }"##), .free)
        XCTAssertEqual(try mode(##"{ "layout": { "resize": "aspect" } }"##), .aspect)
        XCTAssertEqual(try mode(##"{ "layout": { "resize": "content" } }"##), .content)
    }

    /// Themes written before this key still mean what they meant.
    func testLockAspectStillSpeaks() throws {
        XCTAssertEqual(try mode(##"{ "window": { "lockAspect": true } }"##), .aspect)
        XCTAssertEqual(try mode(##"{ "window": { "lockAspect": false } }"##), .content)
    }

    /// The newer key wins where a theme carries both, so a manifest can be
    /// updated without first deleting the old line.
    func testTheExplicitModeOutranksTheOlderKey() throws {
        let json = ##"""
        { "window": { "lockAspect": true }, "layout": { "resize": "free" } }
        """##
        XCTAssertEqual(try mode(json), .free)
    }

    /// A panel with no artwork is a list, and a list grows with what is in it.
    func testTheDefaultFollowsTheRows() throws {
        XCTAssertEqual(try mode("{}"), .content)
    }

    /// A value nobody implemented falls back rather than failing the theme.
    func testAnUnknownModeFallsBack() throws {
        XCTAssertEqual(try mode(##"{ "layout": { "resize": "elastic" } }"##), .content)
        XCTAssertEqual(try mode(##"{ "layout": { "resize": 7 } }"##), .content)
    }

    /// The two shipped demos exist to show the difference, so it is worth
    /// noticing if one of them quietly stops.
    func testTheDemoThemesDemonstrateBothModes() {
        let lunar = ThemeLoader.loadTheme(from: URL(fileURLWithPath: "Themes/spacyAppsLunarAvatar"))
        XCTAssertEqual(lunar.layout.resize, .free, "the station should resize freely")
        XCTAssertFalse(lunar.window.locksAspect, "and nine-slice, so it does not distort")

        let unicorn = ThemeLoader.loadTheme(
            from: URL(fileURLWithPath: "Themes/spacyAppsUnicornOverlord")
        )
        XCTAssertEqual(unicorn.layout.resize, .aspect, "the frame should hold its proportions")
    }
}
