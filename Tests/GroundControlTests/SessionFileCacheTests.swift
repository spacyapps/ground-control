// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The parser remembers what it read, because the store re-reads every session
/// twice a second and most have not changed.
///
/// The danger of any such cache is a stale row: the panel is a monitor, and a
/// monitor that shows yesterday's state is worse than a slow one. These are the
/// cases where it could go stale.
final class SessionFileCacheTests: XCTestCase {
    private var folder = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        SessionFileParser.clearCache()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ lines: [String], to name: String = "s.jsonl") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    private func line(_ message: String) -> String {
        #"{"session_id":"a","name":"n","cwd":"/tmp","state":"working","message":"\#(message)","ts":1}"#
    }

    func testItReadsTheFileAtAll() throws {
        let url = try write([line("first")])
        XCTAssertEqual(SessionFileParser.latestEvent(at: url)?.message, "first")
    }

    /// The normal case: a hook appends. The row must follow.
    func testAnAppendedLineIsSeen() throws {
        let url = try write([line("first")])
        XCTAssertEqual(SessionFileParser.latestEvent(at: url)?.message, "first")

        try write([line("first"), line("second")], to: "s.jsonl")
        XCTAssertEqual(
            SessionFileParser.latestEvent(at: url)?.message,
            "second",
            "the cache went stale on an append"
        )
    }

    /// The awkward case: a rewrite that lands on exactly the same length. Size
    /// cannot tell these apart, so the modification date has to.
    func testAChangeOfTheSameLengthIsStillSeen() throws {
        let url = try write([line("aaaaa")])
        XCTAssertEqual(SessionFileParser.latestEvent(at: url)?.message, "aaaaa")

        // Far enough apart that the timestamp must differ on any filesystem.
        Thread.sleep(forTimeInterval: 0.05)
        try write([line("bbbbb")], to: "s.jsonl")
        XCTAssertEqual(
            SessionFileParser.latestEvent(at: url)?.message,
            "bbbbb",
            "same size, different content — the date should have caught it"
        )
    }

    /// A file that never changes must give the same answer, not a nil once the
    /// cache is involved.
    func testRepeatedReadsAreStable() throws {
        let url = try write([line("steady")])
        for _ in 0..<5 {
            XCTAssertEqual(SessionFileParser.latestEvent(at: url)?.message, "steady")
        }
    }

    /// Junk should be read once and remembered as junk, rather than re-read on
    /// every reload for as long as it sits in the folder.
    func testAnUndecodableFileDoesNotBecomeARow() throws {
        let url = try write(["not json at all"])
        XCTAssertNil(SessionFileParser.latestEvent(at: url))
        XCTAssertNil(SessionFileParser.latestEvent(at: url))
    }

    /// A half-written trailing line still falls back to the previous good one —
    /// the reason the scan runs backwards in the first place.
    func testAHalfWrittenLastLineFallsBack() throws {
        let url = try write([line("complete"), #"{"session_id":"a","mess"#])
        XCTAssertEqual(SessionFileParser.latestEvent(at: url)?.message, "complete")
    }
}
