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
    private var isAlarmed = false

    /// Five rows: the fewest an LED matrix needs to spell anything, which is
    /// what lets the same grid show a message as well as a level.
    private static let rows = 5
    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 2
    private let segmentGap: CGFloat = 1

    /// Every so often, and only while asleep, the grid spells something.
    private static let marqueeText = "SPACYAPPS"
    private static let restInterval: TimeInterval = 90
    private var messageColumn: CGFloat = -1
    private var messageTimer: Timer?

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
        if targetEnergy > 0 { start() }
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
        messageTimer?.invalidate()
        guard window != nil, targetEnergy == 0, !isAlarmed else { return }
        messageTimer = Timer.scheduledTimer(
            withTimeInterval: Self.restInterval, repeats: false
        ) { [weak self] _ in
            self?.beginMessage()
        }
    }

    private func beginMessage() {
        guard isAtRest, !isAlarmed, window != nil else { return }
        messageColumn = -1
        start()
    }

    private var isShowingMessage: Bool { messageColumn >= 0 }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    private func step() {
        if isShowingMessage || (messageColumn == -1 && isAtRest && targetEnergy == 0 && !isAlarmed) {
            advanceMessage()
            return
        }
        energy += (targetEnergy - energy) * 0.12
        resizeBarsIfNeeded()

        for index in levels.indices {
            // Neighbouring bars share a wave so the row reads as one motion
            // rather than independent flicker.
            let phase = CGFloat(index) / CGFloat(max(1, levels.count))
            let wobble = CGFloat.random(in: 0.55...1.0)
            let shape = 0.45 + 0.55 * sin((phase + CGFloat(Date().timeIntervalSince1970)) * 3)
            let target = energy * wobble * abs(shape)

            // Fast attack, slow release — the classic analyser feel.
            let rate: CGFloat = target > levels[index] ? 0.55 : 0.12
            levels[index] += (target - levels[index]) * rate

            peaks[index] = max(peaks[index] - 0.012, levels[index])
        }

        // Peaks fall on their own slower schedule, so stopping when only the
        // bars have settled freezes them mid-air as a row of stray dashes.
        if isAtRest { stop() }
        needsDisplay = true
    }

    private func advanceMessage() {
        // Real activity always wins: a message must never mask state.
        if targetEnergy > 0 || isAlarmed {
            messageColumn = -1
            needsDisplay = true
            return
        }
        messageColumn = messageColumn < 0 ? 0 : messageColumn + 0.55
        let span = CGFloat(MatrixFont.columns(for: Self.marqueeText)) + columnCount
        if messageColumn > span {
            messageColumn = -1
            stop()
        }
        needsDisplay = true
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
        if isShowingMessage {
            drawMessage(usable: usable, inset: inset)
            return
        }

        if isAtRest && !isAlarmed {
            drawSleeping()
            return
        }

        for (index, level) in levels.enumerated() {
            let originX = inset + CGFloat(index) * (barWidth + barGap)
            guard originX + barWidth <= bounds.width - inset else { break }
            drawColumn(x: originX, level: level, peak: peaks[index], usable: usable, inset: inset)
        }
    }

    /// Draws the marquee into the same grid the bars use, so it reads as the
    /// display spelling something rather than as text pasted over it.
    private func drawMessage(usable: CGFloat, inset: CGFloat) {
        let cell = (usable - CGFloat(Self.rows - 1) * segmentGap) / CGFloat(Self.rows)
        for index in levels.indices {
            let column = Int((messageColumn - CGFloat(index)).rounded())
            let originX = inset + CGFloat(index) * (barWidth + barGap)
            guard originX + barWidth <= bounds.width - inset else { break }

            for row in 0..<Self.rows {
                let lit = MatrixFont.isLit(text: Self.marqueeText, column: column, row: row)
                let y = inset + CGFloat(row) * (cell + segmentGap)
                let rect = NSRect(x: originX, y: y, width: barWidth, height: cell)
                if lit {
                    theme.colors.accent.setFill()
                } else {
                    theme.colors.divider.withAlphaComponent(0.10).setFill()
                }
                rect.fill()
            }
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

    /// Green at the floor through to the alarm colour at the ceiling — and the
    /// whole ramp shifts hot when something is waiting on you.
    private func color(at fraction: CGFloat) -> NSColor {
        let low = isAlarmed ? theme.colors.needsAction : theme.colors.accent
        let high = isAlarmed ? theme.colors.needsAction : theme.colors.working
        return low.blended(withFraction: fraction, of: high) ?? low
    }
}
