// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The emitter's dialect handling, exercised by running the real script.
///
/// `cc-notify` is the one part of the system with no automated coverage, and it
/// is where every CLI difference lands: Grok camelCases its keys, Cursor sends
/// its own event names and leaves `cwd` empty. Both were found by probing a live
/// session, and nothing stopped a later edit from quietly undoing either.
///
/// Every payload below is a real one, captured from a running agent — the
/// Cursor lines from a Composer turn on 2026-08-14. Writing them by hand would
/// test the fixture rather than the CLI.
final class EmitterDialectTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("emitter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var emitter: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // GroundControlTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("Scripts/cc-notify")
            .path
    }

    /// Feeds one payload in and returns whatever line the app would read back.
    @discardableResult
    private func emit(_ payload: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [emitter]
        // The emitter writes under TMPDIR, so pointing it at a fresh directory
        // is what keeps these tests out of the real session folder.
        process.environment = ["TMPDIR": home.path + "/"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let folder = home.appendingPathComponent("groundcontrol")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let name = files.first(where: { $0.hasSuffix(".jsonl") }) else { return [:] }
        let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        guard let last = text.split(separator: "\n").last,
              let object = try JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any]
        else { return [:] }
        return object
    }

    // MARK: - Cursor

    private let cursorPrompt = """
    {"conversation_id":"0639bbe2","generation_id":"36431e0d","model":"composer-2.5",\
    "composer_mode":"agent","prompt":"Hello, what can you here ?","attachments":[],\
    "session_id":"0639bbe2","hook_event_name":"beforeSubmitPrompt","cursor_version":"3.15.6",\
    "workspace_roots":["/Users/waltermak/github/empty"],"transcript_path":null}
    """

    /// Cursor's own agent is a different CLI sharing Claude's field casing, so
    /// without `cursor_version` it would be filed as Claude and its rows would
    /// collide with a Claude session that happened to share an id.
    func testCursorIsRecognisedAsItsOwnSource() throws {
        XCTAssertEqual(try emit(cursorPrompt)["source"] as? String, "cursor")
    }

    /// `beforeSubmitPrompt` carries a `prompt` exactly as Claude's
    /// `UserPromptSubmit` does, so it is the same thing under another name.
    func testCursorPromptReadsAsWorking() throws {
        let line = try emit(cursorPrompt)
        XCTAssertEqual(line["state"] as? String, "working")
        XCTAssertEqual(line["message"] as? String, "Hello, what can you here ?")
    }

    /// Cursor sends `cwd` as an empty string and the real answer in
    /// `workspace_roots`. Taking `cwd` at face value would fall through to the
    /// hook's own working directory and name every Cursor row `.cursor`.
    func testCursorRowIsNamedAfterTheWorkspace() throws {
        let line = try emit(cursorPrompt)
        XCTAssertEqual(line["cwd"] as? String, "/Users/waltermak/github/empty")
        XCTAssertEqual(line["name"] as? String, "empty")
    }

    /// Three of Cursor's events already spell what we call them once case and
    /// underscores are stripped. This is the one that would break silently if
    /// that normalising were ever narrowed.
    func testCursorToolUseNeedsNoAlias() throws {
        let line = try emit("""
        {"session_id":"0639bbe2","hook_event_name":"preToolUse","cursor_version":"3.15.6",\
        "tool_name":"Shell","tool_input":{"command":"ls -la","cwd":"","timeout":30000},\
        "cwd":"","workspace_roots":["/Users/waltermak/github/empty"]}
        """)
        XCTAssertEqual(line["state"] as? String, "working")
        XCTAssertEqual(line["message"] as? String, "Shell: ls -la")
    }

    func testCursorStopFinishesTheRow() throws {
        let line = try emit("""
        {"session_id":"0639bbe2","hook_event_name":"stop","cursor_version":"3.15.6",\
        "status":"completed","workspace_roots":["/Users/waltermak/github/empty"]}
        """)
        XCTAssertEqual(line["state"] as? String, "done")
        XCTAssertEqual(line["needs_action"] as? Bool, false)
    }

    // MARK: - The dialects that already worked

    func testClaudeIsStillClaude() throws {
        let line = try emit("""
        {"session_id":"c1","hook_event_name":"UserPromptSubmit","prompt":"hello",\
        "cwd":"/Users/waltermak/github/avaterm"}
        """)
        XCTAssertEqual(line["source"] as? String, "claude")
        XCTAssertEqual(line["state"] as? String, "working")
        XCTAssertEqual(line["name"] as? String, "avaterm")
    }

    func testGrokIsStillGrok() throws {
        let line = try emit("""
        {"sessionId":"g1","hookEventName":"SessionStart","cwd":"/Users/waltermak/github/avaterm"}
        """)
        XCTAssertEqual(line["source"] as? String, "grok")
        XCTAssertEqual(line["state"] as? String, "idle")
    }
}
