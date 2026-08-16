// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The themed title strip, replacing the stock macOS titlebar.
///
/// It is also the drag handle: the panel is borderless-by-appearance, so this
/// is what you grab to move it.
final class TitleBarView: NSView {
    static let height: CGFloat = 64
    /// Without the analyser only the title row is left, so the strip closes up
    /// rather than leaving a band of empty theme where the bars used to be.
    static let compactHeight: CGFloat = 30
    /// Where a corner mark sits, so the resize handle can mirror the close
    /// mark exactly rather than approximating it.
    static let markInset: CGFloat = 8
    static let markTop: CGFloat = 7

    private let titleLabel = NSTextField(labelWithString: "Ground Control")
    private let visualizer = VisualizerView()
    private let mark = NSImageView()
    private var theme: Theme = DefaultTheme.theme
    private var trackingArea: NSTrackingArea?
    private let preferences: Preferences

    /// What this strip needs, which the panel asks for rather than assuming.
    var preferredHeight: CGFloat {
        preferences.showsAnalyser ? Self.height : Self.compactHeight
    }

    override var isFlipped: Bool { true }

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        super.init(frame: .zero)
        wantsLayer = true

        titleLabel.lineBreakMode = .byTruncatingTail

        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.image = Brand.glyph
        addSubview(mark)
        addSubview(titleLabel)
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

        // A theme may supply its own mark; otherwise ours.
        if let custom = theme.backgrounds.brandMark, let image = NSImage(contentsOf: custom) {
            mark.image = image
        } else {
            mark.image = Brand.glyph
        }
        visualizer.apply(theme: theme)
        // Taken out of the hierarchy rather than hidden: the analyser stops
        // its 24fps timer and its message countdown when it loses its window,
        // so leaving is how it switches off completely.
        if preferences.showsAnalyser {
            if visualizer.superview == nil { addSubview(visualizer) }
        } else {
            visualizer.removeFromSuperview()
        }
        needsLayout = true
        needsDisplay = true
    }

    /// The session count used to live at the right end; the resize mark has it
    /// now. Nothing was lost that the panel does not already say: the rows are
    /// the count, each carries its own dot, and the analyser goes to its alarm
    /// colour the moment anything needs you.
    func update(sessions: [Session]) {
        // Switched off means switched off: the analyser runs a 24fps timer and
        // a message scheduler, and a monitor someone asked to sit still should
        // not be waking the CPU to animate something nobody can see.
        guard preferences.showsAnalyser else { return }
        visualizer.update(sessions: sessions)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        let titleRow: CGFloat = 22

        // The close mark is drawn by the panel, above any skin, but its place
        // in the row is still reserved here so the two agree.
        let markSide: CGFloat = 15
        mark.frame = NSRect(
            x: Self.markInset + CloseMarkView.size.width + 7,
            y: (titleRow - markSide) / 2 + 4,
            width: markSide,
            height: markSide
        )
        let textY = (titleRow - 14) / 2 + 4
        // Stops short of the resize mark at the far end.
        titleLabel.frame = NSRect(
            x: mark.frame.maxX + 6,
            y: textY,
            width: max(0, bounds.width - mark.frame.maxX - 6 - Self.markInset - 24),
            height: 14
        )

        guard visualizer.superview != nil else { return }
        visualizer.frame = NSRect(
            x: inset,
            y: titleRow + 6,
            width: bounds.width - inset * 2,
            height: max(0, bounds.height - titleRow - 12)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.colors.titleBarBackground.setFill()
        bounds.fill(using: .sourceOver)

        if let background = theme.backgrounds.titleBar {
            BackgroundRenderer.draw(background, in: bounds)
        }

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
        NSCursor.openHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    /// Dragging anywhere on the strip moves the window.
    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
