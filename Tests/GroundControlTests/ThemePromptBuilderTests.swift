// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The prompt's whole job is producing a theme that drops in and works, so the
/// manifest it embeds must be one the app can actually load.
final class ThemePromptBuilderTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemePromptTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var brief: ThemeBrief {
        ThemeBrief(
            name: "Neon Cat",
            subject: "a neon cat",
            style: "vaporwave",
            mood: "magenta on black",
            wantsAnimation: true,
            background: "worn brass panel",
            avatarSize: 56,
            position: "left"
        )
    }

    func testStarterManifestDecodesAsARealTheme() throws {
        let json = ThemeStarterManifest.text(for: brief)
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.name, "Neon Cat")
        XCTAssertEqual(manifest.avatar?.size, 56)
        XCTAssertEqual(manifest.avatar?.position, "left")
        XCTAssertEqual(manifest.avatar?.states?["working"]?.image, "working.gif")
    }

    func testStillsInsteadOfAnimationChangeTheWorkingFilename() throws {
        var still = brief
        still.wantsAnimation = false
        let json = ThemeStarterManifest.text(for: still)
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.avatar?.states?["working"]?.image, "working.png")
        // The artwork brief must not demand motion; the format notes may still
        // mention GIF as a supported option.
        XCTAssertFalse(ThemePromptBuilder.prompt(for: still).contains("must be **animated GIFs**"))
        XCTAssertTrue(ThemePromptBuilder.prompt(for: brief).contains("must be **animated GIFs**"))
    }

    func testPromptNamesEveryStateAndTheAuthorsAnswers() {
        let prompt = ThemePromptBuilder.prompt(for: brief)
        // needs-input animates alongside working now: both are states asking
        // for attention, and idle and done stay still.
        for filename in ["idle.png", "working.gif", "needs-input.gif", "done.png"] {
            XCTAssertTrue(prompt.contains(filename), "prompt never mentions \(filename)")
        }
        XCTAssertTrue(prompt.contains("a neon cat"))
        XCTAssertTrue(prompt.contains("vaporwave"))
        XCTAssertTrue(prompt.contains("magenta on black"))
        XCTAssertTrue(prompt.contains("needsAction"), "the palette reference must be included")
    }

    /// macOS cannot decode webm, so the prompt has to say so — otherwise an LLM
    /// will happily produce one.
    /// A background is optional, and asking a model for one you did not want
    /// is how themes end up with a dark rectangle behind everything.
    func testBackgroundSectionOnlyAppearsWhenRequested() {
        var plain = brief
        plain.background = "   "
        let without = ThemePromptBuilder.prompt(for: plain)
        XCTAssertFalse(without.contains("nine-slice"))
        XCTAssertTrue(without.contains("colours only"))

        let with = ThemePromptBuilder.prompt(for: brief)
        XCTAssertTrue(with.contains("nine-slice"))
        XCTAssertTrue(with.contains("worn brass panel"))
    }

    /// The analyser is the most eye-catching part of the panel, so the model
    /// should be told it can colour it.
    func testPromptCoversTheMatrixKeys() {
        let prompt = ThemePromptBuilder.prompt(for: brief)
        for key in ["matrix", "alarm", "messages"] {
            XCTAssertTrue(prompt.localizedCaseInsensitiveContains(key), "prompt never mentions \(key)")
        }
    }

    /// A model shown commented JSON emits commented JSON, and the file then
    /// falls back to the default theme with no visible cause.
    func testPromptForbidsCommentsInTheJSON() {
        let prompt = ThemePromptBuilder.prompt(for: brief)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("No comments"))
        XCTAssertFalse(prompt.contains("// "), "the prompt itself must not show commented JSON")
    }

    func testPromptWarnsAgainstWebm() {
        XCTAssertTrue(ThemePromptBuilder.prompt(for: brief).contains(".webm"))
    }

    /// Alpha must survive into the manifest: the default divider is fully
    /// transparent, and a 6-digit value would make hairlines appear.
    func testTransparentDefaultsKeepTheirAlpha() throws {
        let json = ThemeStarterManifest.text(for: brief)
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.colors?["divider"]?.count, 9, "expected #rrggbbaa")

        let resolved = ThemeLoader.resolve(manifest, folder: nil)
        XCTAssertEqual(
            resolved.colors.divider.usingColorSpace(.sRGB)?.alphaComponent,
            DefaultTheme.colors.divider.usingColorSpace(.sRGB)?.alphaComponent
        )
        XCTAssertEqual(manifest.colors?["needsAction"]?.count, 7, "opaque colours stay 6-digit")
    }

    func testQuotesInNamesDoNotBreakTheManifest() throws {
        var awkward = brief
        awkward.name = #"The "Best" Theme"#
        awkward.subject = #"a cat with a \ backslash"#
        let json = ThemeStarterManifest.text(for: awkward)
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.name, #"The "Best" Theme"#)
    }

    func testSlugIsAUsableFolderName() {
        XCTAssertEqual(brief.slug, "neon-cat")

        var messy = brief
        messy.name = "  My / Weird: Theme!  "
        XCTAssertEqual(messy.slug, "my-weird-theme")

        var empty = brief
        empty.name = "***"
        XCTAssertEqual(empty.slug, "my-theme", "a name with nothing usable still yields a folder")
    }

    // MARK: - Scaffold

    func testScaffoldCreatesALoadableTheme() throws {
        let folder = try ThemeScaffold.create(from: brief, in: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("theme.json").path))
        // Two files, not one: a single file gets pasted whole, which hands the
        // model the frame instructions in the same breath as "do the moods and
        // stop".
        for stage in ["PROMPT-1-moods.md", "PROMPT-2-frame.md"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(stage).path),
                "\(stage) should be written into the theme folder"
            )
        }
        let moods = try String(
            contentsOf: folder.appendingPathComponent("PROMPT-1-moods.md"),
            encoding: .utf8
        )
        XCTAssertFalse(moods.contains("capInsets"), "stage one must not leak the frame")

        let theme = ThemeLoader.loadTheme(from: folder)
        XCTAssertEqual(theme.name, "Neon Cat")
        XCTAssertEqual(theme.avatar.size, 56)
        XCTAssertEqual(theme.avatar.position, .left)
    }

    /// The folder is created before the art exists, so every state resolves to
    /// nothing and the app must fall back to its drawn faces rather than break.
    func testScaffoldedThemeWorksBeforeAnyArtworkExists() throws {
        let folder = try ThemeScaffold.create(from: brief, in: directory)
        let theme = ThemeLoader.loadTheme(from: folder)
        for state in SessionState.allCases {
            XCTAssertNil(theme.avatar.asset(for: state))
        }
        XCTAssertFalse(theme.avatar.isHidden, "drawn faces still apply")
    }

    func testScaffoldRefusesToOverwriteAnExistingTheme() throws {
        try ThemeScaffold.create(from: brief, in: directory)
        XCTAssertThrowsError(try ThemeScaffold.create(from: brief, in: directory))
    }

    func testScaffoldedThemeIsDiscoverable() throws {
        try ThemeScaffold.create(from: brief, in: directory)
        let found = ThemeLoader.availableThemes(in: directory).map(\.lastPathComponent)
        XCTAssertEqual(found, ["neon-cat"])
    }
}

