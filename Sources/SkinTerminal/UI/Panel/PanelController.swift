import AppKit

/// Owns the panel: show/hide, window behaviour toggles, and frame persistence.
final class PanelController {
    private(set) var panel: FloatingPanel?
    private let listView = SessionListView()
    private let preferences: Preferences

    var onActivate: ((Session) -> Void)?
    var onSecondaryClick: ((Session, NSEvent) -> Void)?

    private var theme: Theme = DefaultTheme.theme
    private var frameObserver: NSObjectProtocol?

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        listView.onActivate = { [weak self] session in self?.onActivate?(session) }
        listView.onSecondaryClick = { [weak self] session, event in
            self?.onSecondaryClick?(session, event)
        }
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
        listView.apply(theme: theme)
        panel?.backgroundColor = theme.colors.windowBackground
    }

    func apply(sessions: [Session]) {
        listView.apply(sessions: sessions, renames: preferences.renames)
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
        panel.backgroundColor = theme.colors.windowBackground
        panel.contentView = listView
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
        listView.apply(theme: theme)
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
