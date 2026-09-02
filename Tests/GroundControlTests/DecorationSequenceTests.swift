// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// The playlist behind a multi-image corner decoration: each entry holds the
/// timeline for its own length, then the next takes over, looping.
final class DecorationSequenceTests: XCTestCase {
    private var dir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DecorationSequence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func still(_ name: String) throws -> BackgroundImage {
        let url = dir.appendingPathComponent(name)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4,
            pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return BackgroundImage(url: url, mode: .center, capInsets: NSEdgeInsets())
    }

    private func name(_ sample: (image: BackgroundImage, into: TimeInterval)?) throws -> String {
        try XCTUnwrap(sample).image.url.lastPathComponent
    }

    /// Stills: each holds `stillBeat`, then the timeline wraps.
    func testStillsEachHoldTheirBeatThenWrap() throws {
        let seq = DecorationSequence([try still("a.png"), try still("b.png"), try still("c.png")], stillBeat: 1)
        XCTAssertEqual(try name(seq.sample(at: 0.5)), "a.png")
        XCTAssertEqual(try name(seq.sample(at: 1.5)), "b.png")
        XCTAssertEqual(try name(seq.sample(at: 2.5)), "c.png")
        XCTAssertEqual(try name(seq.sample(at: 3.2)), "a.png", "the timeline loops")
    }

    /// The offset returned is into the *current* entry, not the whole timeline
    /// — so a gif entry would start from frame zero when its turn comes.
    func testOffsetIsIntoTheCurrentEntry() throws {
        let seq = DecorationSequence([try still("a.png"), try still("b.png")], stillBeat: 1)
        XCTAssertEqual(try XCTUnwrap(seq.sample(at: 1.25)).into, 0.25, accuracy: 0.001)
    }

    func testASingleImageIsAlwaysItself() throws {
        let seq = DecorationSequence([try still("only.png")], stillBeat: 1)
        XCTAssertEqual(try name(seq.sample(at: 99)), "only.png")
    }

    func testEmptySamplesToNil() {
        XCTAssertNil(DecorationSequence([], stillBeat: 1).sample(at: 0))
    }
}
