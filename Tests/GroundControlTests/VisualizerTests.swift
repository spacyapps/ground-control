// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The analyser is decoration, but its energy is derived from real state — so
/// the mapping is worth pinning down.
final class VisualizerTests: XCTestCase {
    private func session(state: SessionState, needsAction: Bool = false) throws -> Session {
        // Timestamps must be recent: a session that has been quiet for half an
        // hour reads as idle regardless of what its last line claimed.
        let now = Int(Date().timeIntervalSince1970)
        let json = """
        {"session_id":"\(UUID().uuidString)","name":"x","cwd":"/tmp/x",\
        "state":"\(state.rawValue)","message":"","needs_action":\(needsAction),"ts":\(now)}
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

    /// The `sensitivity` knob only changes how loudly work reads, never whether
    /// silence is silent (docs/MATRIX-CUSTOMISATION.md).
    func testSensitivityScalesWorkButNotRest() throws {
        let one = [try session(state: .working)]
        var eager = MatrixFeel.Resolved.standard
        eager.energyFloor = 0.60
        var mellow = MatrixFeel.Resolved.standard
        mellow.energyFloor = 0.35
        XCTAssertGreaterThan(
            VisualizerView.energy(for: one, feel: eager),
            VisualizerView.energy(for: one, feel: mellow)
        )
        XCTAssertEqual(VisualizerView.energy(for: [], feel: eager), 0)
        XCTAssertEqual(VisualizerView.energy(for: [try session(state: .idle)], feel: eager), 0)
    }
}
