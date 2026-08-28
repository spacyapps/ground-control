// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// A WinAmp-style spectrum analyser in the title bar.
///
/// It is decoration, but not a lie: the energy driving it comes from what your
/// sessions are actually doing. Nothing running settles the bars to the floor;
/// a session working makes them dance; one waiting on you pushes them into the
/// red. You can read the panel's mood without reading a word of it.
///
/// Which shape drives the bars, and whether a done flourish is playing, is
/// `MatrixResolver`'s job — the priority stack, the escalation timer and the
/// bloom slot are all edges and windows and live better in a tested value type.
/// This view owns the 24 fps loop, the easing, and the draw. The word-spelling
/// half is in `VisualizerView+Marquee.swift`.
///
/// A theme with no `matrix.shape` formulas behaves exactly as it always has:
/// the eight patterns rotate while working, the panel is flat with a lit red
/// floor while something waits, and it sleeps otherwise.
final class VisualizerView: NSView {
    var levels: [CGFloat] = []
    private var peaks: [CGFloat] = []
    private var timer: Timer?
    var theme: Theme = DefaultTheme.theme

    /// 0…1, smoothed towards `targetEnergy` so state changes ease in.
    private var energy: CGFloat = 0
    private var targetEnergy: CGFloat = 0
    /// Small monotonic clock for the wave. Feeding `timeIntervalSince1970`
    /// into sin() loses the per-bar phase entirely at that magnitude, which is
    /// what flattened the spectrum into a solid block.
    private var phaseClock: CGFloat = 0
    private var pattern: VisualizerPattern = .wave
    private var patternUntil = Date.distantPast
    var isAlarmed = false
    private var resolver = MatrixResolver()
    /// Advanced one tick per `step()` rather than read from the wall clock, so
    /// the escalation and bloom windows count frames — steady under scheduling
    /// jitter, and deterministic to test. Re-seeded from `Date()` whenever the
    /// loop resumes from rest.
    private var frameTime = Date()

    /// Five rows: the fewest an LED matrix needs to spell anything, which is
    /// what lets the same grid show a message as well as a level.
    static let rows = 5
    let barWidth: CGFloat = 3
    private let barGap: CGFloat = 2
    let segmentGap: CGFloat = 1

    /// Every so often, and only while asleep, the grid spells something.
    var messageText = MatrixMessages.brand
    var messageTurn = 0
    /// Screen column the message's first character currently sits at. It starts
    /// off the right edge and walks left. `nil` means no message.
    var messageScroll: CGFloat?
    var messageTimer: Timer?
    /// Words lifted from what the sessions last said.
    var harvested: [String] = []

    override var isFlipped: Bool { true }

    deinit {
        timer?.invalidate()
        messageTimer?.invalidate()
    }

    func apply(theme: Theme) {
        self.theme = theme
        needsDisplay = true
    }

    /// Work is the only signal. Like a real analyser, silence is *flat* — not
    /// a low idle shimmer — so movement in the corner of your eye always means
    /// something is actually running. A session waiting on you is not working,
    /// so it does not drive the bars; it colours them instead.
    ///
    /// The floor and per-session step are the theme's `sensitivity` knob
    /// (docs/MATRIX-CUSTOMISATION.md); `.standard` is the shipped curve.
    static func energy(for sessions: [Session], feel: MatrixFeel.Resolved = .standard) -> CGFloat {
        let working = sessions.filter { $0.state == .working }.count
        guard working > 0 else { return 0 }
        // Saturates quickly: past a few it is already obviously busy.
        return min(1.0, feel.energyFloor + CGFloat(working) * feel.energyPerSession)
    }

    static func alarms(for sessions: [Session]) -> Bool {
        sessions.contains(where: \.needsAction)
    }

    func update(sessions: [Session]) {
        targetEnergy = Self.energy(for: sessions, feel: theme.matrix.feel)
        isAlarmed = Self.alarms(for: sessions)
        // A stopped loop leaves frameTime frozen; catch it up so a resumed
        // animation starts from now, not from minutes ago.
        if timer == nil { frameTime = Date() }
        resolver.observe(sessions, at: frameTime)
        harvested = MatrixMessages.harvest(from: sessions.map(\.message))
        // A done flourish with nothing working still needs the loop running to
        // play out, so start on any of the three, not just energy.
        if targetEnergy > 0 || isAlarmed
            || resolver.resolve(energy: 0, at: frameTime).bloomElapsed != nil {
            start()
        }
        if messageTimer == nil && !isShowingMessage { scheduleMessage() }
        // The alarm colour can change while the bars are at rest and the timer
        // is stopped, so repaint regardless.
        needsDisplay = true
    }

