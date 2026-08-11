// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Rows must fill from the top. An `NSScrollView`'s document view is
/// bottom-origin by default, which pins a short list to the bottom of the
/// panel and leaves a void above it.
private final class TopAlignedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// The other half of the fix: a clip view shorter than its content still
/// anchors at the bottom unless it, too, is flipped.
private final class TopAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// The scrolling stack of rows.
///
/// Rebuilt wholesale on every change. With a handful of sessions this is
/// cheaper than diffing and keeps the file ⇔ row invariant obvious: what is on
/// screen is exactly what the store last produced.
final class SessionListView: NSView {
    var onActivate: ((Session) -> Void)?
    var onSecondaryClick: ((Session, NSEvent) -> Void)?

    private let scrollView = NSScrollView()
    private let stack = TopAlignedStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let emptyMark = NSImageView()

    private var theme: Theme = DefaultTheme.theme
    private var sessions: [Session] = []
    private var renames: [String: String] = [:]
    private var expanded: Set<String> = []

    /// Total height of every row currently laid out, so the panel can size
    /// itself to its content instead of clipping the last row.
    private(set) var contentHeight: CGFloat = 0

    /// Kept so elapsed times can tick without rebuilding the list.
    private var rowViews: [(session: Session, view: SessionRowView)] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView = TopAlignedClipView()
        scrollView.documentView = stack
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        emptyMark.imageScaling = .scaleProportionallyUpOrDown
        emptyMark.image = Brand.lockup
        emptyMark.alphaValue = 0.5
        emptyMark.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(emptyMark)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            emptyMark.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyMark.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -6),
            emptyMark.widthAnchor.constraint(equalToConstant: 168),
            emptyMark.heightAnchor.constraint(equalToConstant: 46),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: emptyMark.bottomAnchor, constant: 10),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SessionListView is created in code only")
    }

    func apply(theme: Theme) {
        self.theme = theme
        rebuild()
    }

    func apply(sessions: [Session], renames: [String: String]) {
        self.sessions = sessions
        self.renames = renames
        // Drop expansion state for sessions that are gone.
        expanded = expanded.filter { id in sessions.contains { $0.id == id } }
        rebuild()
    }

    private func rebuild() {
        // Deliberately transparent: PanelBackgroundView has already painted the
        // window colour and any background image, and an opaque layer here
        // would hide the artwork entirely.
        layer?.backgroundColor = NSColor.clear.cgColor

        emptyLabel.isHidden = !sessions.isEmpty
        emptyMark.isHidden = !sessions.isEmpty
        emptyLabel.stringValue = "No active sessions.\nStart an agent CLI in a terminal and a row appears here."
        emptyLabel.font = theme.typography.messageFont()
        emptyLabel.textColor = theme.colors.messageDim
        emptyLabel.maximumNumberOfLines = 2

        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // A single-CLI user never sees a source tag; two or more and every row
        // gets one, so the comparison is obvious rather than implied.
        let showsSource = Set(sessions.map(\.source)).count > 1
        let rowHeight = SessionRowView.height(for: theme)
        let childHeight = GroupRowView.height(for: theme)
        var total: CGFloat = 0
        rowViews.removeAll()

        for (index, session) in sessions.enumerated() {
            let row = SessionRowView()
            row.configure(session: session, presentation: SessionRowView.Presentation(
                theme: theme,
                renames: renames,
                isExpanded: expanded.contains(session.id),
                isAlternate: index.isMultiple(of: 2),
                showsSource: showsSource
            ))
            row.onActivate = { [weak self] in self?.onActivate?(session) }
            row.onSecondaryClick = { [weak self] event in self?.onSecondaryClick?(session, event) }
            row.onToggleChildren = { [weak self] in self?.toggleExpansion(of: session.id) }
            add(row, height: rowHeight)
            rowViews.append((session, row))
            total += rowHeight

            guard expanded.contains(session.id) else { continue }
            for child in session.children {
                total += childHeight
                let childRow = GroupRowView()
                childRow.configure(child: child, theme: theme)
                // A child jumps to the orchestrator's terminal — same tty.
                childRow.onActivate = { [weak self] in self?.onActivate?(session) }
                add(childRow, height: childHeight)
            }
        }
        contentHeight = total
    }

    /// Ticks the clocks. Nothing else about a row changes without an event.
    func refreshElapsed() {
        for pair in rowViews {
            pair.view.refreshElapsed(for: pair.session)
        }
    }

    private func add(_ view: NSView, height: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: height),
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }

    private func toggleExpansion(of sessionID: String) {
        if expanded.contains(sessionID) {
            expanded.remove(sessionID)
        } else {
            expanded.insert(sessionID)
        }
        rebuild()
    }
}
