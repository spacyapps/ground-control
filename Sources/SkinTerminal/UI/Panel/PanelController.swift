import AppKit

/// Owns the panel: show/hide, window behaviour toggles, and frame persistence.
final class PanelController {
    private(set) var panel: FloatingPanel?
    private let chrome = PanelBackgroundView()
    private let preferences: Preferences

    var onActivate: ((Session) -> Void)?
    var onSecondaryClick: ((Session, NSEvent) -> Void)?

    private var theme: Theme = DefaultTheme.theme
    private var frameObserver: NSObjectProtocol?

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        chrome.list.onActivate = { [weak self] session in self?.onActivate?(session) }
        chrome.list.onSecondaryClick = { [weak self] session, event in
            self?.onSecondaryClick?(session, event)
        }
        chrome.titleBar.onClose = { [weak self] in self?.hide() }
    }

    deinit {
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = existingOrNewPanel()
        applyWindowBehaviour()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func apply(theme: Theme) {
        self.theme = theme
        chrome.apply(theme: theme)
    }

    func apply(sessions: [Session]) {
        chrome.update(sessions: sessions, renames: preferences.renames)
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
            panel.setFrame(NSRectFromString(saved), display: false)
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
