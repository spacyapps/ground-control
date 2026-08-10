import XCTest
@testable import SkinTerminal

/// The contract under test is docs/THEMING.md's one rule: everything is
/// optional, and an omitted key inherits the code default.
final class ThemeLoaderTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemeLoaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func makeTheme(named name: String, json: String) throws -> URL {
        let folder = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try json.write(
            to: folder.appendingPathComponent("theme.json"),
            atomically: true,
            encoding: .utf8
        )
        return folder
    }

    func testEmptyManifestIsAValidTheme() throws {
        let folder = try makeTheme(named: "empty", json: "{}")
        let theme = ThemeLoader.loadTheme(from: folder)
        XCTAssertEqual(theme.colors.needsAction, DefaultTheme.colors.needsAction)
        XCTAssertEqual(theme.layout.rowMaxHeight, DefaultTheme.layout.rowMaxHeight)
        // Name falls back to the folder when the manifest omits it.
        XCTAssertEqual(theme.name, "empty")
    }

    func testSingleColourOverrideLeavesEverythingElseAtDefault() throws {
        let folder = try makeTheme(
            named: "amber",
            json: ##"{"name":"Amber","colors":{"needsAction":"#ffb000"}}"##
        )
        let theme = ThemeLoader.loadTheme(from: folder)
        XCTAssertEqual(theme.name, "Amber")
        XCTAssertEqual(theme.colors.needsAction, NSColor(hex: "#ffb000"))
        XCTAssertEqual(theme.colors.working, DefaultTheme.colors.working)
        XCTAssertEqual(theme.typography.nameSize, DefaultTheme.typography.nameSize)
    }

    func testMalformedColourFallsBackRatherThanFailing() throws {
        let folder = try makeTheme(
            named: "broken",
            json: ##"{"colors":{"needsAction":"not-a-colour","working":"#00ff00"}}"##
        )
        let theme = ThemeLoader.loadTheme(from: folder)
        XCTAssertEqual(theme.colors.needsAction, DefaultTheme.colors.needsAction)
        XCTAssertEqual(theme.colors.working, NSColor(hex: "#00ff00"))
    }

    func testInvalidJSONFallsBackToDefaultTheme() throws {
        let folder = try makeTheme(named: "garbage", json: "{ this is not json")
        let theme = ThemeLoader.loadTheme(from: folder)
        XCTAssertEqual(theme.name, DefaultTheme.theme.name)
    }

    func testMissingManifestFallsBackToDefaultTheme() {
        let folder = directory.appendingPathComponent("absent")
        XCTAssertEqual(ThemeLoader.loadTheme(from: folder).name, DefaultTheme.theme.name)
    }

    func testDensityCompactIsHonoured() throws {
        let folder = try makeTheme(named: "tight", json: #"{"layout":{"density":"compact"}}"#)
        XCTAssertTrue(ThemeLoader.loadTheme(from: folder).layout.isCompact)
    }

    func testAvailableThemesOnlyListsFoldersHoldingAManifest() throws {
        try makeTheme(named: "real", json: "{}")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("not-a-theme"),
            withIntermediateDirectories: true
        )
        let found = ThemeLoader.availableThemes(in: directory).map(\.lastPathComponent)
        XCTAssertEqual(found, ["real"])
    }

    func testRepositoryDefaultThemeMatchesCodeDefaults() throws {
        // Themes/default/theme.json ships as the copyable reference. If it
        // drifts from DefaultTheme, authors inherit surprises.
        let repoTheme = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SkinTerminalTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Themes/default")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: repoTheme.appendingPathComponent("theme.json").path),
            "reference theme not present"
        )
        let theme = ThemeLoader.loadTheme(from: repoTheme)
        XCTAssertEqual(theme.colors.needsAction, DefaultTheme.colors.needsAction)
        XCTAssertEqual(theme.colors.working, DefaultTheme.colors.working)
        XCTAssertEqual(theme.colors.windowBackground, DefaultTheme.colors.windowBackground)
        XCTAssertEqual(theme.layout.rowMaxHeight, DefaultTheme.layout.rowMaxHeight)
        XCTAssertEqual(theme.typography.nameSize, DefaultTheme.typography.nameSize)
    }
}
