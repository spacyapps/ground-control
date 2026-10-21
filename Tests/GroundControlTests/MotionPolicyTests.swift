// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// When the panel holds still. Every test builds its own policy over a throwaway
/// `UserDefaults`, a scripted CPU and a scripted battery: the real ones would make
/// the result depend on what the Mac happened to be doing.
final class MotionPolicyTests: XCTestCase {
    private var suite = ""
    private var preferences = Preferences()
    private var load: Double? = 0
    private var power = SystemLoad.Power(lowPowerMode: false, onBattery: false, percent: nil)

    override func setUp() {
        suite = "MotionPolicyTests-\(UUID().uuidString)"
        preferences = Preferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
        load = 0
        power = SystemLoad.Power(lowPowerMode: false, onBattery: false, percent: nil)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func policy() -> MotionPolicy {
        MotionPolicy(preferences: preferences, cpu: { [unowned self] in load }, power: { [unowned self] in power })
    }

    /// Feeds `readings` of `value` through the policy, one sample each.
    private func run(_ policy: MotionPolicy, load value: Double, times readings: Int) {
        load = value
        for _ in 0..<readings { policy.sample() }
    }

    // MARK: - Busy

    func testDoesNothingUntilAskedTo() {
        let policy = policy()
        run(policy, load: 1.0, times: 20)
        XCTAssertTrue(policy.allowsMotion, "with both options off, a flat-out Mac changes nothing")
    }

    func testPausesAfterSustainedLoadNotASpike() {
        preferences.pausesWhenBusy = true
        let policy = policy()

        run(policy, load: 0.95, times: 2)
        XCTAssertFalse(policy.isPaused, "two hot readings are a spike, not a busy Mac")
        run(policy, load: 0.95, times: 1)
        XCTAssertTrue(policy.isPaused)
    }

    func testASpikeBetweenCalmReadingsNeverPauses() {
        preferences.pausesWhenBusy = true
        let policy = policy()
        for _ in 0..<5 {
            run(policy, load: 0.95, times: 2)
            run(policy, load: 0.10, times: 1)
        }
        XCTAssertFalse(policy.isPaused)
    }

    func testResumesOnlyWellBelowTheLineAndAfterAWhile() {
        preferences.pausesWhenBusy = true
        let policy = policy()
        run(policy, load: 0.95, times: 3)
        XCTAssertTrue(policy.isPaused)

        run(policy, load: 0.60, times: 20)
        XCTAssertTrue(policy.isPaused, "between the lines it holds its state, so it cannot flicker")
        run(policy, load: 0.20, times: 4)
        XCTAssertTrue(policy.isPaused, "four calm readings are not yet enough")
        run(policy, load: 0.20, times: 1)
        XCTAssertFalse(policy.isPaused)
    }

    func testAnUnreadableLoadKeepsTheLastAnswer() {
        preferences.pausesWhenBusy = true
        let policy = policy()
        run(policy, load: 0.95, times: 3)

        load = nil
        policy.sample()
        XCTAssertTrue(policy.isPaused)
    }

    // MARK: - Battery

    func testLowBatteryPausesOnlyWhenAskedAndOnlyOnBattery() {
        let policy = policy()
        power = SystemLoad.Power(lowPowerMode: false, onBattery: true, percent: 10)
        policy.sample()
        XCTAssertFalse(policy.isPaused, "the option is off")

        preferences.pausesOnLowBattery = true
        policy.sample()
        XCTAssertTrue(policy.isPaused)

        power = SystemLoad.Power(lowPowerMode: false, onBattery: false, percent: 10)
        policy.sample()
        XCTAssertFalse(policy.isPaused, "plugged in, a low charge is on its way up")
    }

    func testLowPowerModePausesWhateverTheCharge() {
        preferences.pausesOnLowBattery = true
        let policy = policy()
        power = SystemLoad.Power(lowPowerMode: true, onBattery: false, percent: 100)
        policy.sample()
        XCTAssertTrue(policy.isPaused)
    }

    func testBatteryThresholdIsAFifth() {
        XCTAssertTrue(SystemLoad.Power(lowPowerMode: false, onBattery: true, percent: 20).isLow)
        XCTAssertFalse(SystemLoad.Power(lowPowerMode: false, onBattery: true, percent: 21).isLow)
        XCTAssertFalse(SystemLoad.Power(lowPowerMode: false, onBattery: true, percent: nil).isLow)
    }

    // MARK: - Alarm

    func testAnAlarmKeepsEverythingMovingThenLetsGo() {
        preferences.pausesWhenBusy = true
        let policy = policy()
        run(policy, load: 0.95, times: 3)
        XCTAssertFalse(policy.allowsMotion)

        policy.update(hasAlarm: true)
        XCTAssertTrue(policy.allowsMotion, "a session that needs input is why the panel moves")
        XCTAssertTrue(policy.isPaused, "the reason to pause is still true")

        policy.update(hasAlarm: false)
        XCTAssertFalse(policy.allowsMotion)
    }

    // MARK: - Telling the views

    func testViewsAreToldWhenItChangesAndNotWhenItDoesNot() {
        preferences.pausesWhenBusy = true
        let policy = policy()
        var told = 0
        let token = NotificationCenter.default.addObserver(
            forName: MotionPolicy.didChange, object: policy, queue: nil
        ) { _ in told += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        run(policy, load: 0.95, times: 10)
        XCTAssertEqual(told, 1, "once, when it paused — not once per reading")
        policy.update(hasAlarm: true)
        policy.update(hasAlarm: true)
        XCTAssertEqual(told, 2)
    }

    func testTurningTheOptionOffReleasesAPause() {
        preferences.pausesWhenBusy = true
        let policy = policy()
        run(policy, load: 0.95, times: 3)
        XCTAssertTrue(policy.isPaused)

        preferences.pausesWhenBusy = false
        policy.settingsDidChange()
        XCTAssertFalse(policy.isPaused)
    }

    // MARK: - The real readers

    func testCPUMeterReturnsAFractionOnceItHasSomethingToCompare() {
        let meter = SystemLoad.CPUMeter()
        XCTAssertNil(meter.busyFraction(), "the first reading has nothing to compare with")
        var spin = 0.0
        for index in 0..<2_000_000 { spin += sin(Double(index)) }
        XCTAssertGreaterThan(spin, -1e9)
        let reading = meter.busyFraction()
        XCTAssertNotNil(reading)
        XCTAssertTrue((0...1).contains(reading ?? -1))
    }

    func testPowerReaderAnswersOnThisMac() {
        let power = SystemLoad.power()
        if let percent = power.percent { XCTAssertTrue((0...100).contains(percent)) }
    }
}
