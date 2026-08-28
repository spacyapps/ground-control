// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Decides what drives the analyser each frame: the priority stack, the
/// done-flourish slot, and the needsInput escalation timer.
///
/// A value type on purpose. This is all edges and time windows — "a finish that
/// happened under an alarm is discarded", "a new alarm re-starts the strobe",
/// "the bloom is one slot, not a queue" — the kind of logic that is subtly
/// wrong until it is tested directly rather than watched. `VisualizerView` feeds
/// it `observe(_:)` on every state change and `resolve(energy:)` every frame.
///
/// It knows nothing about the theme. A state with no formula still resolves —
/// the caller supplies zero motion for it, which is exactly today's behaviour.
/// See docs/MATRIX-CUSTOMISATION.md, "the resolution model".
struct MatrixResolver {
    /// How long the alarm strobes before it settles to the motionless lit floor.
    static let escalationWindow: TimeInterval = 15
    /// How long the done flourish is allowed to play before its slot frees.
    static let bloomWindow: TimeInterval = 1.5

    private var previousState: [String: SessionState] = [:]
    private var alarmSince: Date?
    private var alarmCount = 0
    private var doneAt: Date?

    /// The three rungs. `done` is not here — it is an edge, resolved as an
    /// overlay rather than a driver.
    enum Priority: Equatable { case needsInput, working, idle }

    struct Resolution: Equatable {
        var priority: Priority
        /// Multiplies the driver shape: full for a live alarm, the energy curve
        /// for work, and full at idle too (an idle formula is expected to keep
        /// its own values small — it is a resting texture, not a spectrum).
        var amplitude: CGFloat
        /// The ramp runs hot while anything needs you — strobing or settled.
        var isHot: Bool
        /// Seconds since the finish edge, or nil when no flourish is playing or
        /// it is suppressed by an alarm. Feeds `decay()` in a done formula.
        var bloomElapsed: TimeInterval?
    }

    /// Record state transitions. Call whenever the session list changes.
    mutating func observe(_ sessions: [Session], at now: Date = Date()) {
        var next: [String: SessionState] = [:]
        var finished = false
        for session in sessions {
            next[session.id] = session.state
            let was = previousState[session.id]
            // working — or a just-answered alarm — turning to done is a finish.
            if session.state == .done, let was, was != .done, was != .idle {
                finished = true
            }
        }
        // A finish under a live alarm is discarded, not deferred (open question
        // 3): only stamp the slot when nothing is waiting on you.
        if finished, !sessions.contains(where: \.needsAction) {
            doneAt = now
        }
        previousState = next

        let needing = sessions.filter(\.needsAction).count
        if needing == 0 {
            alarmSince = nil
        } else if alarmSince == nil || needing > alarmCount {
            // First alarm, or a *new* session needing you — restart the strobe.
            alarmSince = now
        }
        alarmCount = needing
    }

    func resolve(energy: CGFloat, at now: Date = Date()) -> Resolution {
        let bloom = bloomElapsed(now: now, suppressed: alarmCount > 0)

        if alarmCount > 0 {
            let since = alarmSince.map { now.timeIntervalSince($0) } ?? 0
            let strobing = since < Self.escalationWindow
            return Resolution(
                priority: .needsInput,
                amplitude: strobing ? 1 : 0,   // settled: motion stops, floor stays lit
                isHot: true,
                bloomElapsed: bloom
            )
        }
        if energy > 0 {
            return Resolution(priority: .working, amplitude: energy, isHot: false, bloomElapsed: bloom)
        }
        return Resolution(priority: .idle, amplitude: 1, isHot: false, bloomElapsed: bloom)
    }

    private func bloomElapsed(now: Date, suppressed: Bool) -> TimeInterval? {
        guard !suppressed, let doneAt else { return nil }
        let elapsed = now.timeIntervalSince(doneAt)
        return elapsed >= 0 && elapsed < Self.bloomWindow ? elapsed : nil
    }
}
