// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The one place a Codex row still differs from every other row once its hooks
/// are installed: what its children are called.
final class CodexRowTests: XCTestCase {
    private func agentEvent(type: String, name: String) throws -> AgentEvent {
        let json = """
        {"schema":1,"session_id":"01a09377","agent_id":"01a09378293d","agent_type":"\(type)",\
        "agent_name":"\(name)","state":"working","message":"Working…","needs_action":false,"ts":1}
        """
        return try JSONDecoder().decode(AgentEvent.self, from: Data(json.utf8))
    }

    /// Codex reports `agent_type: "default"` for every sub-agent it spawns, so
    /// using it as the label names three siblings identically. The real name
    /// comes from the child's transcript and must win.
    func testARealNameBeatsCodexsConstantAgentType() throws {
        let row = AgentRow(id: "01a09378293d", latest: try agentEvent(type: "default", name: "hello_one"))
        XCTAssertEqual(row.displayName, "hello_one")
    }

    /// Claude's named subagents carry a meaningful `agent_type` and no name, so
    /// adding the new field must not change what they show.
    func testClaudesAgentTypeStillLabelsItsOwnSubagents() throws {
        let row = AgentRow(id: "01a09378293d", latest: try agentEvent(type: "architect", name: ""))
        XCTAssertEqual(row.displayName, "architect")
    }

    /// Both empty is Claude Code's internal agents, where the id is all there is.
    func testWithNeitherItFallsBackToTheID() throws {
        let row = AgentRow(id: "01a09378293d", latest: try agentEvent(type: "", name: ""))
        XCTAssertEqual(row.displayName, "agent 01a093")
    }
}
