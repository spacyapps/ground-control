// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// Parsing the `cornerDecorations` manifest block into `Theme.CornerDecorations`.
final class CornerDecorationAssetTests: XCTestCase {
    private var folder = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CornerDecorationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func touch(_ name: String) throws {
        try Data("x".utf8).write(to: folder.appendingPathComponent(name))
    }

    private func resolve(_ json: String) throws -> Theme.CornerDecorations {
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: Data(json.utf8))
        return AssetResolver.cornerDecorations(from: manifest.cornerDecorations, folder: folder)
    }

    func testImageParsesWithOffsetAndKeying() throws {
        try touch("chest.gif")
        let decorations = try resolve("""
        {"cornerDecorations":{"bottomRight":{"image":"chest.gif","removeBackground":"#FF00FF",
        "offset":{"x":-12,"y":8}}}}
        """)
        let decoration = try XCTUnwrap(decorations.bottomRight)
        guard case .image(let backgrounds) = decoration.asset, let background = backgrounds.first else {
            return XCTFail("expected an image asset")
        }
        let magenta = try XCTUnwrap(NSColor(hex: "#FF00FF"))
        XCTAssertEqual(background.removeBackground, .color(magenta))
        XCTAssertEqual(decoration.offset, CGSize(width: -12, height: 8))
    }

    /// `image` takes a list — the frames a corner rotates through, one step
    /// per working spell.
    func testImageAcceptsAListOfFiles() throws {
        try touch("a.png")
        try touch("b.png")
        let decorations = try resolve(#"{"cornerDecorations":{"topLeft":{"image":["a.png","b.png"]}}}"#)
        guard case .image(let backgrounds) = decorations.topLeft?.asset else {
            return XCTFail("expected an image asset")
        }
        XCTAssertEqual(backgrounds.map { $0.url.lastPathComponent }, ["a.png", "b.png"])
    }

    /// A bare string is still one file, decoded into a one-element list.
    func testImageStillAcceptsABareString() throws {
        try touch("only.png")
        let decorations = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"only.png"}}}"#)
        guard case .image(let backgrounds) = decorations.topLeft?.asset else {
            return XCTFail("expected an image asset")
        }
        XCTAssertEqual(backgrounds.map { $0.url.lastPathComponent }, ["only.png"])
    }

    func testOffsetDefaultsToZeroWhenOmitted() throws {
        try touch("palm.png")
        let decorations = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"palm.png"}}}"#)
        XCTAssertEqual(decorations.topLeft?.offset, .zero)
    }

    func testScaleParses() throws {
        try touch("ship.apng")
        let decorations = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"ship.apng","scale":0.5}}}"#)
        XCTAssertEqual(decorations.topLeft?.scale, 0.5)
    }

    func testScaleDefaultsToOneWhenOmitted() throws {
        try touch("palm.png")
        let decorations = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"palm.png"}}}"#)
        XCTAssertEqual(decorations.topLeft?.scale, 1)
    }

    /// 0 or negative would hide or invert the art — neither is a meaningful
    /// "scale", so both fall back to the real size rather than do that.
    func testScaleFallsBackToOneWhenZeroOrNegative() throws {
        try touch("a.png")
        try touch("b.png")
        let zero = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"a.png","scale":0}}}"#)
        let negative = try resolve(#"{"cornerDecorations":{"topLeft":{"image":"b.png","scale":-2}}}"#)
        XCTAssertEqual(zero.topLeft?.scale, 1)
        XCTAssertEqual(negative.topLeft?.scale, 1)
    }

    func testVideoWinsOverImageWhenBothAreSet() throws {
        try touch("clip.mp4")
        try touch("fallback.png")
        let decorations = try resolve("""
        {"cornerDecorations":{"topRight":{"image":"fallback.png","video":"clip.mp4",
        "loop":false,"muted":false}}}
        """)
        guard case .video(let url, let loop, let muted) = decorations.topRight?.asset else {
            return XCTFail("expected a video asset")
        }
        XCTAssertEqual(url.lastPathComponent, "clip.mp4")
        XCTAssertFalse(loop)
        XCTAssertFalse(muted)
    }

    func testVideoLoopAndMutedDefaultToTrue() throws {
        try touch("clip.mov")
        let decorations = try resolve(#"{"cornerDecorations":{"topRight":{"video":"clip.mov"}}}"#)
        guard case .video(_, let loop, let muted) = decorations.topRight?.asset else {
            return XCTFail("expected a video asset")
        }
        XCTAssertTrue(loop)
        XCTAssertTrue(muted)
    }

    func testUnsupportedVideoExtensionResolvesToNothing() throws {
        try touch("clip.webm")
        let decorations = try resolve(#"{"cornerDecorations":{"topRight":{"video":"clip.webm"}}}"#)
        XCTAssertNil(decorations.topRight)
    }

    /// One corner's typo must not poison the other three.
    func testMissingFileResolvesToNothingRatherThanFailingTheOthers() throws {
        try touch("real.png")
        let decorations = try resolve("""
        {"cornerDecorations":{"topLeft":{"image":"typo.png"},"bottomLeft":{"image":"real.png"}}}
        """)
        XCTAssertNil(decorations.topLeft)
        XCTAssertNotNil(decorations.bottomLeft)
    }

    func testAllFourCornersAreIndependentlyAddressable() throws {
        for name in ["a.png", "b.png", "c.png", "d.png"] { try touch(name) }
        let decorations = try resolve("""
        {"cornerDecorations":{
            "topLeft":{"image":"a.png"},"topRight":{"image":"b.png"},
            "bottomLeft":{"image":"c.png"},"bottomRight":{"image":"d.png"}
        }}
        """)
        XCTAssertNotNil(decorations.topLeft)
        XCTAssertNotNil(decorations.topRight)
        XCTAssertNotNil(decorations.bottomLeft)
        XCTAssertNotNil(decorations.bottomRight)
        XCTAssertFalse(decorations.isEmpty)
    }

    func testNoBlockMeansNoDecorations() throws {
        let decorations = try resolve("{}")
        XCTAssertEqual(decorations, .none)
        XCTAssertTrue(decorations.isEmpty)
    }
}
