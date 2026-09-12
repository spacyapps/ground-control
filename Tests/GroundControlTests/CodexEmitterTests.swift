// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Codex's dialect, exercised by running the real `cc-notify`.
///
/// Every payload here is verbatim from `Scripts/probe-codex-hooks.sh` against
/// a live `codex` 0.154.0 on 2026-09-11 — ids shortened, nothing else changed.
/// Writing them by hand would test the fixture rather than the CLI, which is
/// the mistake `docs/LIMITATIONS.md` records twice.
final class CodexEmitterTests: XCTestCase {
    private var home = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-emitter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var emitter: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/cc-notify")
            .path
    }

    private var sessionsFolder: URL { home.appendingPathComponent("groundcontrol") }

    private func run(_ payload: String) throws {
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

    private func lastLine(of file: URL) throws -> [String: Any] {
        let text = try String(contentsOf: file, encoding: .utf8)
        guard let last = text.split(separator: "\n").last,
              let object = try JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any]
        else { return [:] }
        return object
    }

    @discardableResult
    private func emit(_ payload: String) throws -> [String: Any] {
        try run(payload)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: sessionsFolder.path)) ?? []
        guard let name = files.first(where: { $0.hasSuffix(".jsonl") }) else { return [:] }
        return try lastLine(of: sessionsFolder.appendingPathComponent(name))
    }

    private func emitAgent(_ payload: String, matching fragment: String) throws -> [String: Any] {
        try run(payload)
        let agents = sessionsFolder.appendingPathComponent("agents")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: agents.path)) ?? []
        guard let name = files.first(where: { $0.contains(fragment) }) else { return [:] }
        return try lastLine(of: agents.appendingPathComponent(name))
    }

    // MARK: - Telling Codex apart

    private let sessionStart = """
    {"session_id":"01a09377","transcript_path":"/Users/you/.codex/sessions/2026/09/11/rollout-x.jsonl",\
    "cwd":"/Users/you/github/empty2","hook_event_name":"SessionStart","model":"gpt-5.6-terra",\
    "permission_mode":"default","source":"startup"}
    """

    /// Codex sends snake_case and the same `hook_event_name` key Claude does,
    /// so without a tell of its own every Codex row would be filed as Claude —
    /// and rows from two CLIs sharing an id would collide.
    func testCodexIsRecognisedByItsTranscriptPath() throws {
        XCTAssertEqual(try emit(sessionStart)["source"] as? String, "codex")
    }

    /// The second tell, for a payload whose transcript path is absent.
    func testTurnIDAlsoIdentifiesCodex() throws {
        let noTranscript = """
        {"session_id":"01a09377","turn_id":"01a09378","cwd":"/Users/you/github/empty2",\
        "hook_event_name":"Stop","last_assistant_message":"done"}
        """
        XCTAssertEqual(try emit(noTranscript)["source"] as? String, "codex")
    }

    /// And a real Claude payload must not start reading as Codex.
    func testClaudeIsStillClaude() throws {
        let claude = """
        {"session_id":"0ff3699a","transcript_path":"/Users/you/.claude/projects/slug/0ff3699a.jsonl",\
        "cwd":"/Users/you/github/ground-control","hook_event_name":"Stop","permission_mode":"auto",\
        "last_assistant_message":"Done."}
        """
        XCTAssertEqual(try emit(claude)["source"] as? String, "claude")
    }

    // MARK: - The alarm

    /// The point of the whole Codex hook path. Codex writes nothing to any file
    /// while it waits on an approval — measured at 80 seconds — so a row only
    /// turns red if this event does it.
    func testAPermissionRequestTurnsTheRowRedInCodexsOwnWords() throws {
        let request = """
        {"session_id":"01a09377","turn_id":"01a09378",\
        "transcript_path":"/Users/you/.codex/sessions/2026/09/11/rollout-x.jsonl",\
        "cwd":"/Users/you/github/empty2","hook_event_name":"PermissionRequest",\
        "model":"gpt-5.6-terra","permission_mode":"default","tool_name":"Bash",\
        "tool_input":{"command":"curl -I -L --max-time 20 https://www.macrumors.com",\
        "description":"May I enable network access to fetch headers from www.macrumors.com?"}}
        """
        let line = try emit(request)
        XCTAssertEqual(line["state"] as? String, "needsInput")
        XCTAssertEqual(line["needs_action"] as? Bool, true)
        XCTAssertEqual(
            line["message"] as? String,
            "May I enable network access to fetch headers from www.macrumors.com?"
        )
    }

    /// The gate can fire on a call that carried no description. The command is
    /// still a better row than "Needs your input".
    func testAPermissionRequestWithNoDescriptionShowsTheCommand() throws {
        let bare = """
        {"session_id":"01a09377","turn_id":"01a09378",\
        "transcript_path":"/Users/you/.codex/sessions/rollout-x.jsonl",\
        "cwd":"/Users/you/github/empty2","hook_event_name":"PermissionRequest",\
        "tool_name":"Bash","tool_input":{"command":"rm -rf build"}}
        """
        XCTAssertEqual(try emit(bare)["message"] as? String, "rm -rf build")
    }

    /// `PostToolUse` fires once the approval is answered, carrying the same
    /// `tool_use_id`. Grok has no such event, and an alarm there once outlived
    /// its answer by 147 seconds.
    func testAnsweringTheRequestClearsTheAlarm() throws {
        try emit("""
        {"session_id":"01a09377","turn_id":"01a09378",\
        "transcript_path":"/Users/you/.codex/sessions/rollout-x.jsonl",\
        "cwd":"/Users/you/github/empty2","hook_event_name":"PermissionRequest",\
        "tool_name":"Bash","tool_input":{"command":"curl example.com","description":"May I?"}}
        """)
        let after = try emit("""
        {"session_id":"01a09377","turn_id":"01a09378",\
        "transcript_path":"/Users/you/.codex/sessions/rollout-x.jsonl",\
        "cwd":"/Users/you/github/empty2","hook_event_name":"PostToolUse","tool_name":"Bash",\
        "tool_input":{"command":"curl example.com"},"tool_response":"HTTP/2 200"}
        """)
        XCTAssertEqual(after["state"] as? String, "working")
        XCTAssertEqual(after["needs_action"] as? Bool, false)
    }

    // MARK: - Sub-agents

    /// Codex names its sub-agents, but not in the payload — `agent_type` is the
    /// constant "default" there. The name is in the child's own transcript, so
    /// without reading it three children all render as `agent 01a093`.
    func testASubagentIsNamedFromItsOwnTranscript() throws {
        let child = try writeRollout(named: "hello_one")
        let start = """
        {"session_id":"01a09377","turn_id":"01a09378","transcript_path":"\(child.path)",\
        "cwd":"/Users/you/github/empty2","hook_event_name":"SubagentStart",\
        "agent_id":"01a09378-293d","agent_type":"default"}
        """
        let line = try emitAgent(start, matching: "01a09378-293d")
        XCTAssertEqual(line["agent_name"] as? String, "hello_one")
        XCTAssertEqual(line["state"] as? String, "working", "it starts before the work, unlike Claude's")
    }

    /// The trap. `transcript_path` is the *child's* on SubagentStart and the
    /// *parent's* on SubagentStop, where the child moves to
    /// `agent_transcript_path`. Reading the wrong one names the child after
    /// whichever sub-agent the parent's transcript happens to mention first.
    func testSubagentStopReadsTheChildNotTheParent() throws {
        let parent = try writeRollout(named: "hello_one")
        let child = try writeRollout(named: "hello_two")
        let stop = """
        {"session_id":"01a09377","turn_id":"01a09378","transcript_path":"\(parent.path)",\
        "agent_transcript_path":"\(child.path)","cwd":"/Users/you/github/empty2",\
        "hook_event_name":"SubagentStop","agent_id":"01a09378-3176","agent_type":"default",\
        "last_assistant_message":"hello"}
        """
        let line = try emitAgent(stop, matching: "01a09378-3176")
        XCTAssertEqual(line["agent_name"] as? String, "hello_two")
        XCTAssertEqual(line["state"] as? String, "done")
        XCTAssertEqual(line["message"] as? String, "hello")
    }

    /// The path arrives in a payload, so it is fenced to `~/.codex`. A hook
    /// must not be a way to make the emitter open an arbitrary file.
    func testATranscriptOutsideCodexIsNotOpened() throws {
        let elsewhere = home.appendingPathComponent("not-codex.jsonl")
        try #"{"item":{"agent_path":"/root/secret"}}"#.write(to: elsewhere, atomically: true, encoding: .utf8)
        let start = """
        {"session_id":"01a09377","turn_id":"01a09378","transcript_path":"\(elsewhere.path)",\
        "cwd":"/Users/you/github/empty2","hook_event_name":"SubagentStart",\
        "agent_id":"01a09378-aaaa","agent_type":"default"}
        """
        let line = try emitAgent(start, matching: "01a09378-aaaa")
        XCTAssertEqual(line["agent_name"] as? String, "", "outside ~/.codex it must not be read")
    }

    /// A real rollout line, in the real place — the fence is a path check, so a
    /// fixture somewhere else would only ever prove the fence.
    private func writeRollout(named name: String) throws -> URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions/gc-tests")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("rollout-\(UUID().uuidString).jsonl")
        let line = """
        {"timestamp":"2026-09-12T02:35:20.791Z","type":"event_msg","payload":{"type":"item_completed",\
        "item":{"type":"SubAgentActivity","kind":"started","agent_thread_id":"01a09378-293d",\
        "agent_path":"/root/\(name)"}}}
        """
        try line.write(to: file, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return file
    }

    // MARK: - Ending

    /// Codex says goodbye, so a row should not wait out the 24h purge — nor the
    /// by-folder guess `CodexWatcher` had to make before hooks existed.
    func testSessionEndRemovesTheRow() throws {
        try emit(sessionStart)
        let file = sessionsFolder.appendingPathComponent("01a09377.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        try run("""
        {"session_id":"01a09377","transcript_path":"/Users/you/.codex/sessions/rollout-x.jsonl",\
        "cwd":"/Users/you/github/empty2","hook_event_name":"SessionEnd","reason":"other"}
        """)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "the file ⇔ row invariant does the rest"
        )
    }
}
