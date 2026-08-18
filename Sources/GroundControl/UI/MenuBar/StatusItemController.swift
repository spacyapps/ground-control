// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The menu-bar presence: always there, badges when a session needs you.
///
/// Left-click toggles the panel; right-click opens the menu — the usual macOS
/// idiom for a status item that has a primary action.
final class StatusItemController {
    var menuProvider: (() -> NSMenu)?

    private let statusItem: NSStatusItem
    private var needsAction = false

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        render()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(buttonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Badge state is derived from the sessions, never set by hand.
    func update(sessions: [Session]) {
        let wanted = sessions.contains { $0.needsAction }
        guard wanted != needsAction else { return }
        needsAction = wanted
        render()
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let symbol = needsAction ? "bell.badge.fill" : "terminal"
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: needsAction ? "Sessions need attention" : "Ground Control"
        )
        button.image?.isTemplate = !needsAction
        button.contentTintColor = needsAction ? DefaultTheme.colors.needsAction : nil
        button.toolTip = needsAction ? "A session needs your input" : "Ground Control"
    }

    /// Either button opens the menu, which is what a menu-bar icon does
    /// everywhere else on the system.
    ///
    /// It used to toggle the panel on a left click and show the menu only on a
    /// right click. That saved a click on the most common action and cost the
    /// convention: people click a menu-bar icon expecting a menu, and got a
    /// window appearing and disappearing instead. Showing and hiding the panel
    /// is the menu's first item, so the action is still one keystroke away.
    @objc private func buttonClicked() {
        guard let menu = menuProvider?() else { return }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
