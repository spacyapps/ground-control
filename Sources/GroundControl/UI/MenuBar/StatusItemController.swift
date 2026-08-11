// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The menu-bar presence: always there, badges when a session needs you.
///
/// Left-click toggles the panel; right-click opens the menu — the usual macOS
/// idiom for a status item that has a primary action.
final class StatusItemController {
    var onTogglePanel: (() -> Void)?
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

    @objc private func buttonClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick, let menu = menuProvider?() {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        onTogglePanel?()
    }
}