extension ThemePromptBuilderTests {
    /// Numbering applies within part two, which is where the numbered
    /// sections live now.
    private func headings(_ brief: ThemeBrief) -> [String] {
        ThemePromptBuilder.partTwo(for: brief)
            .split(separator: "\n")
            .filter { $0.hasPrefix("## ") && $0.contains(". ") }
            .map(String.init)
    }

    /// Sections are optional, so hand-numbered headings drift the moment one is
    /// skipped — which is exactly what happened: 1, (unnumbered), (unnumbered),
    /// 3, 4.
    func testSectionsAreNumberedInSequence() {
        var withoutBackground = brief
        withoutBackground.background = ""

        for candidate in [brief, withoutBackground] {
            let numbers = headings(candidate).compactMap { line -> Int? in
                Int(line.dropFirst(3).prefix(while: \.isNumber))
            }
            XCTAssertEqual(numbers, Array(1...numbers.count), "headings out of sequence")
            XCTAssertGreaterThanOrEqual(numbers.count, 2)
        }
    }

    /// A JSON example that disagrees with the prose wins, because it is the
    /// concrete thing. The example must show the API the prompt describes.
    func testTheExampleUsesTheCurrentWindowAPI() {
        let prompt = ThemePromptBuilder.prompt(for: brief)
        XCTAssertTrue(prompt.contains("\"lockAspect\""))
        XCTAssertTrue(prompt.contains("\"removeBackground\""))
        XCTAssertFalse(
            prompt.contains("\"windowBackground\": {"),
            "the superseded assets API must not appear in the example"
        )
    }
}
