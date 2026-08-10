import AppKit

/// Composition root: owns the subsystems and is the only place that wires
/// concrete instances together (docs/STRUCTURE.md).
///
/// The dependency flow is one-way — the store knows nothing about the panel,
/// the panel knows nothing about files.
final class AppCoordinator {
    private let store = SessionStore()
    private let themeStore = ThemeStore()
    private let purge = PurgeService()
    private let panel = PanelController()
    private let statusItem = StatusItemController()
    private let preferences: Preferences

    private var statusMenu: StatusMenu?

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    func start() {
        Paths.ensureFoldersExist()
        wireMenu()

        statusItem.onTogglePanel = { [weak self] in self?.panel.toggle() }
        statusItem.menuProvider = { [weak self] in
            guard let self else { return NSMenu() }
            return self.statusMenu?.build(
                panelVisible: self.panel.isVisible,
                activeTheme: self.themeStore.theme
            ) ?? NSMenu()
        }

        panel.onActivate = { [weak self] session in self?.activate(session) }
        panel.onSecondaryClick = { [weak self] session, event in
            self?.showContextMenu(for: session, event: event)
        }

        themeStore.onChange = { [weak self] theme in
            self?.panel.apply(theme: theme)
        }

        store.onChange = { [weak self] sessions in
            self?.panel.apply(sessions: sessions)
            self?.statusItem.update(sessions: sessions)
        }

        themeStore.start()
        purge.start()
        store.start()

        panel.apply(sessions: store.sessions)
        statusItem.update(sessions: store.sessions)
        panel.show()
    }

    // MARK: - Actions

    /// Clicking a row jumps to its terminal and clears the dot.
    private func activate(_ session: Session) {
        store.acknowledge(sessionID: session.id)
        TerminalFocuser.focus(tty: session.tty, fallbackPath: session.cwd)
    }

    /// The row the context menu was opened on. Menu items act on this rather
    /// than capturing a session, because NSMenuItem dispatches by selector.
    private var contextSession: Session?

    private func showContextMenu(for session: Session, event: NSEvent) {
        contextSession = session

        let menu = NSMenu()
        menu.addItem(menuItem(
            title: "Jump to Terminal",
            action: #selector(contextJump),
            isEnabled: session.tty != nil
        ))
        menu.addItem(menuItem(title: "Reveal in Finder", action: #selector(contextReveal)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Copy Path", action: #selector(contextCopyPath)))
        menu.addItem(menuItem(title: "Rename…", action: #selector(contextRename)))

        guard let view = panel.panel?.contentView else { return }
        let location = view.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: location, in: view)
    }

    private func menuItem(title: String, action: Selector, isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        return item
    }

    @objc private func contextJump() {
        guard let session = contextSession else { return }
        activate(session)
    }

    @objc private func contextReveal() {
        guard let path = contextSession?.cwd else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    @objc private func contextCopyPath() {
        guard let path = contextSession?.cwd else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc private func contextRename() {
        guard let session = contextSession else { return }
        let current = session.displayName(renames: preferences.renames)

        let alert = NSAlert()
        alert.messageText = "Rename session"
        alert.informativeText = "Leave blank to fall back to the session's own name."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = current
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        preferences.rename(sessionID: session.id, to: field.stringValue)
        panel.apply(sessions: store.sessions)
    }

    private func wireMenu() {
        statusMenu = StatusMenu(actions: StatusMenu.Actions(
            togglePanel: { [weak self] in self?.panel.toggle() },
            toggleAlwaysOnTop: { [weak self] in
                guard let self else { return }
                self.preferences.alwaysOnTop.toggle()
                self.panel.applyWindowBehaviour()
            },
            toggleAllSpaces: { [weak self] in
                guard let self else { return }
                self.preferences.showOnAllSpaces.toggle()
                self.panel.applyWindowBehaviour()
            },
            selectTheme: { [weak self] name in self?.themeStore.select(name: name) },
            openThemesFolder: {
                Paths.ensureFoldersExist()
                NSWorkspace.shared.open(Paths.userThemes)
            },
            quit: { NSApp.terminate(nil) }
        ))
    }
}
