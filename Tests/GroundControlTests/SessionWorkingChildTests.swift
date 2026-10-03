// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// A subagent's tool calls go to its own file, so while only a child is busy
/// the parent's line stops updating. The parent row read "done" — or "idle"
/// after half an hour — over a child that was visibly working.
final class SessionWorkingChildTests: XCTestCase {
    private func parent(
        _ state: String,
        source: String = "claude",
        ageMinutes: Double = 1,
        children: [AgentRow]
    ) throws -> Session {
        let ts = Int(Date().timeIntervalSince1970 - ageMinutes * 60)
        let needs = state == "needsInput"
        let json = """
        {"session_id":"abc","source":"\(source)","state":"\(state)","message":"hi",\
        "needs_action":\(needs),"ts":\(ts)}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        return Session(id: "abc", latest: event, children: children, acknowledgedAt: nil)
    }

    private func child(_ state: SessionState, ageMinutes: Double = 0) -> AgentRow {
        AgentRow(
            id: "a1",
            displayName: "agent",
            message: "m",
            state: state,
            needsAction: false,
            source: "claude",
            lastActivity: Date().addingTimeInterval(-ageMinutes * 60)
        )
    }

    func testAFinishedParentWithAWorkingChildReadsAsWorking() throws {
        XCTAssertEqual(try parent("done", children: [child(.working)]).state, .working)
    }

    /// The reported case: a long child, a parent that has heard nothing for
    /// longer than the stale window.
    func testAParentQuietForHoursStillWorksWhileAChildDoes() throws {
        let subject = try parent("working", ageMinutes: 90, children: [child(.working, ageMinutes: 1)])
        XCTAssertEqual(subject.state, .working)
    }

    func testFinishedChildrenChangeNothing() throws {
        XCTAssertEqual(try parent("done", children: [child(.done)]).state, .done)
    }

    /// Without this, one crashed subagent would hold its parent on "working"
    /// for ever — the lie the stale rule exists to stop.
    func testAChildLeftOnWorkingForHoursDoesNotCount() throws {
        let subject = try parent("done", ageMinutes: 90, children: [child(.working, ageMinutes: 90)])
        XCTAssertEqual(subject.state, .idle)
    }

    /// An alarm is the one state a child must never paint over.
    func testAnAlarmOutranksAWorkingChild() throws {
        XCTAssertEqual(try parent("needsInput", children: [child(.working)]).state, .needsInput)
    }

    /// Its group is a count of bots, not one conversation, and behaved before.
    func testGrokBotKeepsItsOwnState() throws {
        let subject = try parent("done", source: "grokbot", children: [child(.working)])
        XCTAssertEqual(subject.state, .done)
    }
}
