// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Owns the panel: show/hide, window behaviour toggles, and frame persistence.
final class PanelController {
    private(set) var panel: FloatingPanel?
    private let chrome = PanelBackgroundView()
    private let preferences: Preferences

    var onActivate: ((Session) -> Void)?
    var onSecondaryClick: ((Session, NSEvent) -> Void)?

    private var theme: Theme = DefaultTheme.theme
    private var resizeStart: CGSize = .zero
    private var frameObserver: NSObjectProtocol?
    private var elapsedTimer: Timer?

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        chrome.list.onActivate = { [weak self] session in self?.onActivate?(session) }
        chrome.list.onSecondaryClick = { [weak self] session, event in
            self?.onSecondaryClick?(session, event)
        }
        chrome.closeMark.onClose = { [weak self] in self?.hide() }
        chrome.resizeGrip.onResizeBegan = { [weak self] in
            self?.resizeStart = self?.panel?.frame.size ?? .zero
        }
        chrome.resizeGrip.onResize = { [weak self] delta in self?.resize(by: delta) }
    }

    deinit {
        elapsedTimer?.invalidate()
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
    }

    /// Elapsed times advance with the clock, not with events, so they need
    /// their own tick. Five seconds keeps the sub-minute readout honest
    /// without redrawing anything that has not changed.
    private func startElapsedTicking() {
        guard elapsedTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.chrome.refreshElapsed()
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = existingOrNewPanel()
        applyWindowBehaviour()
        panel.orderFrontRegardless()
        fitHeightToContent()
        startElapsedTicking()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func apply(theme: Theme) {
        self.theme = theme
        panel?.apply(shaped: theme.window.isShaped)
        chrome.apply(theme: theme)
        panel?.invalidateShadow()
    }

    func apply(sessions: [Session]) {
        chrome.update(sessions: sessions, renames: preferences.renames)
        fitHeightToContent()
    }

    /// Grow and shrink to the rows rather than clipping the last one.
    ///
    /// A monitor with five sessions should show five sessions. The width and
    /// position stay yours; only the height is derived — and it stops at a
    /// fraction of the screen, after which the list scrolls instead of the
    /// panel eating the display.
    func fitHeightToContent() {
        guard let panel, panel.isVisible else { return }

        // Free: the height is the person's, and nothing here may take it back.
        // Any derivation would fight them a frame after every drag.
        if theme.layout.resize == .free { return }

        // A skin with its aspect locked is a designed object, not a container:
        // width is yours to drag, height follows the artwork, and the rows
        // scroll inside rather than stretching it out of shape.
        if theme.layout.resize == .aspect, theme.window.isShaped {
            let ratio = max(0.05, theme.window.aspectRatio)
            let target = (panel.frame.width / ratio).rounded()
            guard abs(panel.frame.height - target) > 0.5 else { return }

            var frame = panel.frame
            let top = frame.maxY
            frame.size.height = target
            frame.origin.y = top - target
            panel.setFrame(frame, display: true, animate: false)
            return
        }
        let screen = panel.screen ?? NSScreen.main
        let ceiling = (screen?.visibleFrame.height ?? 900) * 0.75
        let target = min(max(panel.minSize.height, chrome.desiredHeight), ceiling)

        var frame = panel.frame
        guard abs(frame.height - target) > 0.5 else { return }

        // Keep the top edge pinned: AppKit measures from the bottom, so the
        // origin has to move as the height changes or the panel grows upward.
        let top = frame.maxY
        frame.size.height = target
        frame.origin.y = top - target
        panel.setFrame(frame, display: true, animate: false)
    }

    /// Drags the panel wider or narrower from its own grip.
    ///
    /// The left edge and the top stay put, so the panel grows into empty space
    /// rather than walking across the screen. Height is left to
    /// `fitHeightToContent`, which knows whether it follows the rows or the
    /// artwork.
    private func resize(by delta: CGSize) {
        guard let panel else { return }

        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let width = min(
            max(panel.minSize.width, resizeStart.width + delta.width),
            visible.width > 0 ? visible.width : 1600
        )
        // Vertical drag only means anything where the height is not derived,
        // and the grip only offers it there.
        let height = theme.layout.resize == .free
            ? min(
                max(panel.minSize.height, resizeStart.height + delta.height),
                visible.height > 0 ? visible.height : 900
            )
            : panel.frame.height

        var frame = panel.frame
        guard abs(frame.width - width) > 0.5 || abs(frame.height - height) > 0.5 else { return }

        // The top edge stays put: AppKit measures from the bottom, so growing
        // downward means moving the origin as the height changes.
        let top = frame.maxY
        frame.size.width = width
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true, animate: false)
        fitHeightToContent()
    }

    /// Recovers a panel dragged off-screen or onto a display that is gone.
    func resetPosition() {
        let frame = defaultFrame()
        panel?.setFrame(frame, display: true)
        preferences.panelFrame = NSStringFromRect(frame)
        show()
    }

    func applyWindowBehaviour() {
        panel?.apply(
            alwaysOnTop: preferences.alwaysOnTop,
            showOnAllSpaces: preferences.showOnAllSpaces
        )
    }

    // MARK: - Panel lifecycle

    private func existingOrNewPanel() -> FloatingPanel {
        if let panel { return panel }

        let panel = FloatingPanel(contentRect: defaultFrame())
        panel.contentView = chrome
        if let saved = preferences.panelFrame {
            var frame = NSRectFromString(saved)
            // A derived height would only fight fitHeightToContent on the first
            // paint — but a height the person chose has to survive a relaunch,
            // or "free" means free until you quit.
            if theme.layout.resize != .free {
                frame.size.height = panel.frame.height
            }
            panel.setFrame(frame, display: false)
        }

        frameObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in self?.saveFrame() }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in self?.saveFrame() }

        self.panel = panel
        chrome.apply(theme: theme)
        return panel
    }

    private func saveFrame() {
        guard let panel else { return }
        preferences.panelFrame = NSStringFromRect(panel.frame)
    }

    /// Top-right of the main screen, out of the way of a centred terminal.
    private func defaultFrame() -> NSRect {
        let size = NSSize(width: 320, height: 380)
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )
    }
}
