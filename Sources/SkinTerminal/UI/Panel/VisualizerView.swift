// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import AppKit

/// A WinAmp-style spectrum analyser in the title bar.
///
/// It is decoration, but not a lie: the energy driving it comes from what your
/// sessions are actually doing. Nothing running settles the bars to the floor;
/// a session working makes them dance; one waiting on you pushes them into the
/// red. You can read the panel's mood without reading a word of it.
final class VisualizerView: NSView {
    private var levels: [CGFloat] = []
    private var peaks: [CGFloat] = []
    private var timer: Timer?
    private var theme: Theme = DefaultTheme.theme

    /// 0…1, smoothed towards `targetEnergy` so state changes ease in.
    private var energy: CGFloat = 0
    private var targetEnergy: CGFloat = 0
    /// Small monotonic clock for the wave. Feeding `timeIntervalSince1970`
    /// into sin() loses the per-bar phase entirely at that magnitude, which is
    /// what flattened the spectrum into a solid block.
    private var phaseClock: CGFloat = 0
    private var pattern: VisualizerPattern = .wave
    private var patternUntil = Date.distantPast
    private var isAlarmed = false

    /// Five rows: the fewest an LED matrix needs to spell anything, which is
    /// what lets the same grid show a message as well as a level.
    private static let rows = 5
    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 2
    private let segmentGap: CGFloat = 1

    /// Every so often, and only while asleep, the grid spells something.
    private var messageText = MatrixMessages.brand
    private var messageTurn = 0
    /// Screen column the message's first character currently sits at. It
    /// starts off the right edge and walks left. `nil` means no message.
    private var messageScroll: CGFloat?
    private var messageTimer: Timer?
    /// Words lifted from what the sessions last said.
    private var harvested: [String] = []

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
    static func energy(for sessions: [Session]) -> CGFloat {
        let working = sessions.filter { $0.state == .working }.count
        guard working > 0 else { return 0 }
        // Saturates quickly: past a few it is already obviously busy.
        return min(1.0, 0.45 + CGFloat(working) * 0.2)
    }

    static func alarms(for sessions: [Session]) -> Bool {
        sessions.contains(where: \.needsAction)
    }

    func update(sessions: [Session]) {
        targetEnergy = Self.energy(for: sessions)
        isAlarmed = Self.alarms(for: sessions)
        harvested = MatrixMessages.harvest(from: sessions.map(\.message))
        if targetEnergy > 0 { start() }
        if messageTimer == nil && !isShowingMessage { scheduleMessage() }
        // The alarm colour can change while the bars are at rest and the timer
        // is stopped, so repaint regardless.
        needsDisplay = true
    }

    // MARK: - Animation

