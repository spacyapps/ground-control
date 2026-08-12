// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

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
    private var settings: SettingsWindowController?
    private var themeBuilder: ThemeBuilderWindowController?

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    func start() {
        Paths.ensureFoldersExist()
        // The themes that ship with the app are copied out before anything
        // reads the folder, so they are in the picker on a first launch.
        ThemeSeeder.seed()
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
            self?.settings?.themeDidChange()
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

    /// Clicking a row jumps to its terminal and clears the dot — but only if
    /// the jump actually landed somewhere.
    ///
    /// Acknowledging is a claim that you have gone and dealt with it. When the
    /// terminal has since closed, or the session never had a tty, the click
    /// takes you nowhere, and quietly dropping the alarm would leave a blocked
    /// session looking handled. Silencing an alarm nobody attended to is the
    /// one thing a monitor must not do.
    private func activate(_ session: Session) {
        let arrived = TerminalFocuser.focus(tty: session.tty, fallbackPath: session.cwd)
        if arrived {
            store.acknowledge(sessionID: session.id)
        } else {
            Log.integration.notice("Could not reach the session; leaving its alarm up")
        }
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
        // The deliberate way to silence an alarm you cannot reach — now that
        // clicking the row will not do it unless the jump lands.
        menu.addItem(menuItem(
            title: "Dismiss Alert",
            action: #selector(contextDismiss),
            isEnabled: session.needsAction
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Copy Path", action: #selector(contextCopyPath)))
        menu.addItem(menuItem(title: "Rename…", action: #selector(contextRename)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Remove Row", action: #selector(contextRemove)))

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

    /// Removes the row outright. A live session reappears on its next event,
    /// so this is only permanent for one that has genuinely finished.
    @objc private func contextRemove() {
        guard let session = contextSession else { return }
        store.remove(sessionID: session.id)
    }

    @objc private func contextDismiss() {
        guard let session = contextSession else { return }
        store.acknowledge(sessionID: session.id)
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

    private func showSettings() {
        if settings == nil {
            settings = SettingsWindowController(actions: SettingsView.Actions(
                selectTheme: { [weak self] name in self?.themeStore.select(name: name) },
                applyWindowBehaviour: { [weak self] in self?.panel.applyWindowBehaviour() },
                reloadSessions: { [weak self] in self?.store.reload() },
                openThemesFolder: { [weak self] in self?.openThemesFolder() },
                resetPanelPosition: { [weak self] in self?.panel.resetPosition() },
                createTheme: { [weak self] in self?.showThemeBuilder() }
            ))
        }
        settings?.present()
    }

    private func showThemeBuilder() {
        if themeBuilder == nil {
            themeBuilder = ThemeBuilderWindowController { [weak self] in
                self?.settings?.themesDidChangeOnDisk()
            }
        }
        themeBuilder?.present()
    }

    private func openThemesFolder() {
        Paths.ensureFoldersExist()
        NSWorkspace.shared.open(Paths.userThemes)
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
            openThemesFolder: { [weak self] in self?.openThemesFolder() },
            openSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) }
        ))
    }
}
