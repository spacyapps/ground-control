// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import SkinTerminal

/// A typo in one avatar path must cost you that one avatar, not the theme.
final class AssetResolverTests: XCTestCase {
    private var folder = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetResolverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func touch(_ name: String) throws {
        try Data("x".utf8).write(to: folder.appendingPathComponent(name))
    }

    private func manifest(_ json: String) throws -> ThemeManifest.Avatar {
        try JSONDecoder().decode(ThemeManifest.Avatar.self, from: Data(json.utf8))
    }

    private func resolve(_ json: String) throws -> Theme.Avatar {
        AssetResolver.avatar(from: try manifest(json), folder: folder, fallback: DefaultTheme.avatar)
    }

    func testResolvesStillsAndAnimatedImages() throws {
        try touch("cat.png")
        try touch("run.gif")
        let avatar = try resolve(#"""
        {"states":{"idle":{"image":"cat.png"},"working":{"image":"run.gif"}}}
        """#)
        XCTAssertEqual(avatar.asset(for: .idle), .image(folder.appendingPathComponent("cat.png")))
        XCTAssertEqual(avatar.asset(for: .working), .image(folder.appendingPathComponent("run.gif")))
        XCTAssertNil(avatar.asset(for: .done), "an omitted state draws nothing")
    }

    func testResolvesVideoWithLoopAndMuteDefaults() throws {
        try touch("run.mov")
        let avatar = try resolve(#"{"states":{"working":{"video":"run.mov"}}}"#)
        XCTAssertEqual(
            avatar.asset(for: .working),
            .video(folder.appendingPathComponent("run.mov"), loop: true, muted: true)
        )
    }

    func testMissingFileResolvesToNothingRatherThanFailing() throws {
        try touch("present.png")
        let avatar = try resolve(#"""
        {"states":{"idle":{"image":"typo.png"},"done":{"image":"present.png"}}}
        """#)
        XCTAssertNil(avatar.asset(for: .idle))
        XCTAssertNotNil(avatar.asset(for: .done), "one bad path must not poison the rest")
    }

    /// macOS has no native webm decoder, so the format is refused rather than
    /// silently producing a blank avatar.
    func testUnsupportedVideoFormatIsRejected() throws {
        try touch("run.webm")
        let avatar = try resolve(#"{"states":{"working":{"video":"run.webm"}}}"#)
        XCTAssertNil(avatar.asset(for: .working))
    }

    func testVideoWinsWhenBothKeysAreSet() throws {
        try touch("a.png")
        try touch("a.mov")
        let avatar = try resolve(#"{"states":{"working":{"image":"a.png","video":"a.mov"}}}"#)
        guard case .video = avatar.asset(for: .working) else {
            return XCTFail("expected the video to win")
        }
    }

    func testGeometryFallsBackToDefaults() throws {
        let avatar = try resolve(#"{"states":{}}"#)
        XCTAssertEqual(avatar.size, DefaultTheme.avatar.size)
        XCTAssertEqual(avatar.position, DefaultTheme.avatar.position)
        XCTAssertFalse(avatar.isHidden, "no artwork still draws the built-in face")
        XCTAssertNil(avatar.asset(for: .idle), "and it does so without theme artwork")
    }

    /// The single documented way to switch avatars off.
    func testZeroSizeHidesAvatarsEntirely() throws {
        XCTAssertTrue(try resolve(#"{"size":0,"states":{}}"#).isHidden)
    }

    func testDrawnDefaultExistsForEveryState() {
        for state in SessionState.allCases {
            XCTAssertNotNil(DrawnAvatar.symbol(for: state), "no built-in face for \(state.rawValue)")
        }
        XCTAssertTrue(DrawnAvatar.isAnimated(.working))
        XCTAssertFalse(DrawnAvatar.isAnimated(.idle))
    }

    func testGeometryIsHonouredWhenSet() throws {
        let avatar = try resolve(#"{"size":72,"position":"left","cornerRadius":4,"states":{}}"#)
        XCTAssertEqual(avatar.size, 72)
        XCTAssertEqual(avatar.position, .left)
        XCTAssertEqual(avatar.cornerRadius, 4)
    }

    /// The shipped example theme is the reference authors copy — if its paths
    /// rot, the docs lie.
    func testShippedExampleThemeResolvesEveryState() throws {
        let repoTheme = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Themes/example-avatars")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: repoTheme.appendingPathComponent("theme.json").path),
            "example theme not present"
        )
        let theme = ThemeLoader.loadTheme(from: repoTheme)
        for state in SessionState.allCases {
            XCTAssertNotNil(theme.avatar.asset(for: state), "no avatar resolved for \(state.rawValue)")
        }
    }
}
