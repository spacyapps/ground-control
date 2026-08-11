// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The store owns the file ⇔ row invariant, which is the whole app.
final class SessionStoreTests: XCTestCase {
    private var root = FileManager.default.temporaryDirectory
    private var agents = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)")
        agents = root.appendingPathComponent("agents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func store() -> SessionStore {
        SessionStore(root: root, agentsRoot: agents)
    }

    private func write(session id: String, state: String = "done", needsAction: Bool = false) throws {
        let stamp = Int(Date().timeIntervalSince1970)
        let json = #"{"session_id":"\#(id)","name":"\#(id)","cwd":"/tmp/\#(id)","#
            + #""state":"\#(state)","message":"m","needs_action":\#(needsAction),"ts":\#(stamp)}"#
        try json.write(
            to: root.appendingPathComponent("\(id).jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeChild(session: String, agent: String) throws {
        let stamp = Int(Date().timeIntervalSince1970)
        let json = #"{"session_id":"\#(session)","agent_id":"\#(agent)","agent_type":"Explore","#
            + #""state":"working","message":"m","needs_action":false,"ts":\#(stamp)}"#
        try json.write(
            to: agents.appendingPathComponent("\(session)__\(agent).jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - file ⇔ row

    func testEveryFileBecomesARow() throws {
        try write(session: "a")
        try write(session: "b")

        let store = store()
        store.reload()
        XCTAssertEqual(Set(store.sessions.map(\.id)), ["a", "b"])
    }

    func testARemovedFileTakesItsRowWithIt() throws {
        try write(session: "a")
        let store = store()
        store.reload()
        XCTAssertEqual(store.sessions.count, 1)

        try FileManager.default.removeItem(at: root.appendingPathComponent("a.jsonl"))
        store.reload()
        XCTAssertTrue(store.sessions.isEmpty)
    }

    /// A file being written while we read it must not blank a row.
    func testUnreadableFilesAreSkippedRatherThanCrashing() throws {
        try write(session: "good")
        try "{ this is not json".write(
            to: root.appendingPathComponent("broken.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let store = store()
        store.reload()
        XCTAssertEqual(store.sessions.map(\.id), ["good"])
    }

    // MARK: - Removal

    func testRemoveDeletesTheSessionAndItsChildren() throws {
        try write(session: "a")
        try writeChild(session: "a", agent: "x")
        try write(session: "b")
        try writeChild(session: "b", agent: "y")

        let store = store()
        store.reload()
        store.remove(sessionID: "a")

        XCTAssertEqual(store.sessions.map(\.id), ["b"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: agents.appendingPathComponent("a__x.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agents.appendingPathComponent("b__y.jsonl").path))
    }

    // MARK: - Acknowledgement

    func testAcknowledgingClearsTheDot() throws {
        try write(session: "a", state: "needsInput", needsAction: true)
        let store = store()
        store.reload()
        XCTAssertTrue(store.sessions[0].needsAction)

        store.acknowledge(sessionID: "a")
        XCTAssertFalse(store.sessions[0].needsAction)
    }

    /// Acknowledgement must not outlive the session it silenced, or a brand new
    /// session reusing the id would start out muted.
    func testAcknowledgementIsForgottenWhenTheSessionGoes() throws {
        try write(session: "a", state: "needsInput", needsAction: true)
        let store = store()
        store.reload()
        store.acknowledge(sessionID: "a")

        try FileManager.default.removeItem(at: root.appendingPathComponent("a.jsonl"))
        store.reload()
        try write(session: "a", state: "needsInput", needsAction: true)
        store.reload()

        XCTAssertTrue(store.sessions[0].needsAction, "a returning session is not still dismissed")
    }

    // MARK: - Ordering

    func testNeedsActionIsPinnedAboveEverythingElse() throws {
        try write(session: "quiet")
        try write(session: "needy", state: "needsInput", needsAction: true)

        let store = store()
        store.reload()
        XCTAssertEqual(store.sessions.first?.id, "needy")
    }
}
