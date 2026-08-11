// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

final class AgentGrouperTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentGrouperTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeAgent(session: String, agent: String, type: String, ts: Int = 1) throws {
        let json = #"{"session_id":"\#(session)","agent_id":"\#(agent)","agent_type":"\#(type)","#
            + #""state":"done","message":"m","needs_action":false,"ts":\#(ts)}"#
        try json.write(
            to: directory.appendingPathComponent("\(session)__\(agent).jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Claude Code's own agents report no type and carry text that was never
    /// part of the conversation, so they must not become rows.
    func testInternalAgentsAreHiddenByDefault() throws {
        try writeAgent(session: "s1", agent: "real", type: "Explore")
        try writeAgent(session: "s1", agent: "internal", type: "")

        let children = AgentGrouper.childrenBySession(in: directory)
        XCTAssertEqual(children["s1"]?.map(\.id), ["real"])
    }

    func testInternalAgentsCanBeShownDeliberately() throws {
        try writeAgent(session: "s1", agent: "real", type: "Explore")
        try writeAgent(session: "s1", agent: "internal", type: "")

        let children = AgentGrouper.childrenBySession(in: directory, includingInternal: true)
        XCTAssertEqual(children["s1"]?.count, 2)
    }

    func testWhitespaceOnlyTypeCountsAsInternal() throws {
        try writeAgent(session: "s1", agent: "blank", type: "   ")
        XCTAssertNil(AgentGrouper.childrenBySession(in: directory)["s1"])
    }

    func testGroupsBySessionAndSortsNewestFirst() throws {
        try writeAgent(session: "s1", agent: "old", type: "Explore", ts: 10)
        try writeAgent(session: "s1", agent: "new", type: "Explore", ts: 20)
        try writeAgent(session: "s2", agent: "other", type: "Plan", ts: 5)

        let children = AgentGrouper.childrenBySession(in: directory)
        XCTAssertEqual(children["s1"]?.map(\.id), ["new", "old"])
        XCTAssertEqual(children["s2"]?.map(\.id), ["other"])
    }

    func testMissingDirectoryYieldsNoChildren() {
        let absent = directory.appendingPathComponent("nope")
        XCTAssertTrue(AgentGrouper.childrenBySession(in: absent).isEmpty)
    }
}
