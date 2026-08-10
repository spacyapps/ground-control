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

    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 2
    private let segment: CGFloat = 3
    private let segmentGap: CGFloat = 1

    override var isFlipped: Bool { true }

    deinit {
        timer?.invalidate()
    }

    func apply(theme: Theme) {
        self.theme = theme
        needsDisplay = true
    }

    /// Energy model: working sessions drive the bars, a session waiting on you
    /// pins them high, and an idle panel falls quiet.
    static func energy(for sessions: [Session]) -> CGFloat {
        guard !sessions.isEmpty else { return 0 }
        if sessions.contains(where: \.needsAction) { return 1.0 }

        let working = sessions.filter { $0.state == .working }.count
        guard working > 0 else { return 0.12 }
        // Saturates at three: past that it is already obviously busy.
        return min(0.95, 0.45 + CGFloat(working) * 0.2)
    }

    func update(sessions: [Session]) {
        targetEnergy = Self.energy(for: sessions)
        isAlarmed = sessions.contains(where: \.needsAction)
        if targetEnergy > 0 { start() }
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
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    private func step() {
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

        // Settle to a full stop rather than idling a timer forever.
        if energy < 0.01 && levels.allSatisfy({ $0 < 0.01 }) { stop() }
        needsDisplay = true
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

        resizeBarsIfNeeded()
        guard !levels.isEmpty else { return }

        let inset: CGFloat = 3
        let usable = bounds.height - inset * 2
        guard usable > 0 else { return }

        for (index, level) in levels.enumerated() {
            let originX = inset + CGFloat(index) * (barWidth + barGap)
            guard originX + barWidth <= bounds.width - inset else { break }
            drawColumn(x: originX, level: level, peak: peaks[index], usable: usable, inset: inset)
        }
    }

    private func drawColumn(x originX: CGFloat,
                            level: CGFloat,
                            peak: CGFloat,
                            usable: CGFloat,
                            inset: CGFloat) {
        let steps = max(1, Int(usable / (segment + segmentGap)))
        let lit = Int((level * CGFloat(steps)).rounded())

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
