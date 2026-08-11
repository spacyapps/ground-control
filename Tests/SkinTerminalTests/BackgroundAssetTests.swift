import XCTest
@testable import SkinTerminal

/// The `assets` block accepts two shapes and has to survive both, plus every
/// way an author can get it wrong.
final class BackgroundAssetTests: XCTestCase {
    private var folder = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackgroundAssetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func touch(_ name: String) throws {
        try Data("x".utf8).write(to: folder.appendingPathComponent(name))
    }

    private func resolve(_ json: String) throws -> Theme.Backgrounds {
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: Data(json.utf8))
        return AssetResolver.backgrounds(from: manifest.assets, folder: folder)
    }

    /// The shorthand has to keep working: a bare filename means "just tile it".
    func testBareFilenameTilesWithNoCaps() throws {
        try touch("panel.png")
        let backgrounds = try resolve(#"{"assets":{"windowBackground":"panel.png"}}"#)
        let window = try XCTUnwrap(backgrounds.window)
        XCTAssertEqual(window.mode, .tile)
        XCTAssertFalse(window.hasCaps)
    }

    func testObjectFormCarriesModeAndCapInsets() throws {
        try touch("panel.png")
        let backgrounds = try resolve("""
        {"assets":{"windowBackground":{"image":"panel.png","mode":"stretch",
        "capInsets":{"top":28,"left":12,"bottom":10,"right":12}}}}
        """)
        let window = try XCTUnwrap(backgrounds.window)
        XCTAssertEqual(window.mode, .stretch)
        XCTAssertEqual(window.capInsets.top, 28)
        XCTAssertEqual(window.capInsets.left, 12)
        XCTAssertEqual(window.capInsets.bottom, 10)
        XCTAssertEqual(window.capInsets.right, 12)
        XCTAssertTrue(window.hasCaps)
    }

    /// A title bar is a fixed-height strip, so authors set only left/right —
    /// three-slice is nine-slice with two insets at zero.
    func testThreeSliceIsJustNineSliceWithZeroedInsets() throws {
        try touch("bar.png")
        let backgrounds = try resolve("""
        {"assets":{"titleBarBackground":{"image":"bar.png","capInsets":{"left":10,"right":10}}}}
        """)
        let bar = try XCTUnwrap(backgrounds.titleBar)
        XCTAssertEqual(bar.capInsets.left, 10)
        XCTAssertEqual(bar.capInsets.top, 0)
        XCTAssertEqual(bar.capInsets.bottom, 0)
    }

    func testNullAndMissingEntriesResolveToNothing() throws {
        let backgrounds = try resolve(#"{"assets":{"windowBackground":null}}"#)
        XCTAssertNil(backgrounds.window)
        XCTAssertNil(backgrounds.titleBar)
        XCTAssertNil(backgrounds.needsActionDot)
    }

    func testMissingFileResolvesToNothingRatherThanFailing() throws {
        try touch("real.png")
        let backgrounds = try resolve("""
        {"assets":{"windowBackground":"typo.png","titleBarBackground":"real.png"}}
        """)
        XCTAssertNil(backgrounds.window)
        XCTAssertNotNil(backgrounds.titleBar, "one bad path must not poison the rest")
    }

    func testUnknownModeFallsBackToTile() throws {
        try touch("panel.png")
        let backgrounds = try resolve("""
        {"assets":{"windowBackground":{"image":"panel.png","mode":"interpretive-dance"}}}
        """)
        XCTAssertEqual(backgrounds.window?.mode, .tile)
    }

    func testVideoIsNotAcceptedAsABackground() throws {
        try touch("panel.mov")
        let backgrounds = try resolve(#"{"assets":{"windowBackground":"panel.mov"}}"#)
        XCTAssertNil(backgrounds.window)
    }

    func testNeedsActionDotResolvesAsAPlainImage() throws {
        try touch("badge.png")
        let backgrounds = try resolve(#"{"assets":{"needsActionDot":"badge.png"}}"#)
        XCTAssertEqual(backgrounds.needsActionDot?.lastPathComponent, "badge.png")
    }

    /// Cap insets and resizing mode live on the NSImage instance, so two
    /// surfaces sharing a file must not share a cache entry.
    func testCacheKeyDistinguishesSameFileWithDifferentSettings() throws {
        try touch("panel.png")
        let url = folder.appendingPathComponent("panel.png")
        let tiled = BackgroundImage(url: url, mode: .tile, capInsets: NSEdgeInsets())
        let stretched = BackgroundImage(url: url, mode: .stretch, capInsets: NSEdgeInsets())
        let capped = BackgroundImage(
            url: url,
            mode: .tile,
            capInsets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        )
        XCTAssertNotEqual(tiled.cacheKey, stretched.cacheKey)
        XCTAssertNotEqual(tiled.cacheKey, capped.cacheKey)
        XCTAssertNotEqual(tiled, capped)
    }

    func testThemeWithNoAssetsBlockHasNoBackgrounds() throws {
        XCTAssertEqual(try resolve("{}"), Theme.Backgrounds.none)
    }

    /// Backgrounds are optional decoration; a theme is still valid without them.
    func testDefaultThemeHasNoBackgrounds() {
        XCTAssertEqual(DefaultTheme.theme.backgrounds, Theme.Backgrounds.none)
    }

    func testPromptExplainsThatTheCentreStretches() {
        let prompt = ThemePromptBuilder.prompt(for: .placeholder)
        XCTAssertTrue(prompt.contains("nine-slice"))
        XCTAssertTrue(prompt.contains("capInsets"))
        XCTAssertTrue(prompt.contains("CORNERS only"))
        XCTAssertTrue(prompt.contains("resizable"))
    }
}
