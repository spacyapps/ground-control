// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// "It doesn't work" is the commonest report this project gets, and the Setup
/// section exists to answer it without a conversation. What it must never do is
/// answer it wrongly.
final class SetupStatusTests: XCTestCase {
    private func session(source: String, at seconds: Int) throws -> Session {
        let json = """
        {"session_id":"s-\(source)","source":"\(source)","name":"n","cwd":"/tmp",\
        "state":"working","needs_action":false,"ts":\(seconds)}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        return Session(id: event.sessionID, latest: event, children: [], acknowledgedAt: nil)
    }

    private func agent(_ name: String, sessions: [Session]) -> SetupStatus.Agent? {
        SetupStatus.agents(sessions: sessions).first { $0.name == name }
    }

    /// The load-bearing claim. A registration only proves a file was written;
    /// this is the line that proves the file is being run.
    func testAnArrivedEventIsAttributedToItsOwnAgent() throws {
        let sessions = [try session(source: "cursor", at: 1_000)]
        XCTAssertNotNil(agent("Cursor", sessions: sessions)?.lastEvent)
        XCTAssertNil(agent("Claude Code", sessions: sessions)?.lastEvent,
                     "one agent's traffic must never vouch for another's")
    }

    /// Grok reports as its own source but rides Claude Code's settings file, so
    /// the two share a registration and must not share a heartbeat.
    func testGrokAndClaudeAreCountedSeparately() throws {
        let sessions = [try session(source: "grok", at: 2_000)]
        XCTAssertNotNil(agent("Grok", sessions: sessions)?.lastEvent)
        XCTAssertNil(agent("Claude Code", sessions: sessions)?.lastEvent)
    }

    func testTheMostRecentEventWins() throws {
        let sessions = [try session(source: "claude", at: 10),
                        try session(source: "claude", at: 900)]
        let seen = try XCTUnwrap(agent("Claude Code", sessions: sessions)?.lastEvent)
        XCTAssertEqual(seen.timeIntervalSince1970, 900, accuracy: 1)
    }

    /// Silence is the normal state for a CLI nobody runs, and it must not read
    /// as breakage.
    func testNothingHeardIsNotAnError() {
        for agent in SetupStatus.agents(sessions: []) {
            XCTAssertNil(agent.lastEvent, "\(agent.name) invented an event")
        }
    }

    /// The two agents that cannot do everything say so, so a missing alarm
    /// reads as a known limit rather than a broken install.
    func testTheLimitedAgentsCarryTheirCaveat() {
        let agents = SetupStatus.agents(sessions: [])
        XCTAssertNotNil(agents.first { $0.name == "Cursor" }?.caveat)
        XCTAssertNotNil(agents.first { $0.name == "opencode" }?.caveat)
        XCTAssertNil(agents.first { $0.name == "Claude Code" }?.caveat,
                     "the fully supported one should claim no excuses")
    }
}
