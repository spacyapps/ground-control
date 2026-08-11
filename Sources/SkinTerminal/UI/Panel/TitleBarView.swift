import AppKit

/// The themed title strip, replacing the stock macOS titlebar.
///
/// It is also the drag handle: the panel is borderless-by-appearance, so this
/// is what you grab to move it.
final class TitleBarView: NSView {
    static let height: CGFloat = 64

    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "SkinTerminal")
    private let countLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let visualizer = VisualizerView()
    private let mark = NSImageView()
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

        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.image = Brand.glyph
        addSubview(mark)
        addSubview(closeButton)
        addSubview(titleLabel)
        addSubview(countLabel)
        addSubview(visualizer)
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
        // A theme may supply its own mark; otherwise ours.
        if let custom = theme.backgrounds.brandMark, let image = NSImage(contentsOf: custom) {
            mark.image = image
        } else {
            mark.image = Brand.glyph
        }
        visualizer.apply(theme: theme)
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
        visualizer.update(sessions: sessions)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        let titleRow: CGFloat = 22

        closeButton.frame = NSRect(x: inset - 2, y: (titleRow - 16) / 2 + 4, width: 16, height: 16)
        let markSide: CGFloat = 15
        mark.frame = NSRect(
            x: closeButton.frame.maxX + 7,
            y: (titleRow - markSide) / 2 + 4,
            width: markSide,
            height: markSide
        )
        let textY = (titleRow - 14) / 2 + 4
        titleLabel.frame = NSRect(x: mark.frame.maxX + 6, y: textY, width: 150, height: 14)
        countLabel.frame = NSRect(x: bounds.width - inset - 90, y: textY, width: 90, height: 14)

        visualizer.frame = NSRect(
            x: inset,
            y: titleRow + 6,
            width: bounds.width - inset * 2,
            height: max(0, bounds.height - titleRow - 12)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.colors.titleBarBackground.setFill()
        bounds.fill()

        if let background = theme.backgrounds.titleBar {
            BackgroundRenderer.draw(background, in: bounds)
        }

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
