// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import AppKit

/// The panel's themed content: title bar and session list.
///
/// Owns the whole surface so the theme reaches the window's edges — macOS
/// chrome is switched off in `FloatingPanel`, and this is what replaces it.
final class PanelBackgroundView: NSView {
    let titleBar = TitleBarView()
    let list = SessionListView()

    private var theme: Theme = DefaultTheme.theme

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        addSubview(titleBar)
        addSubview(list)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PanelBackgroundView is created in code only")
    }

    func apply(theme: Theme) {
        self.theme = theme
        layer?.backgroundColor = theme.colors.windowBackground.cgColor
        titleBar.apply(theme: theme)
        list.apply(theme: theme)
        needsDisplay = true
    }

    /// Height at which nothing is clipped: title strip plus every row.
    var desiredHeight: CGFloat {
        TitleBarView.height + list.contentHeight
    }

    func refreshElapsed() {
        list.refreshElapsed()
    }

    func update(sessions: [Session], renames: [String: String]) {
        titleBar.update(sessions: sessions)
        list.apply(sessions: sessions, renames: renames)
    }

    override func layout() {
        super.layout()
        titleBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: TitleBarView.height)
        list.frame = NSRect(
            x: 0,
            y: titleBar.frame.maxY,
            width: bounds.width,
            height: max(0, bounds.height - TitleBarView.height)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        // The colour is painted first regardless: a background image with
        // transparency composites onto it rather than onto nothing.
        theme.colors.windowBackground.setFill()
        bounds.fill()

        if let background = theme.backgrounds.window {
            BackgroundRenderer.draw(background, in: bounds)
        }
    }
}
