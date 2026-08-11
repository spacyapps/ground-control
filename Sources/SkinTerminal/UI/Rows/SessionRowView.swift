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
    private let sourceTag = NSTextField(labelWithString: "")
    private let elapsedLabel = NSTextField(labelWithString: "")

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
        addSubview(sourceTag)
        addSubview(elapsedLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SessionRowView is created in code only")
    }

    // MARK: - Content

    /// Everything about how a row is shown, as opposed to what it shows.
    struct Presentation {
        let theme: Theme
        let renames: [String: String]
        let isExpanded: Bool
        let isAlternate: Bool
        let showsSource: Bool
    }

    func configure(session: Session, presentation: Presentation) {
        let theme = presentation.theme
        let renames = presentation.renames
        self.theme = theme
        self.isGroup = session.isGroup
        self.isExpanded = presentation.isExpanded
        self.useAlternateBackground = presentation.isAlternate

        nameLabel.stringValue = session.displayName(renames: renames)
        nameLabel.font = theme.typography.nameFont()
        nameLabel.textColor = theme.colors.sessionName

        elapsedLabel.stringValue = ElapsedFormatter.short(since: session.lastActivity)
        elapsedLabel.font = .systemFont(ofSize: max(8, theme.typography.messageSize - 2))
        elapsedLabel.alignment = .right
        elapsedLabel.textColor = session.needsAction
            ? theme.colors.needsAction
            : theme.colors.messageDim.withAlphaComponent(0.8)

        // Only worth the pixels when more than one CLI is on screen.
        sourceTag.isHidden = !presentation.showsSource
        sourceTag.stringValue = session.source.uppercased()
        sourceTag.font = .systemFont(ofSize: max(7, theme.typography.messageSize - 3), weight: .bold)
        sourceTag.textColor = theme.colors.messageDim.withAlphaComponent(0.75)

        messageLabel.font = theme.typography.messageFont()
        messageLabel.textColor = session.needsAction ? theme.colors.message : theme.colors.messageDim
        messageLabel.speed = theme.layout.marqueeSpeed
        messageLabel.isEnabled = theme.layout.marqueeOnOverflow
        messageLabel.text = summary(for: session)

        dot.color = theme.colors.color(for: session.state)
        dot.isProminent = session.needsAction
        dot.badge = theme.backgrounds.needsActionDot

        avatar.isHidden = theme.avatar.isHidden
        if !avatar.isHidden {
            avatar.configure(
                asset: theme.avatar.asset(for: session.state),
                state: session.state,
                theme: theme
            )
        }

        disclosure.isHidden = !session.isGroup
        disclosure.attributedTitle = triangle(
            expanded: presentation.isExpanded,
            color: theme.colors.messageDim
        )

        toolTip = session.cwd
        needsDisplay = true
        needsLayout = true
    }

    /// Updates only the clock. Rebuilding the row instead would restart its
    /// marquee and drop hover state every few seconds.
    func refreshElapsed(for session: Session) {
        elapsedLabel.stringValue = ElapsedFormatter.short(since: session.lastActivity)
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

        layoutText(textX: textX, textWidth: textWidth, trailingInset: trailingInset)
    }

    private func layoutText(textX: CGFloat, textWidth: CGFloat, trailingInset: CGFloat) {
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
            let tagWidth = sourceTag.isHidden ? 0 : sourceTag.intrinsicContentSize.width + 8
            let elapsedWidth = elapsedLabel.intrinsicContentSize.width + 8
            nameLabel.frame = NSRect(
                x: textX,
                y: top,
                width: max(0, textWidth - tagWidth - elapsedWidth),
                height: nameHeight
            )
            sourceTag.frame = NSRect(
                x: bounds.width - trailingInset - tagWidth - elapsedWidth + 8,
                y: top + 2,
                width: max(0, tagWidth - 8),
                height: nameHeight - 2
            )
            // Elapsed time sits furthest right on the name line, where the eye
            // lands last: you read what, then who, then how long.
            elapsedLabel.frame = NSRect(
                x: bounds.width - trailingInset - elapsedWidth,
                y: top + 1,
                width: max(0, elapsedWidth - 4),
                height: nameHeight - 1
            )
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

    // Pushed imperatively rather than via cursorUpdate: this panel never
    // becomes key, and AppKit only runs cursor updates for the key window.
    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.pointingHand.push()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.pop()
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
