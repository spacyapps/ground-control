import AppKit

/// One session row: dot + name + latest message, with an optional disclosure
/// triangle when the session has subagent children.
///
/// Clicking the body jumps to the terminal and clears the dot; clicking the
/// triangle only toggles children (docs/SPEC.md §5).
final class SessionRowView: NSView {
    var onActivate: (() -> Void)?
    var onToggleChildren: (() -> Void)?
    var onSecondaryClick: ((NSEvent) -> Void)?

    private let dot = StatusDotView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let messageLabel = MarqueeLabel()
    private let disclosure = NSButton()
    private let avatar = AvatarView()

    private var theme: Theme = DefaultTheme.theme
    private var isHovering = false
    private var isGroup = false
    private var isExpanded = false
    private var useAlternateBackground = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isSelectable = false

        disclosure.isBordered = false
        disclosure.bezelStyle = .inline
        disclosure.title = ""
        disclosure.target = self
        disclosure.action = #selector(toggleChildren)
        disclosure.isHidden = true

        addSubview(dot)
        addSubview(nameLabel)
        addSubview(messageLabel)
        addSubview(disclosure)
        addSubview(avatar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SessionRowView is created in code only")
    }

    // MARK: - Content

    func configure(session: Session,
                   theme: Theme,
                   renames: [String: String],
                   isExpanded: Bool,
                   isAlternate: Bool) {
        self.theme = theme
        self.isGroup = session.isGroup
        self.isExpanded = isExpanded
        self.useAlternateBackground = isAlternate

        nameLabel.stringValue = session.displayName(renames: renames)
        nameLabel.font = theme.typography.nameFont()
        nameLabel.textColor = theme.colors.sessionName

        messageLabel.font = theme.typography.messageFont()
        messageLabel.textColor = session.needsAction ? theme.colors.message : theme.colors.messageDim
        messageLabel.speed = theme.layout.marqueeSpeed
        messageLabel.isEnabled = theme.layout.marqueeOnOverflow
        messageLabel.text = summary(for: session)

        dot.color = theme.colors.color(for: session.state)
        dot.isProminent = session.needsAction

        avatar.isHidden = theme.avatar.isHidden
        if !avatar.isHidden {
            avatar.configure(
                asset: theme.avatar.asset(for: session.state),
                state: session.state,
                tint: theme.colors.color(for: session.state),
                cornerRadius: theme.avatar.cornerRadius
            )
        }

        disclosure.isHidden = !session.isGroup
        disclosure.attributedTitle = triangle(expanded: isExpanded, color: theme.colors.messageDim)

        toolTip = session.cwd
        needsDisplay = true
        needsLayout = true
    }

    private func summary(for session: Session) -> String {
        guard session.isGroup else { return session.message }
        let count = session.children.count
        let suffix = count == 1 ? "1 subagent" : "\(count) subagents"
        return session.message.isEmpty ? suffix : "\(session.message)  ·  \(suffix)"
    }

    private func triangle(expanded: Bool, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: expanded ? "▼" : "▶",
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 8)]
        )
    }

    // MARK: - Layout

    /// Two-line rows read better, but compact themes get one line. A theme with
    /// avatars needs room for the face too — whichever is taller wins, still
    /// capped by `rowMaxHeight`.
    static func height(for theme: Theme) -> CGFloat {
        let padding = theme.layout.rowPadding
        let lines = theme.layout.isCompact
            ? theme.typography.nameSize + 6
            : theme.typography.nameSize + theme.typography.messageSize + 10
        let content = max(lines, theme.avatar.isHidden ? 0 : theme.avatar.size)
        return min(theme.layout.rowMaxHeight, content + padding * 2)
    }

    override func layout() {
        super.layout()
        let padding = theme.layout.rowPadding
        let dotSize: CGFloat = 10
        let disclosureWidth: CGFloat = isGroup ? 14 : 0

        // Never let a large avatar spill out of a capped row.
        let avatarSide = avatar.isHidden
            ? 0
            : min(theme.avatar.size, bounds.height - padding * 2)
        let avatarSpan = avatarSide > 0 ? avatarSide + 8 : 0
        let onLeft = theme.avatar.position == .left

        if avatarSide > 0 {
            avatar.frame = NSRect(
                x: onLeft ? padding : bounds.width - padding - avatarSide,
                y: (bounds.height - avatarSide) / 2,
                width: avatarSide,
                height: avatarSide
            )
        }

        let leadingInset = padding + (onLeft ? avatarSpan : 0)
        disclosure.frame = NSRect(
            x: leadingInset,
            y: (bounds.height - 14) / 2,
            width: disclosureWidth,
            height: 14
        )

        let dotX = leadingInset + disclosureWidth + (isGroup ? 4 : 0)
        dot.frame = NSRect(x: dotX, y: (bounds.height - dotSize) / 2, width: dotSize, height: dotSize)

        let textX = dot.frame.maxX + 8
        let trailingInset = padding + (onLeft ? 0 : avatarSpan)
        let textWidth = max(0, bounds.width - textX - trailingInset)

        let nameHeight = theme.typography.nameSize + 4
        let messageHeight = theme.typography.messageSize + 4

        if theme.layout.isCompact {
            let nameWidth = min(textWidth * 0.4, nameLabel.intrinsicContentSize.width)
            nameLabel.frame = NSRect(
                x: textX,
                y: (bounds.height - nameHeight) / 2,
                width: nameWidth,
                height: nameHeight
            )
            messageLabel.frame = NSRect(
                x: nameLabel.frame.maxX + 8,
                y: 0,
                width: max(0, textWidth - nameWidth - 8),
                height: bounds.height
            )
        } else {
            let top = (bounds.height - (nameHeight + messageHeight + 2)) / 2
            nameLabel.frame = NSRect(x: textX, y: top, width: textWidth, height: nameHeight)
            messageLabel.frame = NSRect(
                x: textX,
                y: top + nameHeight + 2,
                width: textWidth,
                height: messageHeight
            )
        }
    }

    // MARK: - Drawing & interaction

    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor
        if isHovering {
            background = theme.colors.rowBackgroundHover
        } else {
            background = useAlternateBackground ? theme.colors.rowBackgroundAlt : theme.colors.rowBackground
        }
        background.setFill()
        bounds.fill()

        theme.colors.divider.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 0, y: bounds.maxY - 0.5))
        line.line(to: NSPoint(x: bounds.width, y: bounds.maxY - 0.5))
        line.stroke()
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
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isGroup && disclosure.frame.insetBy(dx: -4, dy: -4).contains(point) {
            onToggleChildren?()
            return
        }
        onActivate?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick?(event)
    }

    @objc private func toggleChildren() {
        onToggleChildren?()
    }
}
