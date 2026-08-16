// SPDX-License-Identifier: GPL-3.0-or-later
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
        var setUpHooks: () -> Void
        var removeHooks: () -> Void
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
        menu.addItem(item(title: "Set Up Hooks…", action: #selector(setUpHooks)))
        menu.addItem(item(title: "Remove Hooks…", action: #selector(removeHooks)))
        menu.addItem(.separator())

        menu.addItem(item(title: "Quit Ground Control", action: #selector(quit), key: "q"))
        return menu
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
    @objc private func setUpHooks() { actions.setUpHooks() }
    @objc private func removeHooks() { actions.removeHooks() }
    @objc private func quit() { actions.quit() }
    @objc private func selectDefaultTheme() { actions.selectTheme(nil) }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        actions.selectTheme(sender.representedObject as? String)
    }
}
