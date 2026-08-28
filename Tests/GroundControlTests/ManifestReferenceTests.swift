// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// `Themes/default/theme.json` claims to list every key a theme may set. This
/// is what makes the claim true a year from now.
///
/// The file is increasingly read by models rather than people — it sits beside
/// the working themes, so anything scanning the folder finds both the complete
/// key list and examples of the keys in use. A reference that silently falls
/// behind the code is worse than none: it does not look wrong, and whoever
/// trusts it inherits a key that no longer exists or misses one that does.
///
/// So the test derives the expected keys from `ThemeManifest` itself. Add a
/// property there and this fails until the reference documents it.
final class ManifestReferenceTests: XCTestCase {
    private var reference: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GroundControlTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Themes/default")
    }

    private func manifestJSON() throws -> [String: Any] {
        let url = reference.appendingPathComponent("theme.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "no reference theme")
        let stripped = ThemeLoader.forgiving(try Data(contentsOf: url))
        let object = try JSONSerialization.jsonObject(with: stripped)
        return try XCTUnwrap(object as? [String: Any], "the reference is not a JSON object")
    }

    /// Every key name anywhere in the file, at any depth.
    private func keyNames(in value: Any) -> Set<String> {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: Set(dictionary.keys)) { found, entry in
                found.formUnion(keyNames(in: entry.value))
            }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { $0.formUnion(keyNames(in: $1)) }
        }
        return []
    }

    /// Property names of a manifest type, via an instance decoded from `{}`.
    ///
    /// Every property is optional, so an empty object decodes into one of
    /// anything — which is what makes the whole type reflectable without
    /// needing a populated example. Computed properties (`Window.file`) are not
    /// stored and so are correctly absent.
    private func properties<T: Decodable>(of type: T.Type) throws -> Set<String> {
        let empty = try JSONDecoder().decode(type, from: Data("{}".utf8))
        return Set(Mirror(reflecting: empty).children.compactMap(\.label))
    }

    /// The one place a new nested type has to be added by hand. Everything
    /// inside each type is found by reflection; only the list of types is
    /// written down, and a type absent from here is a gap this test cannot see.
    private func allManifestKeys() throws -> Set<String> {
        var keys = try properties(of: ThemeManifest.self)
        keys.formUnion(try properties(of: ThemeManifest.Asset.self))
        keys.formUnion(try properties(of: ThemeManifest.Asset.Insets.self))
        keys.formUnion(try properties(of: ThemeManifest.Window.self))
        keys.formUnion(try properties(of: ThemeManifest.Matrix.self))
        keys.formUnion(try properties(of: ThemeManifest.Matrix.Feel.self))
        keys.formUnion(try properties(of: ThemeManifest.Matrix.Sleep.self))
        keys.formUnion(try properties(of: ThemeManifest.Avatar.self))
        keys.formUnion(try properties(of: ThemeManifest.Avatar.State.self))
        keys.formUnion(try properties(of: ThemeManifest.Layout.self))
        keys.formUnion(try properties(of: ThemeManifest.Typography.self))
        keys.formUnion(try properties(of: ThemeManifest.CornerDecorations.self))
        keys.formUnion(try properties(of: ThemeManifest.CornerDecoration.self))
        keys.formUnion(try properties(of: ThemeManifest.CornerDecoration.Offset.self))
        return keys
    }

    func testTheReferenceDocumentsEveryManifestKey() throws {
        let documented = keyNames(in: try manifestJSON())
        let missing = try allManifestKeys().subtracting(documented).sorted()

        XCTAssertTrue(
            missing.isEmpty,
            "Themes/default/theme.json is the documented key list and is missing: "
                + missing.joined(separator: ", ")
                + ". Add each one with the value the app uses when it is absent."
        )
    }

    /// `colors` is a free dictionary, so reflection cannot reach its names —
    /// they are the properties of the resolved `Theme.Colors` instead. A colour
    /// the app reads but the reference never names is one an author cannot
    /// discover except by reading Swift.
    func testTheReferenceNamesEveryColourTheAppReads() throws {
        let json = try manifestJSON()
        let declared = Set((json["colors"] as? [String: Any])?.keys ?? [:].keys)
        let read = Set(Mirror(reflecting: DefaultTheme.colors).children.compactMap(\.label))

        XCTAssertTrue(
            read.subtracting(declared).isEmpty,
            "colours the app reads but the reference does not list: "
                + read.subtracting(declared).sorted().joined(separator: ", ")
        )
    }

    /// Asset names are string literals in `AssetResolver`, reachable by neither
    /// reflection nor the type system, so they are repeated here deliberately.
    /// If this list and that function disagree, one of them is a bug.
    func testTheReferenceNamesEveryBackgroundSlot() throws {
        let json = try manifestJSON()
        let declared = Set((json["assets"] as? [String: Any])?.keys ?? [:].keys)
        let used: Set<String> = [
            "windowBackground", "titleBarBackground", "footerBackground",
            "needsActionDot", "brandMark"
        ]

        XCTAssertTrue(
            used.subtracting(declared).isEmpty,
            "asset slots AssetResolver reads but the reference omits: "
                + used.subtracting(declared).sorted().joined(separator: ", ")
        )
    }

    /// It must still load — a reference nobody can parse teaches the wrong
    /// syntax, and it is the file most likely to be copied verbatim.
    func testTheReferenceStillParsesAndMatchesTheCodeDefaults() throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: reference.appendingPathComponent("theme.json").path),
            "no reference theme"
        )
        let theme = ThemeLoader.loadTheme(from: reference)

        XCTAssertTrue(theme.warnings.isEmpty, "the reference failed to load: \(theme.warnings)")
        XCTAssertEqual(theme.colors.needsAction, DefaultTheme.colors.needsAction)
        XCTAssertEqual(theme.colors.working, DefaultTheme.colors.working)
        XCTAssertEqual(theme.colors.windowBackground, DefaultTheme.colors.windowBackground)
        XCTAssertEqual(theme.layout.rowMaxHeight, DefaultTheme.layout.rowMaxHeight)
        XCTAssertEqual(theme.layout.resize, DefaultTheme.layout.resize)
        XCTAssertEqual(theme.typography.nameSize, DefaultTheme.typography.nameSize)
        XCTAssertEqual(theme.avatar.size, DefaultTheme.avatar.size)
    }

    /// The reason it is not in the picker: choosing it cannot do anything.
    func testTheReferenceIsNotOfferedAsAChoice() throws {
        XCTAssertTrue(ThemeLoader.isReference(reference), "the reference must declare itself one")

        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("themes-\(UUID().uuidString)")
        let copy = folder.appendingPathComponent("default")
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.copyItem(
            at: reference.appendingPathComponent("theme.json"),
            to: copy.appendingPathComponent("theme.json")
        )

        // A real theme beside it, to prove the filter removes one and not both.
        let real = folder.appendingPathComponent("something")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try #"{"name":"Something"}"#
            .write(to: real.appendingPathComponent("theme.json"), atomically: true, encoding: .utf8)

        let offered = ThemeLoader.availableThemes(in: folder).map(\.lastPathComponent)
        XCTAssertEqual(offered, ["something"], "the reference must not appear in the picker")
    }
}
