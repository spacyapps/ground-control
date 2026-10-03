// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The context meter's contract: a Claude Code mod reports the window's fill
/// through `cc-notify`'s synthetic `ContextUsage` event, the number rides on
/// the row's last line, and the row view reads it back.
///
/// Runs the real script, for the reason `EmitterDialectTests` does: a wrong
/// field name and a working setup look identical from outside.
final class ContextMeterTests: XCTestCase {
    private var home = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var emitter: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Scripts/cc-notify").path
    }

    private var sessionFile: URL {
        home.appendingPathComponent("groundcontrol/ctx1.jsonl")
    }

    private func emit(_ payload: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [emitter]
        process.environment = ["TMPDIR": home.path + "/"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    private func lines() throws -> [[String: Any]] {
        guard let text = try? String(contentsOf: sessionFile, encoding: .utf8) else { return [] }
        return try text.split(separator: "\n").compactMap {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }

    private let prompt = """
    {"session_id":"ctx1","hook_event_name":"UserPromptSubmit","prompt":"hello","cwd":"/tmp/demo"}
    """

    private func usage(_ percent: String) -> String {
        """
        {"session_id":"ctx1","hook_event_name":"ContextUsage","context_percent":\(percent)}
        """
    }

    /// The report is not a hook: it must never conjure a row out of nothing,
    /// or a mod loading late would put a nameless row on the panel.
    func testAReportWithNoRowYetWritesNothing() throws {
        try emit(usage("40"))
        XCTAssertTrue(try lines().isEmpty)
    }

    /// The last line is the row's whole state, so the report has to carry all
    /// of it forward — a line holding only a percent would blank the row.
    func testAReportKeepsTheRowsStateAndAddsThePercent() throws {
        try emit(prompt)
        try emit(usage("40"))
        let all = try lines()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[1]["context_percent"] as? Int, 40)
        XCTAssertEqual(all[1]["message"] as? String, "hello")
        XCTAssertEqual(all[1]["state"] as? String, "working")
        XCTAssertEqual(all[1]["ts"] as? Int, all[0]["ts"] as? Int, "elapsed time must not restart")
    }

    /// No hook payload carries the figure, so the next real event would erase
    /// the bar if it were not latched from the line before.
    func testTheNextHookEventKeepsThePercent() throws {
        try emit(prompt)
        try emit(usage("55"))
        try emit("""
        {"session_id":"ctx1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}
        """)
        XCTAssertEqual(try lines().last?["context_percent"] as? Int, 55)
    }

    /// A row that has never been reported must not claim a figure: the key is
    /// null, not zero, so the row draws no bar.
    func testARowNeverReportedHasNoPercent() throws {
        try emit(prompt)
        XCTAssertNil(try lines().last?["context_percent"] as? Int)
    }

    func testOutOfRangeAndNonNumericReportsAreClampedOrIgnored() throws {
        try emit(prompt)
        try emit(usage("250"))
        XCTAssertEqual(try lines().last?["context_percent"] as? Int, 100)
        try emit(usage("\"lots\""))
        XCTAssertEqual(try lines().count, 2, "a non-number writes nothing")
    }

    // MARK: - The app's side

    func testTheAppDecodesThePercent() throws {
        let json = #"{"session_id":"ctx1","state":"working","message":"x","context_percent":72}"#
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.contextPercent, 72)
    }

    func testAnAbsentOrNullPercentDecodesToNil() throws {
        for json in [#"{"session_id":"ctx1"}"#, #"{"session_id":"ctx1","context_percent":null}"#] {
            let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
            XCTAssertNil(event.contextPercent)
        }
    }

    func testTheAppClampsAHandWrittenPercent() throws {
        let json = #"{"session_id":"ctx1","context_percent":900}"#
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.contextPercent, 100)
    }
}
