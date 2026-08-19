// SPDX-License-Identifier: AGPL-3.0-or-later
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
        // The emitter and this app are two halves of one contract, installed
        // separately and therefore prone to drifting apart in silence.
        HookUpdater.updateIfNeeded()
        wireMenu()

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
        let arrived = TerminalFocuser.focus(
            tty: session.tty,
            hostApp: session.hostApp,
            hostID: session.hostID,
            fallbackPath: session.cwd
        )
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
        let menu = contextMenu(for: session)
        guard let view = panel.panel?.contentView else { return }
        let location = view.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: location, in: view)
    }

    /// Built apart from showing it, so what the menu says about a session can be
    /// checked without a window, a click, or a running app.
    func contextMenu(for session: Session) -> NSMenu {
        // Named after where the click will actually land: "Terminal" is a lie
        // when the session lives in VS Code, and the item was disabled on a
        // missing tty even when the host app was perfectly reachable.
        let destination = TerminalFocuser.destinationName(
            tty: session.tty,
            hostApp: session.hostApp,
            hostID: session.hostID
        )
        let menu = NSMenu()
        menu.addItem(menuItem(
            title: destination.map { "Jump to \($0)" } ?? "Jump to Terminal",
            action: #selector(contextJump),
            isEnabled: destination != nil
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

        // Said on the row it applies to, because that is where the question
        // gets asked: this one never turns red, and nothing about it explains
        // why. Cursor fires no hook while its agent waits for approval, so a
        // blocked chat is indistinguishable from a busy one — measured, and
        // confirmed against their docs. See docs/LIMITATIONS.md.
        //
        // Worded without naming the CLI: the row already says CURSOR, and an
        // editor's built-in agent is going to keep being the shape of this
        // problem — VS Code's chat will land here too.
        if StatusDotView.Mark.forSource(session.source) == .square {
            menu.addItem(.separator())
            menu.addItem(note("Agent: limited support"))
            menu.addItem(note("No alert when it waits for approval"))
        }
        return menu
    }

    /// A line that explains rather than does.
    ///
    /// A plain disabled item reads as an action you cannot have right now; the
    /// smaller grey type says it was never a button. No target, so it cannot be
    /// chosen however hard anyone tries.
    private func note(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
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

    /// Re-applies the current theme, which is what rebuilds the title strip.
    ///
    /// Turning the analyser off changes the strip's height, so the panel has to
    /// lay out again — and `apply(theme:)` already refits the height, so there
    /// is nothing else to say.
    private func refreshPanelChrome() {
        panel.apply(theme: themeStore.theme)
        panel.apply(sessions: store.sessions)
    }

    /// Kept alive between openings, so the window remembers where it was put.
    private var legal: LegalWindowController?

    private func showLegal() {
        if legal == nil { legal = LegalWindowController() }
        legal?.present()
    }

    private func showSettings() {
        if settings == nil {
            settings = SettingsWindowController(actions: SettingsView.Actions(
                selectTheme: { [weak self] name in self?.themeStore.select(name: name) },
                applyWindowBehaviour: { [weak self] in self?.panel.applyWindowBehaviour() },
                reloadSessions: { [weak self] in self?.store.reload() },
                refreshPanelChrome: { [weak self] in self?.refreshPanelChrome() },
                reloadTheme: { [weak self] in self?.themeStore.reload() },
                openLegal: { [weak self] in self?.showLegal() },
                openThemesFolder: { [weak self] in self?.openThemesFolder() },
                resetPanelPosition: { [weak self] in self?.panel.resetPosition() },
                createTheme: { [weak self] in self?.showThemeBuilder() },
                currentSessions: { [weak self] in self?.store.sessions ?? [] }
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
            toggleHook: { target, on in
                HookInstaller.run(on ? .install : .uninstall, target: target, silent: true)
            },
            currentSessions: { [weak self] in self?.store.sessions ?? [] },
            quit: { NSApp.terminate(nil) }
        ))
    }
}
