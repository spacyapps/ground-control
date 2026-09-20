// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

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
    /// Reports what the pointer is over, so the panel can draw a hint for it.
    /// Nil means "nothing worth explaining here".
    var onHint: ((String?, NSRect) -> Void)?

    private let dot = StatusDotView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let messageLabel = MarqueeLabel()
    let disclosure = NSButton()
    private let avatar = AvatarView()
    /// For the hint, which lives in its own file and only needs to know where
    /// the avatar is when it is on screen at all.
    var avatarFrameIfVisible: NSRect? { avatar.isHidden ? nil : avatar.frame }
    private let sourceTag = NSTextField(labelWithString: "")
    private let elapsedLabel = NSTextField(labelWithString: "")

    /// Not private: the menu mark draws itself from the same palette, from
    /// its own file.
    var theme: Theme = DefaultTheme.theme
    /// Not private: the menu mark, in its own file, dims itself when the
    /// pointer is elsewhere in the row.
    var isHovering = false
    var isGroup = false
    private var isExpanded = false
    private var useAlternateBackground = false
    var trackingArea: NSTrackingArea?

    /// Where the menu mark sits, filled in during layout so the click test and
    /// the drawing cannot disagree about it.
    var menuRect: NSRect = .zero
    /// Tracked separately from the row's own hover: the mark should light up
    /// when the pointer is on *it*, the way the avatar button does, not
    /// whenever the pointer is anywhere in the row.
    var isMenuHovered = false
    /// What clicking the avatar will actually do — the app it will raise, which
    /// the row is told because only the coordinator can work it out.
    var jumpHint: String?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.isOpaque = false

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
        let showsHost: Bool
    }

    func configure(session: Session, presentation: Presentation) {
        let theme = presentation.theme
        let renames = presentation.renames
        self.theme = theme
        self.isGroup = session.isGroup
        self.isExpanded = presentation.isExpanded
        self.useAlternateBackground = presentation.isAlternate

        // "Claude → xcode", not a second row also called "xcode" — but not
        // "Grok Bot → Grok Bot" where the host is the name.
        let name = session.displayName(renames: renames)
        let host = presentation.showsHost ? session.hostName : nil
        nameLabel.stringValue = host != nil && host != name ? "\(host ?? "") → \(name)" : name
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

        // A dismissed alarm has to look dismissed. The state is still
        // needsInput — the agent really is waiting — so the face stays, but
        // the row goes quiet: dimmed, and wearing the idle colour rather than
        // a red that no longer means "deal with me".
        let seen = session.isDismissedAlarm
        dot.color = seen ? theme.colors.idle : theme.colors.color(for: session.state)
        dot.altColor = theme.colors.color(for: .done)
        dot.isProminent = session.needsAction
        dot.badge = theme.backgrounds.needsActionDot
        dot.mark = .forSource(session.source, state: session.state)
        avatar.alphaValue = seen ? 0.4 : 1
        nameLabel.alphaValue = seen ? 0.55 : 1

        avatar.isHidden = theme.avatar.isHidden
        if !avatar.isHidden {
            // A *quiet* Grok Bot row can't say which state it is in, so its
            // face is split idle | done — the same admission the dot makes.
            // A working one can, and wears the theme's working face like any
            // other row: the mood is what carries across the panel, where a
            // dot two millimetres wide does not.
            if StatusDotView.Mark.forSource(session.source, state: session.state) == .unknown,
               !session.needsAction {
                avatar.configureSplit(left: .idle, right: .done, theme: theme)
            } else {
                avatar.configure(
                    asset: theme.avatar.asset(for: session.state),
                    state: session.state,
                    theme: theme
                )
            }
        }

        disclosure.isHidden = !session.isGroup
        disclosure.attributedTitle = triangle(
            expanded: presentation.isExpanded,
            color: theme.colors.messageDim
        )

        needsDisplay = true
        needsLayout = true
    }

    /// Updates only the clock. Rebuilding the row instead would restart its
    /// marquee and drop hover state every few seconds.
    func refreshElapsed(for session: Session) {
        elapsedLabel.stringValue = ElapsedFormatter.short(since: session.lastActivity)
        avatar.tickSplitSeam()
        needsLayout = true
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

        // Above the dot, sharing its column: the row's own affordances stay in
        // one line down the leading edge. Right-click still works — this is the
        // visible way in, not a replacement.
        //
        // The gap allows for the tile drawn around it: without that, the tile's
        // lower edge sat against the status dot and the two read as one object.
        let markSide: CGFloat = 12
        menuRect = NSRect(
            x: dot.frame.midX - markSide / 2,
            y: max(6, dot.frame.minY - markSide - 9),
            width: markSide,
            height: markSide
        )

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

    /// Rounded-card radius for a row that floats free under `bodyFade`.
    static let floatingCornerRadius: CGFloat = 7

    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor
        if isHovering {
            background = theme.colors.rowBackgroundHover
        } else {
            background = useAlternateBackground ? theme.colors.rowBackgroundAlt : theme.colors.rowBackground
        }
        background.setFill()

        // Under `bodyFade` the rows are separate cards over the frame, so each
        // one paints a rounded rect with a hairline gap and no divider. Behind
        // the analyser they are still a contiguous block: full-bleed fill,
        // divider between.
        if theme.window.bodyFadesBelowAnalyser {
            let card = bounds.insetBy(dx: 0, dy: 1)
            NSBezierPath(
                roundedRect: card,
                xRadius: Self.floatingCornerRadius,
                yRadius: Self.floatingCornerRadius
            ).fill()
        } else {
            // sourceOver, not the default: a row colour carrying alpha has to
            // blend over the panel's background image rather than replace it.
            bounds.fill(using: .sourceOver)

            theme.colors.divider.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: bounds.maxY - 0.5))
            line.line(to: NSPoint(x: bounds.width, y: bounds.maxY - 0.5))
            line.stroke()
        }

        drawMenuMark()
    }

    @objc private func toggleChildren() {
        onToggleChildren?()
    }
}
