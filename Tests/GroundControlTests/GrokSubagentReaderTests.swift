// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

final class GrokSubagentReaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private var root = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokSubagentReader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// The call under test, at every call site — spelled once so the tests read
    /// as what they assert rather than as the same 120 columns of plumbing.
    private func children(for sessions: [Session]) -> [String: [AgentRow]] {
        GrokSubagentReader.childrenBySession(
            liveSessions: sessions,
            now: now,
            sessionsRoot: root
        )
    }

    private func session(
        _ id: String,
        source: String = "grok",
        cwd: String = "/Users/you/repo",
        state: SessionState = .working,
        message: String = "Working…",
        needsAction: Bool = false,
        at seconds: TimeInterval = 1_000_000
    ) -> Session {
        Session(
            id: id,
            latest: SessionEvent(
                sessionID: id,
                source: source,
                cwd: cwd,
                state: state,
                message: message,
                needsAction: needsAction,
                timestamp: Date(timeIntervalSince1970: seconds)
            ),
            children: [],
            acknowledgedAt: nil
        )
    }

    /// Writes `meta.json` at `<root>/<encoded cwd>/<parentID>/subagents/<childID>/meta.json`.
    private func writeMeta(
        parentID: String,
        childID: String,
        cwd: String = "/Users/you/repo",
        description: String? = "Count files",
        status: String = "completed",
        completedAt: Date? = Date(timeIntervalSince1970: 1_999_990)
    ) throws {
        let dir = GrokSubagentReader
            .subagentsDir(sessionID: parentID, cwd: cwd, sessionsRoot: root)
            .appendingPathComponent(childID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let meta = GrokSubagentMeta(
            subagentID: childID,
            parentSessionID: parentID,
            childSessionID: childID,
            subagentType: "explore",
            description: description,
            status: status,
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            completedAt: completedAt
        )
        let data = try JSONEncoder().encode(meta)
        try data.write(to: dir.appendingPathComponent("meta.json"))
    }

    // MARK: - Shape

    func testNoSubagentsFolderMeansNoChildren() {
        let sessions = [session("parent")]
        XCTAssertTrue(children(for: sessions).isEmpty)
    }

    func testOnlyGrokSessionsAreConsidered() throws {
        try writeMeta(parentID: "parent", childID: "child")
        let sessions = [session("parent", source: "claude")]
        XCTAssertTrue(children(for: sessions).isEmpty)
    }

    func testAChildFoldsUnderItsParent() throws {
        try writeMeta(parentID: "parent", childID: "child", description: "Count files by extension")
        let sessions = [session("parent")]
        let children = GrokSubagentReader.childrenBySession(liveSessions: sessions, now: now, sessionsRoot: root)
        XCTAssertEqual(children["parent"]?.map(\.displayName), ["Count files by extension"])
        XCTAssertEqual(children["parent"]?.first?.source, "grok")
    }

    func testChildrenSortNewestFirst() throws {
        try writeMeta(parentID: "parent", childID: "older", completedAt: Date(timeIntervalSince1970: 1_999_910))
        try writeMeta(parentID: "parent", childID: "newer", completedAt: Date(timeIntervalSince1970: 1_999_990))
        let children = children(for: [session("parent")])
        XCTAssertEqual(children["parent"]?.map(\.id), ["newer", "older"])
    }

    // MARK: - Live vs. retroactive

    func testAStillLiveChildUsesItsOwnRowNotMetaJSON() throws {
        // meta.json alone carries no alarm signal — while the child's own row
        // still exists, that row must be the source of state/needsAction.
        try writeMeta(parentID: "parent", childID: "child", status: "running")
        let sessions = [
            session("parent"),
            session("child", state: .needsInput, message: "Approve this?", needsAction: true)
        ]
        let children = GrokSubagentReader.childrenBySession(liveSessions: sessions, now: now, sessionsRoot: root)
        let row = try XCTUnwrap(children["parent"]?.first)
        XCTAssertEqual(row.state, .needsInput)
        XCTAssertTrue(row.needsAction)
        XCTAssertEqual(row.message, "Approve this?")
        // The label still comes from meta.json, not the live row's own name.
        XCTAssertEqual(row.displayName, "Count files")
    }

    func testACompletedChildWithNoLiveRowFallsBackToMetaJSON() throws {
        try writeMeta(
            parentID: "parent",
            childID: "child",
            status: "completed",
            completedAt: Date(timeIntervalSince1970: 1_999_000))
        let children = children(for: [session("parent")])
        let row = try XCTUnwrap(children["parent"]?.first)
        XCTAssertEqual(row.state, .done)
        XCTAssertFalse(row.needsAction)
        XCTAssertEqual(row.message, "Finished")
    }

    // MARK: - The parent's own flat row stays out of the way

    func testAChildsOwnFlatSessionIsExcludedFromItsGroup() throws {
        try writeMeta(parentID: "parent", childID: "child")
        let sessions = [session("parent"), session("child")]
        // childIDs computed from children map, as SessionAggregator does.
        let children = GrokSubagentReader.childrenBySession(liveSessions: sessions, now: now, sessionsRoot: root)
        let childIDs = Set(children.values.flatMap { $0.map(\.id) })
        XCTAssertTrue(childIDs.contains("child"))
    }

    // MARK: - History cutoff

    func testAnOldCompletedChildWithNoLiveRowIsDroppedAfterShowFinishedFor() throws {
        let longAgo = now.addingTimeInterval(-GrokSubagentReader.showFinishedFor - 1)
        try writeMeta(parentID: "parent", childID: "child", status: "completed", completedAt: longAgo)
        let children = children(for: [session("parent")])
        XCTAssertNil(children["parent"])
    }

    func testAStillLiveChildIsShownRegardlessOfAge() throws {
        let longAgo = now.addingTimeInterval(-GrokSubagentReader.showFinishedFor - 1)
        try writeMeta(parentID: "parent", childID: "child", status: "running")
        let sessions = [session("parent"), session("child", at: longAgo.timeIntervalSince1970)]
        let children = GrokSubagentReader.childrenBySession(liveSessions: sessions, now: now, sessionsRoot: root)
        XCTAssertEqual(children["parent"]?.count, 1)
    }

    // MARK: - Percent-encoding

    func testPercentEncodeEscapesSlashes() {
        XCTAssertEqual(GrokSubagentReader.percentEncode("/Users/you/repo"), "%2FUsers%2Fyou%2Frepo")
    }

    // MARK: - Malformed data

    func testAnUnreadableMetaJSONIsSkippedNotCrashed() throws {
        let dir = GrokSubagentReader
            .subagentsDir(sessionID: "parent", cwd: "/Users/you/repo", sessionsRoot: root)
            .appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not json".write(to: dir.appendingPathComponent("meta.json"), atomically: true, encoding: .utf8)
        let children = children(for: [session("parent")])
        XCTAssertNil(children["parent"])
    }
}
