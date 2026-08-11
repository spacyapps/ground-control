// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import SkinTerminal

/// The analyser is decoration, but its energy is derived from real state — so
/// the mapping is worth pinning down.
final class VisualizerTests: XCTestCase {
    private func session(state: SessionState, needsAction: Bool = false) throws -> Session {
        let json = """
        {"session_id":"\(UUID().uuidString)","name":"x","cwd":"/tmp/x",\
        "state":"\(state.rawValue)","message":"","needs_action":\(needsAction),"ts":1}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        return Session(id: event.sessionID, latest: event, children: [], acknowledgedAt: nil)
    }

    func testEmptyPanelIsSilent() {
        XCTAssertEqual(VisualizerView.energy(for: []), 0)
    }

    /// Silence is flat, not a low shimmer — motion must always mean work.
    func testIdleAndFinishedSessionsAreCompletelyFlat() throws {
        XCTAssertEqual(VisualizerView.energy(for: [try session(state: .idle)]), 0)
        XCTAssertEqual(VisualizerView.energy(for: [try session(state: .done)]), 0)
        XCTAssertEqual(
            VisualizerView.energy(for: [try session(state: .idle), try session(state: .done)]),
            0
        )
    }

    /// Waiting on you is not work: it colours the bars rather than moving them.
    func testNeedsInputAloneDoesNotDriveTheBars() throws {
        let waiting = [try session(state: .needsInput, needsAction: true)]
        XCTAssertEqual(VisualizerView.energy(for: waiting), 0)
        XCTAssertTrue(VisualizerView.alarms(for: waiting))
    }

    func testWorkingWhileSomethingWaitsStillMoves() throws {
        let mixed = [
            try session(state: .working),
            try session(state: .needsInput, needsAction: true)
        ]
        XCTAssertGreaterThan(VisualizerView.energy(for: mixed), 0.4)
        XCTAssertTrue(VisualizerView.alarms(for: mixed))
    }

    func testWorkingRaisesEnergy() throws {
        let one = VisualizerView.energy(for: [try session(state: .working)])
        let two = VisualizerView.energy(for: [
            try session(state: .working),
            try session(state: .working)
        ])
        XCTAssertGreaterThan(one, 0.4)
        XCTAssertGreaterThan(two, one, "busier panel, livelier bars")
    }

    func testEnergyNeverExceedsOne() throws {
        let many = try (0..<20).map { _ in try session(state: .working) }
        XCTAssertLessThanOrEqual(VisualizerView.energy(for: many), 1.0)
    }
}
