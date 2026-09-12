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
    /// optionally a `task_complete` last line. `lastLineTimestamp`, when
    /// given, is stamped on the very last line — real rollout lines all
    /// carry a top-level `timestamp`, which is what `CodexWatcher` now reads
    /// for `lastActivity` instead of the index's own unreliable `updated_at`.
    private func writeRollout(
        id: String, cwd: String, completed: String? = nil, lastLineTimestamp: String? = nil
    ) throws {
        let dir = sessionsRoot.appendingPathComponent("2026/09/11", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines = [
            #"{"type":"session_meta","payload":{"session_id":"\#(id)","cwd":"\#(cwd)"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        ]
        if let completed {
            lines.append(#"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"\#(completed)"}}"#)
        }
        if let lastLineTimestamp {
            let last = lines.removeLast()
            let withTimestamp = last.replacingOccurrences(of: "{", with: #"{"timestamp":"\#(lastLineTimestamp)","#, options: [], range: last.range(of: "{"))
            lines.append(withTimestamp)
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
        XCTAssertEqual(session.latest.state, .working)
        XCTAssertEqual(session.displayName(renames: [:]), "List files here")
        XCTAssertEqual(session.source, "codex")
        XCTAssertTrue(session.children.isEmpty)
    }

    func testACompletedThreadReadsTheRealFinalMessage() throws {
        try writeRollout(id: "t2", cwd: "/Users/you/repo", completed: "This directory is empty.")
        try writeIndex([#"{"id":"t2","thread_name":"List files here","updated_at":"2026-09-11T21:55:00.000000Z"}"#])

        let session = try XCTUnwrap(CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now).first)
        XCTAssertEqual(session.latest.state, .done)
        XCTAssertEqual(session.message, "This directory is empty.")
    }

    /// Caught live 2026-09-11: `session_index.jsonl`'s `updated_at` sat
    /// frozen through an entire long turn (and a second one after it) while
    /// the transcript kept growing — 25+ minutes of real activity the index
    /// never reflected. Trusting it for `lastActivity` would age a
    /// genuinely-working row past the 30-minute staleness window into
    /// looking idle. The transcript's own last-line timestamp must win.
    func testLastActivityComesFromTheTranscriptNotTheStaleIndex() throws {
        try writeRollout(id: "t5", cwd: "/Users/you/repo", lastLineTimestamp: "2026-09-11T21:59:00.000000Z")
        // The index claims this thread went quiet an hour before `now` —
        // well past the 30-minute staleness window on its own, exactly what
        // was observed live for a thread that was genuinely still working.
        try writeIndex([#"{"id":"t5","thread_name":"Long turn","updated_at":"2026-09-11T21:00:00.000000Z"}"#])

        let session = try XCTUnwrap(CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now).first)
        XCTAssertEqual(session.lastActivity, ISO8601DateFormatter().date(from: "2026-09-11T21:59:00Z"))
        XCTAssertFalse(
            ElapsedFormatter.isStale(since: session.lastActivity, now: now),
            "the transcript's own fresher timestamp must win over the index's stale one"
        )
    }

    /// Caught live: a real `last_agent_message` was a numbered list and
    /// rendered as several stacked lines in the panel — the only row in the
    /// app that did not collapse to one, until this was fixed.
    func testAMultilineMarkdownMessageCollapsesToOneCleanLine() throws {
        let raw = #"Select the **1st**, **2nd**, or **3rd** item:\n1. ember\n2. meadow\n3. quartz"#
        try writeRollout(id: "t4", cwd: "/Users/you/repo", completed: raw)
        try writeIndex([#"{"id":"t4","thread_name":"Pick one","updated_at":"2026-09-11T21:55:00.000000Z"}"#])

        let session = try XCTUnwrap(CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now).first)
        XCTAssertEqual(session.message, "Select the 1st, 2nd, or 3rd item:")
        XCTAssertFalse(session.message.contains("\n"))
    }

    /// The load-bearing limit: a frozen file (mid-approval-prompt, nothing
    /// new written) must never be misread as done just because it is quiet.
    func testAFrozenTranscriptStaysWorkingNeverGuessedDone() throws {
        try writeRollout(id: "t3", cwd: "/Users/you/repo") // no task_complete appended
        try writeIndex([#"{"id":"t3","thread_name":"Needs approval","updated_at":"2026-09-11T21:55:00.000000Z"}"#])

        let session = try XCTUnwrap(CodexWatcher.sessions(fromIndexAt: indexURL, sessionsRoot: sessionsRoot, now: now).first)
        XCTAssertEqual(session.latest.state, .working)
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
