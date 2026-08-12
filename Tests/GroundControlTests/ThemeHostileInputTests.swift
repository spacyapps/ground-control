// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// A theme is authored by a language model from a prompt, so the manifest that
/// lands on disk is whatever the model felt like emitting that day. These are
/// the cases a QA sweep actually produced — each one must degrade to a usable
/// panel rather than an empty or broken one.
final class ThemeHostileInputTests: XCTestCase {
    private var dir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hostile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func theme(_ json: String) throws -> Theme {
        let folder = dir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = folder.appendingPathComponent("theme.json")
        try json.write(to: manifest, atomically: true, encoding: .utf8)
        return ThemeLoader.loadTheme(from: folder)
    }

    /// The manifest is not an object at all.
    func testNonObjectManifestsFallBack() throws {
        for json in ["[]", "\"hello\"", "null", "{}", ""] {
            XCTAssertEqual(try theme(json).colors.needsAction,
                           DefaultTheme.colors.needsAction,
                           "\(json) should yield defaults")
        }
    }

    /// Right keys, wrong types.
    func testWrongTypesFallBack() throws {
        let result = try theme(##"""
        { "name": 42, "colors": { "needsAction": 123 }, "avatar": { "size": "big" } }
        """##)
        XCTAssertEqual(result.colors.needsAction, DefaultTheme.colors.needsAction)
        XCTAssertEqual(result.avatar.size, DefaultTheme.avatar.size)
    }

    /// Avatar size is clamped: negative is meaningless, and a huge value would
    /// only decode artwork no row can show.
    func testAvatarSizeIsClamped() throws {
        XCTAssertEqual(try theme(##"{ "avatar": { "size": -40 } }"##).avatar.size, 0)
        XCTAssertEqual(try theme(##"{ "avatar": { "size": 99999 } }"##).avatar.size, 256)
        XCTAssertEqual(try theme(##"{ "avatar": { "size": 44.5 } }"##).avatar.size, 44.5)
    }

    /// Everything a model plausibly adds on its own initiative, at once:
    /// comments, trailing commas, an upper-case enum, a state that does not
    /// exist, and a key it invented.
    func testModelFlavouredManifest() throws {
        let result = try theme(##"""
        {
          // Theme by an over-helpful model
          "name": "Modelish",
          "colors": { "needsAction": "#FF2D55", },
          "avatar": {
            "position": "RIGHT",
            "states": { "unknownState": { "image": "x.png" }, },
          },
          "extraKeyItInvented": true,
        }
        """##)
        XCTAssertEqual(result.name, "Modelish")
        XCTAssertEqual(result.avatar.position, .right)
    }

    /// A `window.image` naming a file that was never generated must leave the
    /// window unshaped — shaping to a missing image would mask the panel away.
    func testWindowWithMissingImageIsNotShaped() throws {
        let result = try theme(##"{ "window": { "image": "never-generated.png" } }"##)
        XCTAssertFalse(result.window.isShaped)
    }
}

/// The brief comes from free-text fields, and its values are interpolated into
/// a JSON manifest that `ThemeScaffold` writes to disk. Anything that survives
/// a text field has to survive that round trip.
final class ThemeBriefRoundTripTests: XCTestCase {
    private var dir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("brief-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeBrief(name: String, subject: String, avatarSize: Int = 44) -> ThemeBrief {
        ThemeBrief(
            name: name,
            subject: subject,
            style: "style",
            mood: "mood",
            wantsAnimation: true,
            background: "background",
            avatarSize: avatarSize,
            position: "right"
        )
    }

    /// Newlines, quotes and non-Latin text in a brief must still produce a
    /// manifest that parses. A pasted multi-line name used to emit a raw
    /// newline inside a JSON string, so the scaffolded theme silently loaded
    /// as the default.
    func testAwkwardBriefsScaffoldParseableManifests() throws {
        let briefs = [
            makeBrief(name: "Multi\nLine", subject: "a\nb"),
            makeBrief(name: #"The "Best""#, subject: "x", avatarSize: 9999),
            makeBrief(name: "テーマ", subject: "猫", avatarSize: 1)
        ]
        for brief in briefs {
            let folder = try ThemeScaffold.create(from: brief, in: dir)
            let data = try Data(contentsOf: folder.appendingPathComponent("theme.json"))
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data),
                             "\(brief.slug) wrote an unparseable manifest")
        }
    }

    /// The prompt asks a model for a square canvas, so the number has to stay
    /// in a range something can actually generate.
    func testRecommendedPixelsStaysGeneratable() {
        XCTAssertEqual(makeBrief(name: "n", subject: "s", avatarSize: 1).recommendedPixels, 192)
        XCTAssertEqual(makeBrief(name: "n", subject: "s", avatarSize: 44).recommendedPixels, 192)
        XCTAssertEqual(makeBrief(name: "n", subject: "s", avatarSize: 9999).recommendedPixels, 512)
    }
}
