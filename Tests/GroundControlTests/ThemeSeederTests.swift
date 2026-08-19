// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Updating a shipped theme is a choice between two failures: never delivering
/// a fix, or deleting somebody's evening of recolouring. The seeder is allowed
/// to do the first and must never do the second.
final class ThemeSeederTests: XCTestCase {
    private var root = URL(fileURLWithPath: "/tmp")
    private var source: URL { root.appendingPathComponent("bundled") }
    private var destination: URL { root.appendingPathComponent("installed") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString)")
        try make(source.appendingPathComponent("demo"), manifest: ##"{"name":"Demo v1"}"##)
        UserDefaults.standard.removeObject(forKey: "seededThemeFingerprints")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removeObject(forKey: "seededThemeFingerprints")
    }

    private func make(_ folder: URL, manifest: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try manifest.write(
            to: folder.appendingPathComponent("theme.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func installedManifest() throws -> String {
        try String(
            contentsOf: destination.appendingPathComponent("demo/theme.json"),
            encoding: .utf8
        )
    }

    func testItInstallsWhatIsNotThere() throws {
        XCTAssertEqual(ThemeSeeder.seed(from: source, into: destination), ["demo"])
        XCTAssertTrue(try installedManifest().contains("Demo v1"))
    }

    /// The whole point. A theme nobody has touched gets the fix.
    func testItUpdatesAThemeNobodyHasTouched() throws {
        ThemeSeeder.seed(from: source, into: destination)
        try make(source.appendingPathComponent("demo"), manifest: ##"{"name":"Demo v2"}"##)

        XCTAssertEqual(ThemeSeeder.seed(from: source, into: destination), ["demo"])
        XCTAssertTrue(try installedManifest().contains("Demo v2"), "the update should have landed")
    }

    /// The line that must never be crossed, and the case a size-and-date check
    /// would miss: a recolour is exactly as long as what it replaced.
    func testItNeverTouchesAThemeSomebodyHasEdited() throws {
        ThemeSeeder.seed(from: source, into: destination)
        try make(destination.appendingPathComponent("demo"), manifest: ##"{"name":"Mine!!!!"}"##)
        try make(source.appendingPathComponent("demo"), manifest: ##"{"name":"Demo v2"}"##)

        XCTAssertEqual(
            ThemeSeeder.seed(from: source, into: destination),
            [],
            "an edited theme is not ours to replace"
        )
        XCTAssertTrue(try installedManifest().contains("Mine!!!!"), "their work survived")
    }

    /// A folder seeded before any record existed could equally be pristine or a
    /// weekend's work, so it is left alone.
    func testItLeavesAThemeItDidNotRecordAlone() throws {
        try make(destination.appendingPathComponent("demo"), manifest: ##"{"name":"From an old build"}"##)

        XCTAssertEqual(ThemeSeeder.seed(from: source, into: destination), [])
        XCTAssertTrue(try installedManifest().contains("old build"))
    }

    /// Running twice must not report an install it did not perform.
    func testItSaysNothingWhenThereIsNothingToDo() throws {
        ThemeSeeder.seed(from: source, into: destination)
        XCTAssertEqual(ThemeSeeder.seed(from: source, into: destination), [])
    }
}
