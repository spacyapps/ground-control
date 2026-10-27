// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// What each animated surface does when the panel is asked to hold still: the
/// motion stops, the mood does not.
final class MotionHoldTests: XCTestCase {
    private var motion = MotionFixture()

    override func setUp() { motion = MotionFixture() }
    override func tearDown() { motion.restore() }

    private func session(_ state: SessionState, needs: Bool = false) throws -> Session {
        let json = """
        {"session_id":"\(UUID().uuidString)","name":"x","cwd":"/tmp/x",\
        "state":"\(state.rawValue)","message":"","needs_action":\(needs),\
        "ts":\(Int(Date().timeIntervalSince1970))}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        return Session(id: event.sessionID, latest: event, children: [], acknowledgedAt: nil)
    }

    private func analyser() -> VisualizerView {
        VisualizerView(frame: NSRect(x: 0, y: 0, width: 120, height: 20))
    }

    // MARK: - Analyser

    /// With no window the loop cannot run either way, so the bars only move here
    /// if the held path paints them. The control below is what makes that mean
    /// something.
    func testHeldAnalyserStillShowsWorking() throws {
        let control = analyser()
        control.update(sessions: [try session(.working)])
        XCTAssertTrue(control.levels.allSatisfy { $0 == 0 }, "control: with nothing pumping, nothing is lit")

        motion.pause()
        let held = analyser()
        held.update(sessions: [try session(.working)])
        // One paint of a random pattern peaks anywhere from ~0.19 up (measured over
        // 3000 draws); the control above is exactly 0, so 0.1 still proves "lit".
        XCTAssertGreaterThan(held.levels.max() ?? 0, 0.1, "held, a working panel still reads as working")
        XCTAssertFalse(held.isShowingMessage)
    }

    func testHeldAnalyserStillSettlesWhenWorkEnds() throws {
        motion.pause()
        let view = analyser()
        view.update(sessions: [try session(.working)])
        XCTAssertGreaterThan(view.levels.max() ?? 0, 0.1)

        view.update(sessions: [try session(.done)])
        XCTAssertTrue(view.levels.allSatisfy { $0 < 0.05 }, "the mood changed to done, so the bars fall")
    }

    func testReleasingTheHoldLetsTheAnalyserRunAgain() throws {
        motion.pause()
        let view = analyser()
        view.update(sessions: [try session(.working)])
        motion.resume()
        XCTAssertTrue(motion.policy.allowsMotion)
        // It was told, and is free to start; with no window it just must not crash.
        view.update(sessions: [try session(.working)])
        XCTAssertGreaterThan(view.levels.max() ?? 0, 0)
    }

    // MARK: - Avatar

    func testOnlyANeedsInputAvatarMovesWhileHeld() {
        let theme = DefaultTheme.theme
        let working = AvatarView(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        let waiting = AvatarView(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        working.configure(asset: nil, state: .working, theme: theme)
        waiting.configure(asset: nil, state: .needsInput, theme: theme)
        XCTAssertTrue(working.mayMove, "control: nothing is held yet")

        motion.pause()
        XCTAssertFalse(working.mayMove)
        XCTAssertTrue(waiting.mayMove, "a row that needs input always moves")

        motion.resume()
        XCTAssertTrue(working.mayMove)
    }

    func testAnAvatarWhoseStateBecomesNeedsInputStartsMoving() {
        motion.pause()
        let theme = DefaultTheme.theme
        let avatar = AvatarView(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        avatar.configure(asset: nil, state: .working, theme: theme)
        XCTAssertFalse(avatar.mayMove)

        avatar.configure(asset: nil, state: .needsInput, theme: theme)
        XCTAssertTrue(avatar.mayMove)
    }

    // MARK: - Layers

    func testPausingALayerFreezesItAndResumingDoesNotJump() throws {
        let layer = CALayer()
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 10
        spin.repeatCount = .infinity
        layer.add(spin, forKey: "spin")

        layer.setPaused(true)
        XCTAssertEqual(layer.speed, 0)
        let frozen = layer.timeOffset
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(layer.timeOffset, frozen, "frozen means the clock stands still")

        layer.setPaused(false)
        XCTAssertEqual(layer.speed, 1)
        let resumed = layer.convertTime(CACurrentMediaTime(), from: nil)
        XCTAssertEqual(resumed, frozen, accuracy: 0.1, "it picks up where it stopped, not where the clock got to")
    }
}
