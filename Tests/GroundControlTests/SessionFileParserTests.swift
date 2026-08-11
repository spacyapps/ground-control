// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

final class SessionFileParserTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionFileParserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ lines: [String], name: String = "session.jsonl") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func line(message: String, needsAction: Bool = false, ts: Int = 100) -> String {
        """
        {"schema":1,"session_id":"abc","name":"avaterm","cwd":"/tmp/avaterm",\
        "tty":"/dev/ttys008","event":"Stop","state":"done","message":"\(message)",\
        "needs_action":\(needsAction),"ts":\(ts)}
        """
    }

    func testLastLineWins() throws {
        let url = try write([line(message: "first"), line(message: "second", ts: 200)])
        let event = SessionFileParser.latestEvent(at: url)
        XCTAssertEqual(event?.message, "second")
        XCTAssertEqual(event?.timestamp, Date(timeIntervalSince1970: 200))
    }

    /// A hook appending while we read can leave a truncated final line. The row
    /// must fall back to the last good state rather than blanking.
    func testHalfWrittenTrailingLineFallsBackToPreviousLine() throws {
        let url = try write([line(message: "good"), #"{"session_id":"abc","mess"#])
        XCTAssertEqual(SessionFileParser.latestEvent(at: url)?.message, "good")
    }

    func testBlankLinesAreSkipped() throws {
        let url = try write([line(message: "kept"), "", "   "])
        XCTAssertEqual(SessionFileParser.latestEvent(at: url)?.message, "kept")
    }

    func testEmptyFileReturnsNil() throws {
        let url = try write([])
        XCTAssertNil(SessionFileParser.latestEvent(at: url))
    }

    func testMissingFileReturnsNil() {
        let url = directory.appendingPathComponent("nope.jsonl")
        XCTAssertNil(SessionFileParser.latestEvent(at: url))
    }

    /// A newer cc-notify could emit a state this build has never heard of;
    /// that must degrade to idle, not fail the whole line.
    func testUnknownStateDecodesToIdle() throws {
        let url = try write([
            #"{"session_id":"abc","state":"teleporting","message":"hi","ts":1}"#
        ])
        XCTAssertEqual(SessionFileParser.latestEvent(at: url)?.state, .idle)
    }

    func testMinimalLineDecodesWithDefaults() throws {
        let url = try write([#"{"session_id":"abc"}"#])
        let event = SessionFileParser.latestEvent(at: url)
        XCTAssertEqual(event?.sessionID, "abc")
        XCTAssertEqual(event?.message, "")
        XCTAssertFalse(event?.needsAction ?? true)
    }

    func testAgentEventDecodes() throws {
        let json = #"{"session_id":"abc","agent_id":"a1","agent_type":"","#
            + #""state":"done","message":"Finished","needs_action":false,"ts":5}"#
        let url = try write([json])
        let event = SessionFileParser.latestAgentEvent(at: url)
        XCTAssertEqual(event?.agentID, "a1")
        XCTAssertEqual(event?.message, "Finished")
    }
}
