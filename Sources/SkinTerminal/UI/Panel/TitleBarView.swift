import AppKit

/// The themed title strip, replacing the stock macOS titlebar.
///
/// It is also the drag handle: the panel is borderless-by-appearance, so this
/// is what you grab to move it.
final class TitleBarView: NSView {
    static let height: CGFloat = 28

    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "SkinTerminal")
    private let countLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var theme: Theme = DefaultTheme.theme

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        titleLabel.lineBreakMode = .byTruncatingTail
        countLabel.alignment = .right

        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.target = self
        closeButton.action = #selector(close)

        addSubview(closeButton)
        addSubview(titleLabel)
        addSubview(countLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TitleBarView is created in code only")
    }

    func apply(theme: Theme) {
        self.theme = theme
        layer?.backgroundColor = theme.colors.titleBarBackground.cgColor

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = theme.colors.titleBarText
        countLabel.font = .systemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = theme.colors.titleBarText.withAlphaComponent(0.55)

        closeButton.attributedTitle = NSAttributedString(
            string: "✕",
            attributes: [
                .foregroundColor: theme.colors.titleBarText.withAlphaComponent(0.5),
                .font: NSFont.systemFont(ofSize: 10)
            ]
        )
        needsDisplay = true
    }

    func update(sessions: [Session]) {
        let needy = sessions.filter(\.needsAction).count
        if sessions.isEmpty {
            countLabel.stringValue = ""
        } else if needy > 0 {
            countLabel.stringValue = "\(needy) waiting · \(sessions.count)"
        } else {
            countLabel.stringValue = "\(sessions.count)"
        }
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        closeButton.frame = NSRect(x: inset - 2, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let textY = (bounds.height - 14) / 2
        titleLabel.frame = NSRect(x: closeButton.frame.maxX + 6, y: textY, width: 150, height: 14)
        countLabel.frame = NSRect(
            x: bounds.width - inset - 90,
            y: textY,
            width: 90,
            height: 14
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.colors.titleBarBackground.setFill()
        bounds.fill()

        theme.colors.divider.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 0, y: bounds.maxY - 0.5))
        line.line(to: NSPoint(x: bounds.width, y: bounds.maxY - 0.5))
        line.stroke()
    }

    /// Dragging anywhere on the strip moves the window.
    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    @objc private func close() {
        onClose?()
    }
}
