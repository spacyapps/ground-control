// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Whether the panel's decorative motion may run right now.
///
/// Two opt-in reasons to hold still — the Mac is busy, the battery is low — and
/// one reason never to: something is waiting on you. A session that needs input
/// keeps everything moving, because the movement is how it gets noticed.
///
/// Holding still means stopping the animation, not the information. A mood still
/// changes from working to done while paused; it just changes without a flourish.
final class MotionPolicy {
    /// `var` so a test can swap in one with scripted readings.
    static var shared = MotionPolicy()

    /// Posted when `isPaused` or the alarm exemption changes, so each animated
    /// view can re-evaluate itself.
    static let didChange = Notification.Name("groundcontrol.motionPolicyDidChange")

    /// Seconds between readings. Slow enough to cost nothing, fast enough that a
    /// build starting is noticed within a few of them.
    static let sampleInterval: TimeInterval = 2

    private let preferences: Preferences
    private let cpu: () -> Double?
    private let power: () -> SystemLoad.Power
    private var busyGate = BusyGate()
    private var timer: Timer?

    /// A reason to hold still is currently true.
    private(set) var isPaused = false
    /// Some session is waiting on you.
    private(set) var hasAlarm = false

    /// Whether panel-wide motion may run: always, while an alarm is up.
    var allowsMotion: Bool { hasAlarm || !isPaused }

    init(
        preferences: Preferences = .shared,
        cpu: (() -> Double?)? = nil,
        power: @escaping () -> SystemLoad.Power = SystemLoad.power
    ) {
        self.preferences = preferences
        self.cpu = cpu ?? SystemLoad.CPUMeter().busyFraction
        self.power = power
    }

    /// Reads the two settings and starts or stops sampling to match. Called at
    /// launch and whenever a checkbox flips.
    func settingsDidChange() {
        busyGate = BusyGate()
        let wanted = preferences.pausesWhenBusy || preferences.pausesOnLowBattery
        if wanted, timer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
                self?.sample()
            }
            // Tolerance because nothing here is urgent, and the system can
            // fold the wake-up into one it was already making.
            timer.tolerance = 0.5
            self.timer = timer
        } else if !wanted {
            timer?.invalidate()
            timer = nil
        }
        sample()
    }

    /// The panel's current alarm state, from the session list.
    func update(hasAlarm: Bool) {
        guard hasAlarm != self.hasAlarm else { return }
        let before = allowsMotion
        self.hasAlarm = hasAlarm
        if allowsMotion != before { announce() }
    }

    /// One reading of each enabled reason. Internal so a test can step it.
    func sample() {
        var busy = false
        if preferences.pausesWhenBusy {
            if let load = cpu() { busy = busyGate.feed(load) } else { busy = busyGate.isBusy }
        }
        let lowPower = preferences.pausesOnLowBattery && power().isLow
        setPaused(busy || lowPower)
    }

    private func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        // Announced even while an alarm keeps panel-wide motion on: an avatar
        // whose own row is calm reads `isPaused` and holds still regardless.
        announce()
    }

    private func announce() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// Busy / not busy from a stream of readings, with hysteresis both ways.
///
/// A build that spikes the processor for one sample should not freeze the panel,
/// and a load hovering near the line should not make it flicker between the two.
/// So it takes a few readings above the line to pause, and more below a lower
/// line to resume.
struct BusyGate {
    /// Above this, the machine counts as busy…
    var pauseAbove = 0.70
    /// …and only below this does it count as free again.
    var resumeBelow = 0.50
    /// Readings in a row: 3 × 2 s to pause, 5 × 2 s to resume.
    var pauseAfter = 3
    var resumeAfter = 5

    private(set) var isBusy = false
    private var streak = 0

    @discardableResult
    mutating func feed(_ load: Double) -> Bool {
        let crossing = isBusy ? load < resumeBelow : load > pauseAbove
        guard crossing else {
            streak = 0
            return isBusy
        }
        streak += 1
        if streak >= (isBusy ? resumeAfter : pauseAfter) {
            isBusy.toggle()
            streak = 0
        }
        return isBusy
    }
}
