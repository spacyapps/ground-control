// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Themes are read only from Application Support, so the ones that ship inside
/// the app have to be copied out before they can appear in the picker at all.
final class ThemeSeederTests: XCTestCase {
    private var source = FileManager.default.temporaryDirectory
    private var destination = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString)")
        source = root.appendingPathComponent("bundled")
        destination = root.appendingPathComponent("installed")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: source.deletingLastPathComponent())
    }

    private func makeTheme(_ name: String, in folder: URL, manifest: String = "{}") throws {
        let dir = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("theme.json")
        try manifest.write(to: file, atomically: true, encoding: .utf8)
    }

    private func manifest(of name: String) throws -> String {
        try String(contentsOf: destination.appendingPathComponent(name)
            .appendingPathComponent("theme.json"), encoding: .utf8)
    }

    func testShippedThemesAreInstalledOnFirstRun() throws {
        try makeTheme("unicorns", in: source)
        try makeTheme("hull", in: source)

        let installed = ThemeSeeder.seed(from: source, into: destination)
        XCTAssertEqual(Set(installed), ["unicorns", "hull"])
        XCTAssertEqual(ThemeLoader.availableThemes(in: destination).count, 2)
    }

    /// The important one: an update must never take someone's edits with it.
    func testAnEditedThemeIsNeverOverwritten() throws {
        try makeTheme("unicorns", in: source, manifest: ##"{ "name": "Shipped" }"##)
        try makeTheme("unicorns", in: destination, manifest: ##"{ "name": "Mine" }"##)

        let installed = ThemeSeeder.seed(from: source, into: destination)
        XCTAssertTrue(installed.isEmpty, "an existing theme was replaced")
        XCTAssertTrue(try manifest(of: "unicorns").contains("Mine"))
    }

    /// Running twice must be as harmless as running once — every launch does.
    func testSeedingTwiceChangesNothing() throws {
        try makeTheme("unicorns", in: source)
        ThemeSeeder.seed(from: source, into: destination)
        try ##"{ "name": "Edited" }"##.write(
            to: destination.appendingPathComponent("unicorns/theme.json"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertTrue(ThemeSeeder.seed(from: source, into: destination).isEmpty)
        XCTAssertTrue(try manifest(of: "unicorns").contains("Edited"))
    }

    func testFoldersWithoutAManifestAreNotThemes() throws {
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("not-a-theme"),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(ThemeSeeder.seed(from: source, into: destination).isEmpty)
    }

    /// Running from a checkout rather than a bundle: nothing to install, and
    /// nothing to complain about either.
    func testNoBundledThemesIsNotAnError() {
        XCTAssertTrue(ThemeSeeder.seed(from: nil, into: destination).isEmpty)
    }
}
