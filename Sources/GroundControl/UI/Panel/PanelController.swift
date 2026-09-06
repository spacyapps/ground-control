// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Owns the panel: show/hide, window behaviour toggles, and frame persistence.
final class PanelController {
    private(set) var panel: FloatingPanel?
    private let root = PanelRootView()
    private var chrome: PanelBackgroundView { root.chrome }
    private let preferences: Preferences

    var onActivate: ((Session) -> Void)?
    var onSecondaryClick: ((Session, NSEvent) -> Void)?

    private var theme: Theme = DefaultTheme.theme
    private var resizeStart: CGSize = .zero
    private var frameObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var elapsedTimer: Timer?
    private var hasAppeared = false

    /// The user's own show/hide intent, kept apart from `panel.isVisible`
    /// because the panel also hides itself while another app is full-screen
    /// (unless "always on top" is on) and restores when that ends.
    private var wantsToBeVisible = false
    private var autoHiddenForFullscreen = false

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        chrome.list.onActivate = { [weak self] session in self?.onActivate?(session) }
        chrome.list.onSecondaryClick = { [weak self] session, event in
            self?.onSecondaryClick?(session, event)
        }
        // Expanding a group changes the content height with no session update
        // and no drag: refit the panel, then redo the body behind the rows now
        // that the rows have their new positions.
        chrome.list.onContentHeightChange = { [weak self] in
            guard let self else { return }
            self.fitHeightToContent()
            self.chrome.refreshInteriorBody()
        }
        root.closeMark.onClose = { [weak self] in self?.hide() }
        root.resizeGrip.onResizeBegan = { [weak self] in
            self?.resizeStart = self?.panel?.frame.size ?? .zero
        }
        root.resizeGrip.onResize = { [weak self] delta in self?.resize(by: delta) }
    }

    deinit {
        elapsedTimer?.invalidate()
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
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

    /// Visible *to the user*: ordered in, and not blanked for a full-screen app.
    var isVisible: Bool { (panel?.isVisible ?? false) && !autoHiddenForFullscreen }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = existingOrNewPanel()
        wantsToBeVisible = true
        // An explicit "show" wins over the full-screen auto-hide until the next
        // Spaces change re-evaluates — so clicking it from the menu while
        // full-screen actually shows it.
        autoHiddenForFullscreen = false
        panel.alphaValue = 1
        panel.apply(
            alwaysOnTop: preferences.alwaysOnTop,
            showOnAllSpaces: preferences.showOnAllSpaces
        )
        panel.orderFrontRegardless()
        // First appearance after launch is fitted like a theme switch: the
        // saved frame's height can be from a different skin, and a `free`
        // panel would otherwise open squished under a tall frame — with the
        // resize grip that fixes it lost somewhere in the artwork.
        fitHeightToContent(afterThemeChange: !hasAppeared)
        hasAppeared = true
        startElapsedTicking()
    }

    func hide() {
        wantsToBeVisible = false
        autoHiddenForFullscreen = false
        panel?.orderOut(nil)
    }

    /// Get out of the way of a full-screen app.
    ///
    /// "Always on top" is the opt-out: with it on the panel is meant to float
    /// over everything, full-screen included. Otherwise, when another app takes
    /// a full-screen space the panel blanks itself and comes back when that
    /// space is left — but only if the user had it open.
    ///
    /// It goes to `alphaValue = 0` rather than `orderOut`: a window returned
    /// from `orderOut` is only placed on the active Space, not every Space, so
    /// ordering out here broke "show on all Spaces" for good. Invisible-but-
    /// present keeps the Space membership intact, and the panel never takes a
    /// click anyway (`hitTest` returns nil).
    ///
    /// AppKit has no notification for a Space becoming full-screen, so this is
    /// re-checked on every Spaces change, slightly delayed because the
    /// full-screen window is not at its final size the instant that fires.
    private func evaluateFullscreenAutoHide() {
        guard let panel, wantsToBeVisible else { return }

        let hideForFullscreen = !preferences.alwaysOnTop && Self.anotherAppIsFullscreen()
        guard hideForFullscreen != autoHiddenForFullscreen else { return }

        autoHiddenForFullscreen = hideForFullscreen
        panel.alphaValue = hideForFullscreen ? 0 : 1
        if !hideForFullscreen { panel.orderFrontRegardless() }
    }

    /// Whether another app currently holds a full-screen space on any display.
    ///
    /// AppKit has no notification or property for this, so it is read from the
    /// window list. A full-screen app decomposes into several windows (a tab
    /// strip, the content, a bar over the menu-bar area), so no single window
    /// matches the display — but their **union** covers it corner to corner,
    /// reaching `y = 0` over the space the menu bar occupies. A merely zoomed
    /// or tiled window stops below the menu bar and above the Dock, so its
    /// union never touches the top edge.
    private static func anotherAppIsFullscreen() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return false }

        let ourPID = Int(getpid())
        let systemOwners: Set<String> = [
            "Window Server", "Dock", "WindowManager", "Control Center",
            "SystemUIServer", "Spotlight", "Notification Center",
        ]

        var coverage: [Int: CGRect] = [:]
        for window in list {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int, pid != ourPID,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  !systemOwners.contains(owner),
                  // The desktop sits at a deeply negative layer; a full-screen
                  // app's own bar over the menu-bar area is a small positive
                  // one. Only real window layers count.
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 40, height > 20 else { continue }
            let rect = CGRect(x: x, y: y, width: width, height: height)
            coverage[pid] = coverage[pid].map { $0.union(rect) } ?? rect
        }

        for screen in NSScreen.screens {
            let width = screen.frame.width, height = screen.frame.height
            for box in coverage.values
            where box.minX <= 2 && box.minY <= 2 && box.maxX >= width - 2 && box.maxY >= height - 2 {
                return true
            }
        }
        return false
    }

    func apply(theme: Theme) {
        self.theme = theme
        panel?.apply(shaped: theme.window.isShaped)
        panel?.enforce(minimum: theme.window.minimumPanelSize)
        root.apply(theme: theme)
        panel?.invalidateShadow()
        // Themes disagree about what the panel's size means — one derives the
        // height from its artwork, the next from the rows, a third leaves it to
        // you. Without this, a theme was drawn at whatever size the *previous*
        // one had settled on, and looked wrong through no fault of its own.
        fitHeightToContent(afterThemeChange: true)
    }

    func apply(sessions: [Session]) {
        root.update(sessions: sessions, renames: preferences.renames)
        fitHeightToContent()
    }

    /// Grow and shrink to the rows rather than clipping the last one.
    ///
    /// A monitor with five sessions should show five sessions. The width and
    /// position stay yours; only the height is derived — and it stops at a
    /// fraction of the screen, after which the list scrolls instead of the
    /// panel eating the display.
    ///
    /// `afterThemeChange` is when a `free` panel is also fitted: a theme switch
    /// — or the first appearance after launch — should land the skin near its
    /// own content, not at whatever height the last skin was dragged to. Every
    /// resize after that is the person's again.
    func fitHeightToContent(afterThemeChange: Bool = false) {
        guard let panel, panel.isVisible else { return }

        // Free: the height is the person's, and nothing here may take it back —
        // save for a theme switch or the first launch, which start fresh. Any
        // other derivation would fight them a frame after every drag.
        if theme.layout.resize == .free, !afterThemeChange { return }

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
        // Turning "always on top" on mid-full-screen should bring the panel
        // straight back; turning it off in full-screen should send it away.
        evaluateFullscreenAutoHide()
    }

    // MARK: - Panel lifecycle

    private func existingOrNewPanel() -> FloatingPanel {
        if let panel { return panel }

        let panel = FloatingPanel(contentRect: defaultFrame())
        panel.contentView = root
        if let saved = preferences.panelFrame {
            var frame = NSRectFromString(saved)
            // Width and position are restored; the height is not — `show()`
            // refits it to the current theme on first appearance, since the
            // saved one can belong to a skin that is no longer active. A
            // non-free theme never keeps a saved height at all.
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

        // A full-screen space is its own Space, so entering or leaving one
        // fires this. The re-check is delayed: the full-screen window is not
        // yet at its final size the instant the notification lands.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.evaluateFullscreenAutoHide()
            }
        }
        // No Spaces change fires if the app launches already inside a
        // full-screen space, so seed the check once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.evaluateFullscreenAutoHide()
        }

        self.panel = panel
        root.apply(theme: theme)
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
