// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Hosts the settings window.
///
/// The app is an accessory with no Dock icon, so it must activate explicitly
/// before showing a real window — otherwise the window appears behind
/// everything and cannot take keyboard focus. That is the opposite of the
/// panel's rule, which must never steal focus.
final class SettingsWindowController: NSWindowController {
    private let settingsView: SettingsView

    init(actions: SettingsView.Actions) {
        settingsView = SettingsView(actions: actions)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 654),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Ground Control Settings"
        // The star field runs under the title bar rather than stopping at a
        // grey strip, and the fixed dark palette needs the dark appearance so
        // the system controls sitting on it are legible.
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = SettingsChrome.deepSpace
        window.contentView = settingsView
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is created in code only")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func themeDidChange() {
        settingsView.themeDidChange()
    }

    func themesDidChangeOnDisk() {
        settingsView.themesDidChangeOnDisk()
    }
}