    // MARK: - Animation

    func start() {
        guard timer == nil, window != nil else { return }
        let tick = 1.0 / 24.0
        let timer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            self?.step()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        scheduleMessage()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    /// One animation tick. Internal only so a test can pump it without a
    /// run loop — the timer is the sole caller in the app.
    func step() {
        advanceMessage()
        frameTime += 1.0 / 24.0
        let feel = theme.matrix.feel
        energy += (targetEnergy - energy) * 0.12
        resizeBarsIfNeeded()

        phaseClock += feel.phaseStep
        advancePattern()

        let plan = resolver.resolve(energy: energy, at: frameTime)
        let barCount = levels.count
        let driver = driverSampler(for: plan.priority, count: barCount)
        // The rotating pattern is the fallback for `working` only. `needsInput`
        // and `idle` with no formula stay flat — that is today's behaviour, and
        // it is why an alarm with no strobe formula is just a lit red floor.
        let patternFallback = driver == nil && plan.priority == .working
        let bloom = plan.bloomElapsed.flatMap { elapsed in
            theme.matrix.doneShape?.sampler(
                phase: phaseClock, energy: energy, count: barCount, decayElapsed: elapsed
            )
        }

        for index in levels.indices {
            let position = CGFloat(index) / CGFloat(max(1, barCount - 1))
            let base: CGFloat
            if let driver {
                base = driver.height(pos: Double(position), bar: index)
            } else if patternFallback {
                base = pattern.shape(position: position, phase: phaseClock)
            } else {
                base = 0
            }
            let bloomHeight = bloom?.height(pos: Double(position), bar: index) ?? 0

            // A word sweeping past pushes the bars around it.
            let wake = messageWake(at: index)
            // The theme's `jitter` knob overrides the pattern's own range;
            // absent, each pattern keeps the noise that suits it.
            let wobble = CGFloat.random(in: feel.jitter ?? pattern.jitter)
            let target = min(1, plan.amplitude * wobble * base + bloomHeight + wake)

            // Fast attack, slow release — the classic analyser feel. Attack
            // stays quick; `fall` tunes only the release side.
            let rate: CGFloat = target > levels[index] ? 0.55 : feel.release
            levels[index] += (target - levels[index]) * rate

            peaks[index] = max(peaks[index] - feel.peakFall, levels[index])
        }

        // Peaks fall on their own slower schedule, so stopping when only the
        // bars have settled freezes them mid-air as a row of stray dashes.
        if isAtRest && !isShowingMessage && !isAlarmed { stop() }
        needsDisplay = true
    }

    /// The formula driving the bars this frame, or nil. For `working`, nil means
    /// "use the rotating built-in pattern"; for `needsInput` and `idle`, nil
    /// means flat.
    private func driverSampler(for priority: MatrixResolver.Priority,
                               count: Int) -> PatternFormula.Sampler? {
        let formula: PatternFormula?
        switch priority {
        case .needsInput: formula = theme.matrix.needsInputShape
        case .working:    formula = theme.matrix.workingShape
        case .idle:       formula = theme.matrix.idleShape
        }
        return formula?.sampler(phase: phaseClock, energy: energy, count: count)
    }

    /// Rotates the shape every so often, so the panel has a repertoire rather
    /// than one look. Only while there is energy to see it with.
    private func advancePattern() {
        guard energy > 0.02 else { return }
        let now = frameTime
        guard now >= patternUntil else { return }
        let rotation = theme.matrix.patterns
        if patternUntil == .distantPast {
            pattern = rotation.randomElement() ?? .wave
        } else {
            let others = rotation.filter { $0 != pattern }
            pattern = others.randomElement() ?? pattern
        }
        let hold = theme.matrix.feel.patternHold
        patternUntil = now.addingTimeInterval(VisualizerPattern.nextDuration(in: hold))
    }

    private var isAtRest: Bool {
        energy < 0.01
            && levels.allSatisfy { $0 < 0.01 }
            && peaks.allSatisfy { $0 < 0.01 }
            && resolver.resolve(energy: 0, at: frameTime).bloomElapsed == nil
    }

    private func resizeBarsIfNeeded() {
        let count = max(1, Int(bounds.width / (barWidth + barGap)))
        guard count != levels.count else { return }
        levels = Array(repeating: 0, count: count)
        peaks = Array(repeating: 0, count: count)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // The palette's footer colours live on as this recessed well.
        theme.colors.footerBackground.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()

        if let background = theme.backgrounds.footer {
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).addClip()
            BackgroundRenderer.draw(background, in: bounds)
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        resizeBarsIfNeeded()
        guard !levels.isEmpty else { return }

        let inset: CGFloat = 3
        let usable = bounds.height - inset * 2
        guard usable > 0 else { return }

        // Fully asleep with nothing waiting: an empty grid says "broken", a
        // sleeping face says "quiet". Something waiting on you still gets the
        // lit red floor below, so rest never hides an alarm.
        if isAtRest && !isAlarmed && !isShowingMessage {
            drawSleeping()
            return
        }

        for (index, level) in levels.enumerated() {
            let originX = inset + CGFloat(index) * (barWidth + barGap)
            guard originX + barWidth <= bounds.width - inset else { break }

            if let column = messageColumn(at: index) {
                drawLetterColumn(x: originX, column: column, usable: usable, inset: inset)
            } else {
                drawColumn(x: originX, level: level, peak: peaks[index], usable: usable, inset: inset)
            }
        }
    }

    private func drawSleeping() {
        let face = theme.matrix.feel.sleepFace
        let color = theme.colors.messageDim.withAlphaComponent(0.75)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(13, bounds.height * 0.5), weight: .medium),
            .foregroundColor: color
        ]
        let size = (face as NSString).size(withAttributes: attributes)
        let hasZzz = theme.matrix.feel.sleepZzz
        // The face sits left of centre only to leave room for the "z z z".
        let shift: CGFloat = hasZzz ? -10 : 0
        let origin = NSPoint(
            x: (bounds.width - size.width) / 2 + shift,
            y: (bounds.height - size.height) / 2
        )
        (face as NSString).draw(at: origin, withAttributes: attributes)

