import AppKit

/// One subagent child row — indented, quieter than its parent.
///
/// Children are rendered by the same list code as parents (docs/SPEC.md §4),
/// so this is deliberately a thin view rather than a second layout engine.
final class GroupRowView: NSView {
    var onActivate: (() -> Void)?

    private let dot = StatusDotView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let messageLabel = MarqueeLabel()
    private var theme: Theme = DefaultTheme.theme
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(dot)
        addSubview(nameLabel)
        addSubview(messageLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GroupRowView is created in code only")
    }

    static func height(for theme: Theme) -> CGFloat {
        theme.typography.messageSize + theme.layout.rowPadding * 2
    }

    func configure(child: AgentRow, theme: Theme) {
        self.theme = theme

        nameLabel.stringValue = child.displayName
        nameLabel.font = NSFont.systemFont(ofSize: theme.typography.messageSize, weight: .medium)
        nameLabel.textColor = theme.colors.messageDim

        messageLabel.font = theme.typography.messageFont()
        messageLabel.textColor = theme.colors.messageDim
        messageLabel.speed = theme.layout.marqueeSpeed
        messageLabel.isEnabled = theme.layout.marqueeOnOverflow
        messageLabel.text = child.message

        dot.color = theme.colors.color(for: child.state)
        dot.isProminent = child.needsAction

        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let indent = theme.layout.rowPadding + 22
        let dotSize: CGFloat = 6
        dot.frame = NSRect(x: indent, y: (bounds.height - dotSize) / 2, width: dotSize, height: dotSize)

        let textX = dot.frame.maxX + 8
        let available = max(0, bounds.width - textX - theme.layout.rowPadding)
        let nameWidth = min(available * 0.45, nameLabel.intrinsicContentSize.width)

        let lineHeight = theme.typography.messageSize + 4
        nameLabel.frame = NSRect(
            x: textX,
            y: (bounds.height - lineHeight) / 2,
            width: nameWidth,
            height: lineHeight
        )
        messageLabel.frame = NSRect(
            x: nameLabel.frame.maxX + 8,
            y: 0,
            width: max(0, available - nameWidth - 8),
            height: bounds.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.colors.rowBackgroundAlt.setFill()
        bounds.fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }
}
