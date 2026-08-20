// SPDX-License-Identifier: AGPL-3.0-or-later
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
    /// Each test gets its own TMPDIR, so nothing lands in the real session
    /// folder and the cases cannot see each other's files.
    private var home = URL(fileURLWithPath: NSTemporaryDirectory())

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
    /// hook's own working directory and put `.cursor` on every row.
    func testCursorWorkspaceComesFromWorkspaceRoots() throws {
        XCTAssertEqual(try emit(cursorPrompt)["cwd"] as? String, "/Users/waltermak/github/empty")
    }

    /// Cursor keeps several chats against one workspace, so naming rows after
    /// the folder makes them all `empty`. Its own titles live in app state we
    /// cannot reach, but the opening prompt — which is what Cursor titles them
    /// from — is right there in the payload.
    func testCursorRowIsNamedAfterItsOpeningPrompt() throws {
        XCTAssertEqual(try emit(cursorPrompt)["name"] as? String, "Hello, what can you here ?")
    }

    /// A Cursor row can be created by a tool event, before any prompt is seen.
    /// The folder alone reads as the name of one chat when it is really the
    /// container several of them share, so it says which it is.
    func testACursorRowWithNoPromptYetSaysItIsAWorkspace() throws {
        let line = try emit("""
        {"session_id":"s9","hook_event_name":"preToolUse","cursor_version":"3.15.6",\
        "tool_name":"Write","tool_input":{"file_path":"/x"},"cwd":"",\
        "workspace_roots":["/Users/waltermak/github/empty"]}
        """)
        XCTAssertEqual(line["name"] as? String, "workspace: empty")
    }

    /// And the placeholder still gives way to the first prompt — it is a label
    /// for "not named yet", not a name.
    func testTheWorkspaceLabelGivesWayToTheFirstPrompt() throws {
        try emit("""
        {"session_id":"s9","hook_event_name":"preToolUse","cursor_version":"3.15.6",\
        "tool_name":"Write","tool_input":{"file_path":"/x"},"cwd":"",\
        "workspace_roots":["/Users/waltermak/github/empty"]}
        """)
        let named = try emit("""
        {"session_id":"s9","hook_event_name":"beforeSubmitPrompt","cursor_version":"3.15.6",\
        "prompt":"do I pick composer or Grok?",\
        "workspace_roots":["/Users/waltermak/github/empty"]}
        """)
        XCTAssertEqual(named["name"] as? String, "do I pick composer or Grok?")
    }

    /// And it latches: a chat keeps the question it started from rather than
    /// renaming itself on every prompt.
    func testCursorNameDoesNotFollowTheConversation() throws {
        try emit(cursorPrompt)
        let later = try emit("""
        {"session_id":"0639bbe2","hook_event_name":"beforeSubmitPrompt","cursor_version":"3.15.6",\
        "prompt":"and now something completely different",\
        "workspace_roots":["/Users/waltermak/github/empty"]}
        """)
        XCTAssertEqual(later["name"] as? String, "Hello, what can you here ?")
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

    // MARK: - The question an agent is asking

    /// Payload shape measured from a live `AskUserQuestion`, not guessed: the
    /// text sits at `tool_input.questions[0].question`, a list of objects. The
    /// flat-key search walked past it, so every such row read
    /// "Working… (AskUserQuestion)" and told you nothing.
    private let askPayload = """
    {"session_id":"q1","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion",\
    "cwd":"/Users/waltermak/github/avaterm","tool_input":{"questions":[{\
    "question":"Commit the JournalShell.tsx fix?","header":"Commit",\
    "options":[{"label":"Approve"},{"label":"Deny"}]}]}}
    """

    func testTheQuestionBecomesTheMessage() throws {
        XCTAssertEqual(try emit(askPayload)["message"] as? String,
                       "Commit the JournalShell.tsx fix?")
    }

    /// The alarm arrives on a *different* event six seconds later, carrying
    /// only "Claude needs your permission". Last line wins, so without a latch
    /// the words are lost exactly when they matter most.
    func testTheAlarmKeepsTheQuestionRatherThanReplacingIt() throws {
        try emit(askPayload)
        let alarm = try emit("""
        {"session_id":"q1","hook_event_name":"Notification",\
        "message":"Claude needs your permission","cwd":"/Users/waltermak/github/avaterm"}
        """)
        XCTAssertEqual(alarm["state"] as? String, "needsInput")
        XCTAssertEqual(alarm["needs_action"] as? Bool, true)
        XCTAssertEqual(alarm["message"] as? String, "Commit the JournalShell.tsx fix?")
    }

    /// An alarm with no question before it must still say something. Not every
    /// notification comes from a question the agent asked.
    func testAnAlarmWithNoQuestionFallsBackToWhatItWasGiven() throws {
        let alarm = try emit("""
        {"session_id":"q2","hook_event_name":"Notification",\
        "message":"Claude needs your permission","cwd":"/tmp/x"}
        """)
        XCTAssertEqual(alarm["message"] as? String, "Claude needs your permission")
    }

    /// Every other tool keeps the phrasing it had — the question is an addition
    /// to the search, not a replacement for it.
    func testOtherToolsAreUnchanged() throws {
        let line = try emit("""
        {"session_id":"q3","hook_event_name":"PreToolUse","tool_name":"Bash",\
        "tool_input":{"description":"Run the tests"},"cwd":"/tmp/x"}
        """)
        XCTAssertEqual(line["message"] as? String, "Bash: Run the tests")
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

    // MARK: - Notifications alarm by default

    /// Captured from a live Grok session on 2026-08-19, in `normal` mode.
    ///
    /// `elicitation_dialog` appears nowhere in Grok's documentation, which lists
    /// `idle_prompt`, `permission_prompt` and `task_complete`. It reached the
    /// app anyway, red and carrying the real question, because `interpret()`
    /// alarms on everything it is not told to skip.
    func testAnUndocumentedNotificationTypeStillAlarms() throws {
        let line = try emit("""
        {"sessionId":"g2","hookEventName":"notification","notificationType":"elicitation_dialog",\
        "message":"Approve input (test) — enter 1, 2, or 3.",\
        "cwd":"/Users/waltermak/github/avaterm"}
        """)
        XCTAssertEqual(line["state"] as? String, "needsInput")
        XCTAssertEqual(line["needs_action"] as? Bool, true)
        XCTAssertEqual(
            line["message"] as? String,
            "Approve input (test) — enter 1, 2, or 3.",
            "the row should carry the question, not a generic phrase"
        )
    }

    /// Answering a question emits nothing — not a `Stop`, not a second
    /// notification, not a prompt. Without this event the row stays red from the
    /// question until the agent's next tool call: 147 seconds on the session that
    /// found it, spent entirely on thinking.
    ///
    /// Registered with a matcher for the question tools alone, so in practice
    /// this event *is* "the question was answered".
    func testAnsweringAQuestionClearsTheAlarm() throws {
        try emit("""
        {"sessionId":"g4","hookEventName":"notification","notificationType":"elicitation_dialog",\
        "message":"Overlay or background?","cwd":"/Users/waltermak/github/avaterm"}
        """)
        let cleared = try emit("""
        {"sessionId":"g4","hookEventName":"PostToolUse","toolName":"ask_user_question",\
        "cwd":"/Users/waltermak/github/avaterm"}
        """)
        XCTAssertEqual(cleared["state"] as? String, "working")
        XCTAssertEqual(cleared["needs_action"] as? Bool, false, "the alarm must not outlive the answer")
        XCTAssertEqual(cleared["message"] as? String, "Working…", "the answered question is stale text")
    }

    /// The one exception, and the reason the rule is worth stating: `idle_prompt`
    /// means the turn ended, which `Stop` already reports with better wording.
    /// Alarming on it turned every finished session red.
    ///
    /// These two tests are a pair. Inverting the emitter to a whitelist of known
    /// types keeps this one passing and silently breaks the one above — which is
    /// exactly how an undocumented type would be lost.
    func testIdlePromptIsTheOnlyTypeSkipped() throws {
        let line = try emit("""
        {"sessionId":"g3","hookEventName":"notification","notificationType":"idle_prompt",\
        "message":"Grok is waiting for your input","cwd":"/Users/waltermak/github/avaterm"}
        """)
        XCTAssertTrue(line.isEmpty, "an idle_prompt should write no line at all")
    }
}
