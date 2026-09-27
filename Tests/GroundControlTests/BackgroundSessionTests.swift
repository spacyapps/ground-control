// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Claude Code's background sessions, run through the real emitter.
///
/// Measured 2026-09-26 on 2.1.283. Backgrounding a session hands the
/// conversation to a new session id inside the daemon's own pty; the old
/// transcript ends on a `continued-in` line and the old id never fires again,
/// so its row sat on "working" for a day. The daemon also starts sessions that
/// only ever send SessionStart. Both are told apart by `CLAUDE_JOB_DIR`, the
/// one marker a background session's hooks carry and a foreground one's do not.
final class BackgroundSessionTests: XCTestCase {
    private var home = URL(fileURLWithPath: NSTemporaryDirectory())

    private var rows: URL { home.appendingPathComponent("groundcontrol") }
    private var project: URL { home.appendingPathComponent("projects/-Users-you-seed") }

    private let old = "c05de2b8-a36d-4648-9ec6-916b6970f6b7"
    private let new = "7417cbc5-7a03-4160-a61e-61dd5ffdf998"

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("background-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rows.appendingPathComponent("agents"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var emitter: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Scripts/cc-notify").path
    }

    private func emit(_ payload: String, background: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [emitter]
        var environment = ["TMPDIR": home.path + "/"]
        if background { environment["CLAUDE_JOB_DIR"] = home.appendingPathComponent("jobs/7417cbc5").path }
        process.environment = environment
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    private func payload(_ id: String, _ event: String, _ extra: String = "") -> String {
        """
        {"session_id":"\(id)","transcript_path":"\(project.path)/\(id).jsonl",\
        "cwd":"/Users/you/seed","hook_event_name":"\(event)"\(extra)}
        """
    }

    private func row(_ id: String) -> [String: Any]? {
        guard let text = try? String(contentsOf: rows.appendingPathComponent("\(id).jsonl"),
                                     encoding: .utf8),
              let last = text.split(separator: "\n").last else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any]
    }

    /// The old session as the panel knew it, and its transcript ending the way
    /// a real one did — the last line copied from the measured session.
    private func backgroundTheOldSession() throws {
        let line = """
        {"schema":1,"source":"claude","session_id":"\(old)","name":"seed",\
        "tty":"/dev/ttys009","host_app":"/System/Applications/Utilities/Terminal.app",\
        "host_id":"com.apple.Terminal","event":"PreToolUse","state":"working",\
        "message":"Working… (SubagentHandback)","ts":1790479266}
        """
        try (line + "\n").write(
            to: rows.appendingPathComponent("\(old).jsonl"), atomically: true, encoding: .utf8)
        try "{}\n".write(
            to: rows.appendingPathComponent("agents/\(old)__a1.jsonl"), atomically: true, encoding: .utf8)
        let transcript = """
        {"type":"system","content":"Backgrounding after the current tool finishes…","sessionId":"\(old)"}
        {"type":"continued-in","timestamp":"2026-09-27T03:21:57.619Z","sessionId":"\(old)",\
        "continuedInSessionId":"\(new)"}
        """
        try (transcript + "\n").write(
            to: project.appendingPathComponent("\(old).jsonl"), atomically: true, encoding: .utf8)
    }

    // MARK: - Handoff

    func testTheBackgroundedSessionTakesOverTheOldTab() throws {
        try backgroundTheOldSession()
        try emit(payload(new, "SessionStart", #","source":"startup""#), background: true)
        XCTAssertEqual(row(new)?["tty"] as? String, "/dev/ttys009")
        XCTAssertEqual(row(new)?["host_id"] as? String, "com.apple.Terminal")
        XCTAssertEqual(row(new)?["name"] as? String, "seed")
    }

    func testTheOldRowAndItsSubagentsGo() throws {
        try backgroundTheOldSession()
        try emit(payload(new, "SessionStart"), background: true)
        XCTAssertNil(row(old))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: rows.appendingPathComponent("agents/\(old)__a1.jsonl").path))
    }

    /// The tab stays latched past the first line; the daemon's own pty, which
    /// every later hook resolves to, matches no tab anyone can click to.
    func testTheTabSurvivesLaterEvents() throws {
        try backgroundTheOldSession()
        try emit(payload(new, "SessionStart"), background: true)
        try emit(payload(new, "PreToolUse", #","tool_name":"Bash""#), background: true)
        XCTAssertEqual(row(new)?["tty"] as? String, "/dev/ttys009")
    }

    /// A transcript that ended in `continued-in` long ago belongs to some
    /// earlier handoff; only a fresh one can be this session's.
    func testAStaleHandoffIsNotFollowed() throws {
        try backgroundTheOldSession()
        let hourAgo = Date().addingTimeInterval(-3600)
        try FileManager.default.setAttributes(
            [.modificationDate: hourAgo], ofItemAtPath: project.appendingPathComponent("\(old).jsonl").path)
        try emit(payload(new, "SessionStart"), background: true)
        XCTAssertNotNil(row(old))
        XCTAssertNil(row(new))
    }

    // MARK: - Spares

    func testABackgroundSessionThatHasDoneNothingHasNoRow() throws {
        try emit(payload(new, "SessionStart"), background: true)
        XCTAssertNil(row(new))
    }

    func testItAppearsOnceItWorks() throws {
        try emit(payload(new, "SessionStart"), background: true)
        try emit(payload(new, "PreToolUse", #","tool_name":"Bash""#), background: true)
        XCTAssertEqual(row(new)?["state"] as? String, "working")
    }

    /// Its own ancestry leads to the daemon's pty and no app, neither of which
    /// is somewhere a click can land — so it records neither.
    func testABackgroundRowWithNoHandoffRecordsNoTab() throws {
        try emit(payload(new, "UserPromptSubmit", #","prompt":"ls""#), background: true)
        XCTAssertTrue(row(new)?["tty"] is NSNull)
        XCTAssertTrue(row(new)?["host_app"] is NSNull)
    }

    /// The app reads the flag to ignore the click instead of opening Finder.
    func testTheAppSeesTheRowAsBackground() throws {
        try emit(payload(new, "UserPromptSubmit", #","prompt":"ls""#), background: true)
        let text = try String(contentsOf: rows.appendingPathComponent("\(new).jsonl"), encoding: .utf8)
        let line = try XCTUnwrap(text.split(separator: "\n").last)
        XCTAssertTrue(try JSONDecoder().decode(SessionEvent.self, from: Data(line.utf8)).isBackground)
    }

    func testAForegroundRowIsNotBackground() throws {
        try emit(payload(new, "UserPromptSubmit", #","prompt":"ls""#), background: false)
        XCTAssertEqual(row(new)?["background"] as? Bool, false)
    }

    func testAnOrdinarySessionStillAppearsOnStart() throws {
        try emit(payload(new, "SessionStart"), background: false)
        XCTAssertEqual(row(new)?["message"] as? String, "Session started")
    }

    // MARK: - Injected prompts

    func testATaskNotificationIsNotShownAsAPrompt() throws {
        let prompt = #","prompt":"<task-notification>\n<task-id>a802c0b3c6cde21cb</task-id>""#
        try emit(payload(new, "UserPromptSubmit", prompt), background: false)
        XCTAssertEqual(row(new)?["message"] as? String, "Working…")
    }

    func testAnAgentMessageIsNotShownAsAPrompt() throws {
        let prompt = #","prompt":"<agent-message from=\"a3c9502ecfab0dcde\">\nDone.""#
        try emit(payload(new, "UserPromptSubmit", prompt), background: false)
        XCTAssertEqual(row(new)?["message"] as? String, "Working…")
    }

    func testACrossSessionMessageIsNotShownAsAPrompt() throws {
        let prompt = #","prompt":"<cross-session-message from=\"uds:/tmp/cc-socks/45035.sock\">""#
        try emit(payload(new, "UserPromptSubmit", prompt), background: false)
        XCTAssertEqual(row(new)?["message"] as? String, "Working…")
    }

    func testATypedPromptStillIs() throws {
        try emit(payload(new, "UserPromptSubmit", #","prompt":"go with recommendation""#),
                 background: false)
        XCTAssertEqual(row(new)?["message"] as? String, "go with recommendation")
    }
}
