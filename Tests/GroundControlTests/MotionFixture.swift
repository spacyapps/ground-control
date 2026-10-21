// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import Foundation
@testable import GroundControl

/// Swaps in a `MotionPolicy` whose Mac is busy, or not, on command — for the
/// length of one test. The views read `MotionPolicy.shared`, so that is what has
/// to be replaced; `restore()` puts the real one back.
final class MotionFixture {
    let policy: MotionPolicy
    private let original = MotionPolicy.shared
    private let suite = "MotionFixture-\(UUID().uuidString)"
    private let reading = Reading()

    private final class Reading { var load = 0.0 }

    init() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
        preferences.pausesWhenBusy = true
        let reading = reading
        policy = MotionPolicy(
            preferences: preferences,
            cpu: { reading.load },
            power: { SystemLoad.Power(lowPowerMode: false, onBattery: false, percent: nil) }
        )
        MotionPolicy.shared = policy
    }

    /// A sustained load, long enough to cross the gate.
    func pause() {
        reading.load = 0.95
        for _ in 0..<BusyGate().pauseAfter { policy.sample() }
    }

    /// A sustained calm, long enough to cross it back.
    func resume() {
        reading.load = 0.05
        for _ in 0..<BusyGate().resumeAfter { policy.sample() }
    }

    func restore() {
        MotionPolicy.shared = original
        UserDefaults().removePersistentDomain(forName: suite)
    }
}
