import AppKit

/// A single-line label that scrolls **only when the text overflows**.
///
/// Static text that fits must stay still — constant motion in an always-on
/// panel is exhausting (docs/SPEC.md §5). The animation pauses at each end so
/// the beginning and the end are both readable.
final class MarqueeLabel: NSView {
    var text: String = "" {
        didSet { textChanged(from: oldValue) }
    }

    var font: NSFont = .systemFont(ofSize: 11) {
        didSet { invalidateLayout() }
    }

    var textColor: NSColor = .secondaryLabelColor {
        didSet { needsDisplay = true }
    }

    /// Points per second. Zero or `isEnabled == false` disables scrolling.
    var speed: CGFloat = 40
    var isEnabled = true {
        didSet { invalidateLayout() }
    }

    private var offset: CGFloat = 0
    private var timer: Timer?
    private var pauseUntil: Date?
    private let gap: CGFloat = 36
    private let endPause: TimeInterval = 1.4

    override var isFlipped: Bool { true }

    deinit {
        timer?.invalidate()
    }

    override func layout() {
        super.layout()
        invalidateLayout()
    }

    private func textChanged(from oldValue: String) {
        guard text != oldValue else { return }
        offset = 0
        pauseUntil = Date().addingTimeInterval(endPause)
        invalidateLayout()
    }

    private var textSize: NSSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private var overflows: Bool {
        textSize.width > bounds.width + 0.5
    }

    private func invalidateLayout() {
        needsDisplay = true
        if isEnabled && overflows && speed > 0 {
            startTimer()
        } else {
            stopTimer()
            offset = 0
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let tick = 1.0 / 30.0
        timer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            self?.step(by: tick)
        }
        // Keep scrolling while a menu is open or the panel is being dragged.
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        pauseUntil = nil
    }

    private func step(by interval: TimeInterval) {
        if let pauseUntil, Date() < pauseUntil { return }
        pauseUntil = nil

        offset += speed * CGFloat(interval)
        let span = textSize.width + gap
        if offset >= span {
            offset = 0
            pauseUntil = Date().addingTimeInterval(endPause)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let size = textSize
        let originY = (bounds.height - size.height) / 2

        guard overflows && timer != nil else {
            let rect = NSRect(x: 0, y: originY, width: bounds.width, height: size.height)
            (text as NSString).draw(in: rect, withAttributes: attributes)
            return
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        (text as NSString).draw(at: NSPoint(x: -offset, y: originY), withAttributes: attributes)
        // Trailing copy so the text wraps seamlessly rather than snapping back.
        (text as NSString).draw(
            at: NSPoint(x: -offset + size.width + gap, y: originY),
            withAttributes: attributes
        )
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
