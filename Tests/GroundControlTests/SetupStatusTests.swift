// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// "It doesn't work" is the commonest report this project gets, and the Hooks
/// menu exists to answer it without a conversation. What it must never do is
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

    /// The load-bearing claim. A registration only proves a file was written;
    /// this is the line that proves the file is being run.
    func testTrafficFromAnySupportedAgentCounts() throws {
        for source in ["claude", "grok", "cursor", "opencode"] {
            let seen = SetupStatus.summary(sessions: [try session(source: source, at: 500)]).lastEvent
            XCTAssertNotNil(seen, "\(source) should count as something arriving")
        }
    }

    func testTheMostRecentEventWins() throws {
        let sessions = [try session(source: "claude", at: 10),
                        try session(source: "cursor", at: 900)]
        let seen = try XCTUnwrap(SetupStatus.summary(sessions: sessions).lastEvent)
        XCTAssertEqual(seen.timeIntervalSince1970, 900, accuracy: 1)
    }

    /// Silence is the normal state for a machine nobody is running agents on,
    /// and it must not read as breakage.
    func testNothingHeardIsNotAnError() {
        XCTAssertNil(SetupStatus.summary(sessions: []).lastEvent)
    }

    /// One switch, and it speaks for everything — the per-integration switches
    /// were rows that could never be anything but off, surrounding the one row
    /// that mattered.
    func testThereIsOneSwitchAndItCoversEverything() {
        XCTAssertEqual(SetupStatus.summary(sessions: []).target, .all)
    }

    /// The facts underneath must name what is covered and what is not, since
    /// nothing else on screen says so now.
    func testTheFactsSayWhatIsCoveredAndWhatIsNot() {
        let facts = SetupStatus.facts().joined(separator: " ")
        XCTAssertTrue(facts.contains("Claude Code"), facts)
        XCTAssertTrue(facts.contains("terminal"), "the terminal case is the one people doubt")
        XCTAssertTrue(facts.contains("Not covered"), "and the limits have to be stated")
    }
}
