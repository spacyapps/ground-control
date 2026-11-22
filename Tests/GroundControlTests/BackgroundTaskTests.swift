// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// A session whose turn has ended can still have work running: a shell or a
/// subagent started with `run_in_background`. Claude Code lists them on every
/// `Stop` as `background_tasks` (measured on 2.1.330, docs/HOOK-PAYLOADS.md),
/// and the row says so instead of reading as plain "done".
///
/// Runs the real script, for the reason `EmitterDialectTests` does.
final class BackgroundTaskTests: XCTestCase {
    private var home = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bgtasks-\(UUID().uuidString)")
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
        home.appendingPathComponent("groundcontrol/bg1.jsonl")
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

    private func lastEvent() throws -> SessionEvent {
        let text = try String(contentsOf: sessionFile, encoding: .utf8)
        let last = try XCTUnwrap(text.split(separator: "\n").last)
        return try JSONDecoder().decode(SessionEvent.self, from: Data(last.utf8))
    }

    private let prompt = """
    {"session_id":"bg1","hook_event_name":"UserPromptSubmit","prompt":"bake it","cwd":"/tmp/demo"}
    """

    /// The shape measured live: a shell entry carries `command`, a subagent
    /// entry `agent_type`, and both a `status`.
    private func stop(_ tasks: String) -> String {
        """
        {"session_id":"bg1","hook_event_name":"Stop","last_assistant_message":"Started the bake.",\
        "cwd":"/tmp/demo","background_tasks":\(tasks)}
        """
    }

    private let bake = """
    {"id":"b1","type":"shell","status":"running","description":"Rebuild Vharn model in Blender",\
    "command":"npm run build:assets vharn"}
    """

    // MARK: - The emitter

    func testAStopRecordsItsRunningShell() throws {
        try emit(prompt)
        try emit(stop("[\(bake)]"))
        let event = try lastEvent()
        XCTAssertEqual(event.state, .done)
        let expected = SessionEvent.BackgroundTask(
            type: "shell", description: "Rebuild Vharn model in Blender", id: "b1"
        )
        XCTAssertEqual(event.backgroundTasks, [expected])
    }

    /// No other event carries the list, so without the latch the next tool
    /// call would erase a shell that is still running.
    func testTheListOutlivesTheNextEvent() throws {
        try emit(prompt)
        try emit(stop("[\(bake)]"))
        try emit("""
        {"session_id":"bg1","hook_event_name":"UserPromptSubmit","prompt":"next","cwd":"/tmp/demo"}
        """)
        XCTAssertEqual(try lastEvent().backgroundTasks.count, 1)
    }

    /// A finished task wakes the session, and that turn's Stop lists what is
    /// left — an empty list is news, not an absence.
    func testAnEmptyListClearsIt() throws {
        try emit(prompt)
        try emit(stop("[\(bake)]"))
        try emit(stop("[]"))
        XCTAssertEqual(try lastEvent().backgroundTasks, [])
    }

    func testOnlyRunningTasksAreKept() throws {
        try emit(prompt)
        try emit(stop("""
        [{"id":"b2","type":"shell","status":"completed","description":"Old build"}]
        """))
        XCTAssertEqual(try lastEvent().backgroundTasks, [])
    }

    /// Every other CLI, and Claude Code before the field existed.
    func testAStopWithoutTheFieldRecordsNothing() throws {
        try emit(prompt)
        try emit("""
        {"session_id":"bg1","hook_event_name":"Stop","last_assistant_message":"Done.","cwd":"/tmp/demo"}
        """)
        XCTAssertEqual(try lastEvent().backgroundTasks, [])
    }

    // MARK: - What the row shows

    private func event(_ tasks: [SessionEvent.BackgroundTask]) -> SessionEvent {
        SessionEvent(
            sessionID: "bg1",
            source: "claude",
            state: .done,
            message: "Started the bake.",
            backgroundTasks: tasks,
            timestamp: Date()
        )
    }

    private func session(_ tasks: [SessionEvent.BackgroundTask], children: [AgentRow] = []) -> Session {
        let latest = event(tasks)
        return Session(id: "bg1", latest: latest, children: children + AgentRow.shells(of: latest), acknowledgedAt: nil)
    }

    private func task(_ type: String, id: String? = nil) -> SessionEvent.BackgroundTask {
        .init(type: type, description: "Rebuild Vharn", id: id)
    }

    func testEachShellIsAChildRowMarkedAsOne() {
        let shells = AgentRow.shells(of: event([task("shell", id: "b1")]))
        XCTAssertEqual(shells.count, 1)
        XCTAssertEqual(shells.first?.kind, .shell)
        XCTAssertEqual(shells.first?.message, "Rebuild Vharn")
        XCTAssertEqual(shells.first?.state, .working)
        XCTAssertEqual(shells.first?.id, "bg1-bg-b1")
    }

    func testTheRowCountsShells() {
        XCTAssertEqual(session([task("shell")]).childSummary, "1 shell")
        XCTAssertEqual(session([task("shell"), task("shell")]).childSummary, "2 shells")
        XCTAssertNil(session([]).childSummary)
    }

    /// A background subagent already has a child row of its own; a second
    /// one here would report one task twice.
    func testBackgroundSubagentsAreLeftToTheirOwnRows() {
        XCTAssertTrue(AgentRow.shells(of: event([task("subagent")])).isEmpty)
    }

    /// The session itself is free for input while a shell runs: its row keeps
    /// saying so, and the shell's own row says it is busy.
    func testARunningShellLeavesItsParentDone() {
        XCTAssertEqual(session([task("shell")]).state, .done)
    }

    // MARK: - Helper agents

    private func agent(type: String) throws -> AgentEvent {
        let json = """
        {"session_id":"bg1","agent_id":"a1","agent_type":"\(type)","state":"done","message":"m","ts":1}
        """
        return try JSONDecoder().decode(AgentEvent.self, from: Data(json.utf8))
    }

    /// Claude Code's own helpers (prompt suggestions, "welcome back" recaps)
    /// report no type; real subagents always have one.
    func testAnUntypedChildIsAHelper() throws {
        XCTAssertTrue(AgentRow(id: "a1", latest: try agent(type: "")).isHelper)
        XCTAssertFalse(AgentRow(id: "a1", latest: try agent(type: "general-purpose")).isHelper)
    }

    func testHelpersAreCountedApartFromSubagents() throws {
        let helper = AgentRow(id: "h1", latest: try agent(type: ""))
        let real = AgentRow(id: "r1", latest: try agent(type: "Explore"))
        XCTAssertEqual(session([], children: [helper, real]).childSummary, "1 subagent  ·  1 helper")
        XCTAssertEqual(session([], children: [helper]).childSummary, "1 helper")
    }
}
