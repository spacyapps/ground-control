import AppKit

/// The themed footer strip: a one-line read of the whole panel.
///
/// Exists mostly so the palette's `footerBackground` / `footerText` mean
/// something, and so the window has a bottom edge that belongs to the theme
/// rather than to macOS.
final class FooterView: NSView {
    static let height: CGFloat = 22

    private let label = NSTextField(labelWithString: "")
    private var theme: Theme = DefaultTheme.theme

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FooterView is created in code only")
    }

    func apply(theme: Theme) {
        self.theme = theme
        layer?.backgroundColor = theme.colors.footerBackground.cgColor
        label.font = .systemFont(ofSize: 10)
        label.textColor = theme.colors.footerText
        needsDisplay = true
    }

    func update(sessions: [Session]) {
        guard !sessions.isEmpty else {
            label.stringValue = "Waiting for sessions…"
            return
        }
        var parts: [String] = []
        let counts = Dictionary(grouping: sessions, by: \.state).mapValues(\.count)
        if let needy = counts[.needsInput], needy > 0 { parts.append("\(needy) needs you") }
        if let working = counts[.working], working > 0 { parts.append("\(working) working") }
        if let done = counts[.done], done > 0 { parts.append("\(done) done") }
        if let idle = counts[.idle], idle > 0 { parts.append("\(idle) idle") }
        label.stringValue = parts.joined(separator: "  ·  ")
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 10, y: (bounds.height - 13) / 2, width: bounds.width - 20, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.colors.footerBackground.setFill()
        bounds.fill()

        theme.colors.divider.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 0, y: 0.5))
        line.line(to: NSPoint(x: bounds.width, y: 0.5))
        line.stroke()
    }
}
