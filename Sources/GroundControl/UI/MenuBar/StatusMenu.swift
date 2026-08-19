// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Builds the status-item menu.
///
/// Pure construction — every item routes back through a callback so the menu
/// owns no state of its own.
final class StatusMenu: NSObject {
    struct Actions {
        var togglePanel: () -> Void
        var toggleAlwaysOnTop: () -> Void
        var toggleAllSpaces: () -> Void
        var selectTheme: (String?) -> Void
        var openThemesFolder: () -> Void
        var openSettings: () -> Void
        /// Turns one integration on or off. Hooks are plumbing rather than
        /// taste, so they live in the menu beside the other switches rather than
        /// in Settings, which is for how the panel looks.
        var toggleHook: (HookInstaller.Target, Bool) -> Void
        /// What the panel is showing, so each row can say whether anything has
        /// arrived from that agent.
        var currentSessions: () -> [Session]
        var quit: () -> Void
    }

    private let preferences: Preferences
    private let actions: Actions

    init(preferences: Preferences = .shared, actions: Actions) {
        self.preferences = preferences
        self.actions = actions
    }

    func build(panelVisible: Bool, activeTheme: Theme) -> NSMenu {
        let menu = NSMenu()

        menu.addItem(item(
            title: panelVisible ? "Hide Panel" : "Show Panel",
            action: #selector(togglePanel)
        ))
        menu.addItem(.separator())

        menu.addItem(item(
            title: "Always on Top",
            action: #selector(toggleAlwaysOnTop),
            isOn: preferences.alwaysOnTop
        ))
        menu.addItem(item(
            title: "Show on All Spaces",
            action: #selector(toggleAllSpaces),
            isOn: preferences.showOnAllSpaces
        ))
        menu.addItem(.separator())

        menu.addItem(themeMenu(activeTheme: activeTheme))
        menu.addItem(item(title: "Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())

        // The first thing a new user must do is run a script from inside an app
        // bundle in Terminal, which is the least friendly step in the product.
        // Offering it here is an invitation rather than the app installing
        // itself uninvited — the distinction HookUpdater is careful about.
        menu.addItem(hooksMenu())
        menu.addItem(.separator())

        menu.addItem(item(title: "Quit Ground Control", action: #selector(quit), key: "q"))
        return menu
    }

    /// Each integration, whether it is on, and whether anything has ever
    /// arrived from it.
    ///
    /// Real switches rather than ticks: a menu item can carry a view, and a
    /// switch says "this is a thing you can turn off" where a tick only says
    /// "registered". The title spells out what the submenu does, because
    /// "Hooks" alone tells you nothing about whether it is a status display or
    /// a control.
    private func hooksMenu() -> NSMenuItem {
        let parent = NSMenuItem(
            title: "Hooks (install, uninstall, status)",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()
        let width: CGFloat = 340
        // A menu disables anything without an action, and an item carrying a
        // view has none — its view is the action. Left alone, the switches
        // inside drew in their disabled grey and looked permanently off.
        submenu.autoenablesItems = false

        for agent in SetupStatus.agents(sessions: actions.currentSessions()) {
            let entry = NSMenuItem()
            entry.view = HookMenuRow(agent: agent, width: width) { [actions] on in
                guard let target = agent.target else { return }
                actions.toggleHook(target, on)
            }
            entry.isEnabled = true
            submenu.addItem(entry)
        }

        submenu.addItem(.separator())
        // Terminals need no integration of their own: an agent running inside
        // one is already covered by the switch for that agent. Worth saying,
        // because the absence of a VS Code row otherwise reads as "not
        // supported" when it is the opposite — verified there, and in Warp,
        // Ghostty, WezTerm, iTerm2 and Terminal.app.
        submenu.addItem(note("Agents in any terminal are covered above —"))
        submenu.addItem(note("VS Code, Cursor, Warp, Ghostty, iTerm2, Terminal."))
        submenu.addItem(note("Only an editor's own chat needs more."))
        submenu.addItem(.separator())
        submenu.addItem(note(emitterNote()))
        parent.submenu = submenu
        return parent
    }

    private func emitterNote() -> String {
        let emitter = SetupStatus.emitter()
        guard emitter.installed else { return "Reporting script not installed yet" }
        return emitter.current == false
            ? "Reporting script is older than this app"
            : "Reporting script installed"
    }

    /// A line that explains rather than does — smaller and grey, so it never
    /// reads as an action that is merely unavailable.
    private func note(_ text: String) -> NSMenuItem {
        let entry = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        entry.attributedTitle = NSAttributedString(string: "    " + text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        return entry
    }

    private func themeMenu(activeTheme: Theme) -> NSMenuItem {
        let parent = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let usingDefault = preferences.themeName == nil
        let builtIn = item(title: "Default (built-in)", action: #selector(selectDefaultTheme), isOn: usingDefault)
        submenu.addItem(builtIn)

        let themes = ThemeLoader.availableThemes()
        if !themes.isEmpty { submenu.addItem(.separator()) }
        for folder in themes {
            let name = folder.lastPathComponent
            let entry = item(
                title: name,
                action: #selector(selectTheme(_:)),
                isOn: preferences.themeName == name
            )
            entry.representedObject = name
            submenu.addItem(entry)
        }

        submenu.addItem(.separator())
        submenu.addItem(item(title: "Open Themes Folder…", action: #selector(openThemesFolder)))

        parent.submenu = submenu
        return parent
    }

    private func item(title: String,
                      action: Selector,
                      isOn: Bool = false,
                      key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        entry.state = isOn ? .on : .off
        return entry
    }

    @objc private func togglePanel() { actions.togglePanel() }
    @objc private func toggleAlwaysOnTop() { actions.toggleAlwaysOnTop() }
    @objc private func toggleAllSpaces() { actions.toggleAllSpaces() }
    @objc private func openThemesFolder() { actions.openThemesFolder() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func quit() { actions.quit() }
    @objc private func selectDefaultTheme() { actions.selectTheme(nil) }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        actions.selectTheme(sender.representedObject as? String)
    }
}
