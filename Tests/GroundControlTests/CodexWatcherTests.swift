// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

final class CodexWatcherTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-11T22:00:00Z")!
    private var root: URL!
    private var sessionsRoot: URL!
    private var indexURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexWatcher-\(UUID().uuidString)")
        sessionsRoot = root.appendingPathComponent("sessions", isDirectory: true)
        indexURL = root.appendingPathComponent("session_index.jsonl")
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeIndex(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: indexURL, atomically: true, encoding: .utf8)
    }

    /// Writes a minimal rollout transcript: a `session_meta` first line, then
    /// optionally a `task_complete` last line.
    private func writeRollout(id: String, cwd: String, completed: String? = nil) throws {
        let dir = sessionsRoot.appendingPathComponent("2026/09/11", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines = [
            #"{"type":"session_meta","payload":{"session_id":"\#(id)","cwd":"\#(cwd)"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        ]
        if let completed {
            lines.append(#"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"\#(completed)"}}"#)
        }
        let text = lines.joined(separator: "\n") + "\n"
        try text.write(to: dir.appendingPathComponent("rollout-2026-09-11T14-00-00-\(id).jsonl"), atomically: true, encoding: .utf8)
    }

    // MARK: - Shape

    func testNoIndexMeansNoSessions() {
        XCTAssertTrue(CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now).isEmpty)
    }

    func testAThreadWithNoRolloutFileIsSkipped() throws {
        try writeIndex([#"{"id":"missing","thread_name":"Ghost","updated_at":"2026-09-11T21:55:00.000000Z"}"#])
        XCTAssertTrue(CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now).isEmpty)
    }

    func testAWorkingThreadReadsCwdAndDefaultsToWorking() throws {
        try writeRollout(id: "t1", cwd: "/Users/you/repo")
        try writeIndex([#"{"id":"t1","thread_name":"List files here","updated_at":"2026-09-11T21:55:00.000000Z"}"#])

        let sessions = CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.id, "t1")
        XCTAssertEqual(session.cwd, "/Users/you/repo")
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.displayName(renames: [:]), "List files here")
        XCTAssertEqual(session.source, "codex")
        XCTAssertTrue(session.children.isEmpty)
    }

    func testACompletedThreadReadsTheRealFinalMessage() throws {
        try writeRollout(id: "t2", cwd: "/Users/you/repo", completed: "This directory is empty.")
        try writeIndex([#"{"id":"t2","thread_name":"List files here","updated_at":"2026-09-11T21:55:00.000000Z"}"#])

        let session = try XCTUnwrap(CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now).first)
        XCTAssertEqual(session.state, .done)
        XCTAssertEqual(session.message, "This directory is empty.")
    }

    /// The load-bearing limit: a frozen file (mid-approval-prompt, nothing
    /// new written) must never be misread as done just because it is quiet.
    func testAFrozenTranscriptStaysWorkingNeverGuessedDone() throws {
        try writeRollout(id: "t3", cwd: "/Users/you/repo") // no task_complete appended
        try writeIndex([#"{"id":"t3","thread_name":"Needs approval","updated_at":"2026-09-11T21:55:00.000000Z"}"#])

        let session = try XCTUnwrap(CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now).first)
        XCTAssertEqual(session.state, .working)
        XCTAssertFalse(session.needsAction, "Codex rows never alarm — there is no signal to alarm from")
    }

    func testMultipleThreadsEachBecomeTheirOwnRowNotGrouped() throws {
        try writeRollout(id: "a", cwd: "/Users/you/repo-a")
        try writeRollout(id: "b", cwd: "/Users/you/repo-b")
        try writeIndex([
            #"{"id":"a","thread_name":"A","updated_at":"2026-09-11T21:55:00.000000Z"}"#,
            #"{"id":"b","thread_name":"B","updated_at":"2026-09-11T21:56:00.000000Z"}"#,
        ])
        let sessions = CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now)
        XCTAssertEqual(Set(sessions.map(\.id)), ["a", "b"])
        XCTAssertTrue(sessions.allSatisfy { $0.children.isEmpty })
    }

    // MARK: - History cutoff

    func testAThreadOlderThanTheRelevanceWindowIsDropped() throws {
        try writeRollout(id: "old", cwd: "/Users/you/repo")
        let longAgo = now.addingTimeInterval(-CodexWatcher.relevanceWindow - 1)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        try writeIndex([#"{"id":"old","thread_name":"Old","updated_at":"\#(iso.string(from: longAgo))"}"#])

        XCTAssertTrue(CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now).isEmpty)
    }

    // MARK: - Malformed data

    func testAMalformedIndexLineIsSkippedNotCrashed() throws {
        try writeRollout(id: "ok", cwd: "/Users/you/repo")
        try writeIndex([
            "not json at all",
            #"{"id":"ok","thread_name":"Fine","updated_at":"2026-09-11T21:55:00.000000Z"}"#,
        ])
        let sessions = CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now)
        XCTAssertEqual(sessions.map(\.id), ["ok"])
    }

    func testAMissingSessionMetaLineSkipsTheThread() throws {
        let dir = sessionsRoot.appendingPathComponent("2026/09/11", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"type":"event_msg","payload":{"type":"task_started"}}"#
            .write(to: dir.appendingPathComponent("rollout-2026-09-11T14-00-00-noheader.jsonl"),
                   atomically: true, encoding: .utf8)
        try writeIndex([#"{"id":"noheader","thread_name":"No header","updated_at":"2026-09-11T21:55:00.000000Z"}"#])
        XCTAssertTrue(CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now).isEmpty)
    }
}