    private func start() {
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

    /// A one-shot rather than a heartbeat: the analyser stops dead at rest, and
    /// this wakes it just long enough to spell the name once.
    private func scheduleMessage() {
        // Never restart a countdown that is already running. The bars settle
        // between every burst of activity, and rescheduling on each settle
        // meant the delay never actually elapsed.
        guard messageTimer?.isValid != true else { return }
        messageTimer?.invalidate()
        guard window != nil, !isAlarmed else { return }
        messageTimer = Timer.scheduledTimer(
            withTimeInterval: MatrixMessages.nextDelay(), repeats: false
        ) { [weak self] _ in
            self?.beginMessage()
        }
    }

    private func beginMessage() {
        guard window != nil, !isAlarmed else { return }
        messageTurn += 1
        messageText = MatrixMessages.next(
            turn: messageTurn,
            avoiding: messageText,
            harvested: harvested
        )
        messageScroll = columnCount
        start()
    }

    private var isShowingMessage: Bool { messageScroll != nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    private func step() {
        advanceMessage()
        energy += (targetEnergy - energy) * 0.12
        resizeBarsIfNeeded()

        phaseClock += 0.09
        advancePattern()

        for index in levels.indices {
            let position = CGFloat(index) / CGFloat(max(1, levels.count - 1))
            let shape = pattern.shape(position: position, phase: phaseClock)

            // A word sweeping past pushes the bars around it, so the letters
            // look like they are displacing the spectrum rather than sitting
            // on top of it.
            let wake = messageWake(at: index)
            let wobble = CGFloat.random(in: pattern.jitter)
            let target = min(1, energy * wobble * shape + wake)

            // Fast attack, slow release — the classic analyser feel.
            let rate: CGFloat = target > levels[index] ? 0.55 : 0.12
            levels[index] += (target - levels[index]) * rate

            peaks[index] = max(peaks[index] - 0.012, levels[index])
        }

        // Peaks fall on their own slower schedule, so stopping when only the
        // bars have settled freezes them mid-air as a row of stray dashes.
        if isAtRest && !isShowingMessage { stop() }
        needsDisplay = true
    }

    /// Walks the message leftwards across the grid. The bars keep running
    /// underneath: the word is made of the same squares, so it reads as the
    /// display forming letters rather than as text pasted over a meter.
    private func advanceMessage() {
        guard var scroll = messageScroll else { return }

        // An alarm is the one thing that clears it — nothing should sweep
        // across a panel that needs you.
        if isAlarmed {
            messageScroll = nil
            return
        }

        scroll -= 0.5
        if scroll < -CGFloat(MatrixFont.columns(for: messageText)) {
            messageScroll = nil
            scheduleMessage()
        } else {
            messageScroll = scroll
        }
    }

    /// Rotates the shape every so often, so the panel has a repertoire rather
    /// than one look. Only while there is energy to see it with.
    private func advancePattern() {
        guard energy > 0.02 else { return }
        let now = Date()
        guard now >= patternUntil else { return }
        pattern = patternUntil == .distantPast
            ? VisualizerPattern.allCases.randomElement() ?? .wave
            : VisualizerPattern.next(avoiding: pattern)
        patternUntil = now.addingTimeInterval(VisualizerPattern.nextDuration())
    }

    /// Extra level for bars just outside the sweeping word.
    private func messageWake(at index: Int) -> CGFloat {
        guard let scroll = messageScroll else { return 0 }
        let distance = abs(CGFloat(index) - scroll)
        let span = CGFloat(MatrixFont.columns(for: messageText))
        guard distance < span + 6 else { return 0 }
        let edge = min(abs(CGFloat(index) - scroll), abs(CGFloat(index) - (scroll + span)))
        return edge < 5 ? (5 - edge) / 5 * 0.35 : 0
    }

    private var columnCount: CGFloat {
        CGFloat(max(1, levels.count))
    }

    private var isAtRest: Bool {
        energy < 0.01
            && levels.allSatisfy { $0 < 0.01 }
            && peaks.allSatisfy { $0 < 0.01 }
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

    /// Which column of the message, if any, currently sits at this screen
    /// position.
    private func messageColumn(at index: Int) -> Int? {
        guard let scroll = messageScroll else { return nil }
        let column = index - Int(scroll.rounded())
        guard column >= 0, column < MatrixFont.columns(for: messageText) else { return nil }
        return column
    }

    /// One column of the sweeping word, drawn in the same cells the bars use.
    private func drawLetterColumn(x originX: CGFloat, column: Int, usable: CGFloat, inset: CGFloat) {
        let cell = (usable - CGFloat(Self.rows - 1) * segmentGap) / CGFloat(Self.rows)
        for row in 0..<Self.rows {
            let lit = MatrixFont.isLit(text: messageText, column: column, row: row)
            let y = inset + CGFloat(row) * (cell + segmentGap)
            if lit {
                letterColor.setFill()
            } else {
                theme.colors.divider.withAlphaComponent(0.10).setFill()
            }
            NSRect(x: originX, y: y, width: barWidth, height: cell).fill()
        }
    }

    private func drawSleeping() {
        let face = "-  ‿  -"
        let color = theme.colors.messageDim.withAlphaComponent(0.75)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(13, bounds.height * 0.5), weight: .medium),
            .foregroundColor: color
        ]
        let size = (face as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2 - 10, y: (bounds.height - size.height) / 2)
        (face as NSString).draw(at: origin, withAttributes: attributes)

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

            if step < lit {
                color(at: fraction).setFill()
            } else {
                theme.colors.divider.withAlphaComponent(0.10).setFill()
            }
            rect.fill()
        }

        // The peak marker that hangs in the air and drifts down.
        guard peak > 0.02 else { return }
        let peakStep = min(steps - 1, Int((peak * CGFloat(steps)).rounded()))
        let peakY = bounds.height - inset - CGFloat(peakStep + 1) * (segment + segmentGap)
        theme.colors.titleBarText.withAlphaComponent(0.7).setFill()
        NSRect(x: originX, y: peakY, width: barWidth, height: 1).fill()
    }

    /// The word picks its own colour from the palette, so consecutive messages
    /// look different without ever borrowing the alarm red.
    private var letterColor: NSColor {
        // No white and never the alarm red: white reads as "not coloured", and
        // red belongs to a row that needs you.
        let blend = theme.colors.accent.blended(withFraction: 0.5, of: theme.colors.working)
        let palette = [theme.colors.working, theme.colors.accent, blend ?? theme.colors.working]
        let hash = messageText.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }

    /// Green at the floor through to the alarm colour at the ceiling — and the
    /// whole ramp shifts hot when something is waiting on you.
    private func color(at fraction: CGFloat) -> NSColor {
        let low = isAlarmed ? theme.colors.needsAction : theme.colors.accent
        let high = isAlarmed ? theme.colors.needsAction : theme.colors.working
        return low.blended(withFraction: fraction, of: high) ?? low
    }
}
