// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The resolution model from docs/MATRIX-CUSTOMISATION.md, one test per row of
/// the scenario table plus the four closed open-questions.
final class MatrixResolverTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func session(_ id: String, _ state: SessionState, needs: Bool = false) throws -> Session {
        let json = """
        {"session_id":"\(id)","name":"x","cwd":"/tmp/x","state":"\(state.rawValue)",\
        "message":"","needs_action":\(needs),"ts":\(Int(Date().timeIntervalSince1970))}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        return Session(id: event.sessionID, latest: event, children: [], acknowledgedAt: nil)
    }

    // MARK: - Priority (rows 1–4, 9)

    func testIdleWhenNothingIsHappening() throws {
        var resolver = MatrixResolver()
        resolver.observe([try session("a", .idle)], at: start)
        XCTAssertEqual(resolver.resolve(energy: 0, at: start).priority, .idle)
    }

    func testWorkingBeatsIdle() throws {
        var resolver = MatrixResolver()
        resolver.observe([try session("a", .working), try session("b", .idle)], at: start)
        let plan = resolver.resolve(energy: 0.6, at: start)
        XCTAssertEqual(plan.priority, .working)
        XCTAssertEqual(plan.amplitude, 0.6, "working amplitude is the energy curve")
        XCTAssertFalse(plan.isHot)
    }

    func testNeedsInputSeizesEverything() throws {
        var resolver = MatrixResolver()
        resolver.observe([
            try session("a", .needsInput, needs: true),
            try session("b", .working)
        ], at: start)
        let plan = resolver.resolve(energy: 0.9, at: start)
        XCTAssertEqual(plan.priority, .needsInput)
        XCTAssertEqual(plan.amplitude, 1, "a live alarm runs at full")
        XCTAssertTrue(plan.isHot)
    }

    // MARK: - The done edge (rows 5–8, 10, 13)

    func testWorkingToDoneFiresABloom() throws {
        var resolver = MatrixResolver()
        resolver.observe([try session("a", .working)], at: start)
        resolver.observe([try session("a", .done)], at: start + 1)
        let elapsed = try XCTUnwrap(resolver.resolve(energy: 0, at: start + 1).bloomElapsed)
        XCTAssertEqual(elapsed, 0, accuracy: 0.001)
    }

    /// Row 5 — a finish edge while other sessions still work: `working` keeps
    /// the meter, the bloom rides on top.
    func testABloomPlaysWhileOthersStillWork() throws {
        var resolver = MatrixResolver()
        resolver.observe([
            try session("a", .working),
            try session("b", .working),
            try session("c", .working)
        ], at: start)
        resolver.observe([
            try session("a", .working),
            try session("b", .working),
            try session("c", .done)
        ], at: start + 1)
        let plan = resolver.resolve(energy: 0.7, at: start + 1)
        XCTAssertEqual(plan.priority, .working)
        XCTAssertNotNil(plan.bloomElapsed, "the flourish rides on top of the working spectrum")
    }

    /// Row 19 — an alarm appearing mid-bloom cuts it that frame, not a decay.
    func testAnAlarmMidBloomSuppressesItImmediately() throws {
        var resolver = MatrixResolver()
        resolver.observe([try session("a", .working)], at: start)
        resolver.observe([try session("a", .done)], at: start + 1)
        XCTAssertNotNil(resolver.resolve(energy: 0, at: start + 1.2).bloomElapsed)
        // b now needs you, well inside the bloom window.
        resolver.observe([
            try session("a", .done),
            try session("b", .needsInput, needs: true)
        ], at: start + 1.3)
        XCTAssertNil(resolver.resolve(energy: 0, at: start + 1.3).bloomElapsed,
                     "the bloom is gone the instant the alarm arrives")
    }

    func testTheBloomFreesItsSlotAfterTheWindow() throws {
        var resolver = MatrixResolver()
        resolver.observe([try session("a", .working)], at: start)
        resolver.observe([try session("a", .done)], at: start + 1)
        XCTAssertNotNil(resolver.resolve(energy: 0, at: start + 2).bloomElapsed,
                        "within bloomWindow it is still playing")
        XCTAssertNil(resolver.resolve(energy: 0, at: start + 3).bloomElapsed,
                     "past bloomWindow the slot is free again")
    }

    func testTwoFinishesInOneFrameAreOneBloom() throws {
        var resolver = MatrixResolver()
        resolver.observe([try session("a", .working), try session("b", .working)], at: start)
        resolver.observe([try session("a", .done), try session("b", .done)], at: start + 1)
        // One slot: the elapsed time is measured from the single stamp, not doubled.
        XCTAssertEqual(resolver.resolve(energy: 0, at: start + 1).bloomElapsed ?? -1, 0, accuracy: 0.001)
    }

    /// Open question 3 — a finish under a live alarm is discarded, not deferred.
    func testAFinishUnderAnAlarmIsLost() throws {
        var resolver = MatrixResolver()
        resolver.observe([
            try session("a", .needsInput, needs: true),
            try session("b", .working)
        ], at: start)
        // b finishes while the alarm is still up.
        resolver.observe([
            try session("a", .needsInput, needs: true),
            try session("b", .done)
        ], at: start + 1)
        // Alarm answered a moment later — no deferred bloom appears.
        resolver.observe([try session("a", .idle), try session("b", .done)], at: start + 2)
        XCTAssertNil(resolver.resolve(energy: 0, at: start + 2).bloomElapsed)
    }

    /// Open question 2 — same-frame alarm-clear plus a finish edge: the bloom
    /// fires, because no needsInput is present that frame.
    func testSameFrameAlarmClearAndFinishBlooms() throws {
        var resolver = MatrixResolver()
        resolver.observe([
            try session("a", .needsInput, needs: true),
            try session("b", .working)
        ], at: start)
        resolver.observe([try session("a", .idle), try session("b", .done)], at: start + 1)
        XCTAssertNotNil(resolver.resolve(energy: 0, at: start + 1).bloomElapsed)
    }

    // MARK: - needsInput escalation (rows 14–16)

    func testTheStrobeSettlesToTheLitFloor() throws {
        var resolver = MatrixResolver()
        resolver.observe([try session("a", .needsInput, needs: true)], at: start)
        XCTAssertEqual(resolver.resolve(energy: 0, at: start + 5).amplitude, 1, "still strobing")
        let settled = resolver.resolve(energy: 0, at: start + MatrixResolver.escalationWindow + 1)
        XCTAssertEqual(settled.amplitude, 0, "motion stops")
        XCTAssertTrue(settled.isHot, "but the ramp stays hot — the floor is still lit")
    }

    /// Open question 1 — a *new* alarm restarts the strobe.
    func testANewAlarmReEscalates() throws {
        var resolver = MatrixResolver()
        resolver.observe([try session("a", .needsInput, needs: true)], at: start)
        let settledAt = start + MatrixResolver.escalationWindow + 5
        XCTAssertEqual(resolver.resolve(energy: 0, at: settledAt).amplitude, 0)
        // b now also needs you.
        resolver.observe([
            try session("a", .needsInput, needs: true),
            try session("b", .needsInput, needs: true)
        ], at: settledAt)
        let restarted = resolver.resolve(energy: 0, at: settledAt + 1).amplitude
        XCTAssertEqual(restarted, 1, "the strobe restarts for the new one")
    }

    func testAnsweringOneOfTwoDoesNotReEscalate() throws {
        var resolver = MatrixResolver()
        resolver.observe([
            try session("a", .needsInput, needs: true),
            try session("b", .needsInput, needs: true)
        ], at: start)
        let settledAt = start + MatrixResolver.escalationWindow + 5
        resolver.observe([
            try session("a", .idle),
            try session("b", .needsInput, needs: true)
        ], at: settledAt)
        let stillSettled = resolver.resolve(energy: 0, at: settledAt + 1).amplitude
        XCTAssertEqual(stillSettled, 0, "answering one is not a new edge")
    }

    /// Row 11 — answering an alarm just uncovers what is beneath, no bloom.
    func testAnsweringAnAlarmIsNotAFinish() throws {
        var resolver = MatrixResolver()
        resolver.observe([try session("a", .needsInput, needs: true)], at: start)
        resolver.observe([try session("a", .working)], at: start + 1)
        let plan = resolver.resolve(energy: 0.5, at: start + 1)
        XCTAssertEqual(plan.priority, .working)
        XCTAssertNil(plan.bloomElapsed)
    }
}