        guard hasZzz else { return }
        let zzz = "z z z"
        let zAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(9, bounds.height * 0.35), weight: .semibold),
            .foregroundColor: color.withAlphaComponent(0.5)
        ]
        (zzz as NSString).draw(
            at: NSPoint(x: origin.x + size.width + 8, y: origin.y - 2),
            withAttributes: zAttributes
        )
    }

    private func drawColumn(x originX: CGFloat,
                            level: CGFloat,
                            peak: CGFloat,
                            usable: CGFloat,
                            inset: CGFloat) {
        let steps = Self.rows
        let segment = (usable - CGFloat(steps - 1) * segmentGap) / CGFloat(steps)
        // At rest with something waiting on you, keep the floor row lit: signal
        // present, no motion — a mixer sitting at zero with the input hot.
        let floor = isAlarmed ? 1 : 0
        let lit = max(floor, Int((level * CGFloat(steps)).rounded()))

        for step in 0..<steps {
            let fraction = CGFloat(step) / CGFloat(max(1, steps - 1))
            let y = bounds.height - inset - CGFloat(step + 1) * (segment + segmentGap)
            let rect = NSRect(x: originX, y: y, width: barWidth, height: segment)
            (step < lit ? color(at: fraction) : theme.matrix.unlit).setFill()
            rect.fill()
        }

        // The peak marker that hangs in the air and drifts down.
        guard peak > 0.02 else { return }
        let peakStep = min(steps - 1, Int((peak * CGFloat(steps)).rounded()))
        let peakY = bounds.height - inset - CGFloat(peakStep + 1) * (segment + segmentGap)
        theme.matrix.peak.setFill()
        NSRect(x: originX, y: peakY, width: barWidth, height: 1).fill()
    }

    /// Green at the floor through to the alarm colour at the ceiling — and the
    /// whole ramp shifts hot when something is waiting on you.
    private func color(at fraction: CGFloat) -> NSColor {
        let low = isAlarmed ? theme.matrix.alarm : theme.matrix.low
        let high = isAlarmed ? theme.matrix.alarm : theme.matrix.high
        return low.blended(withFraction: fraction, of: high) ?? low
    }
}
