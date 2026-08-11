// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import AppKit

/// The active theme, plus hot reload.
///
/// Watching the theme folder means saving `theme.json` in an editor re-skins
/// the panel immediately — the thing that makes authoring feel good
/// (docs/SPEC.md §6).
final class ThemeStore {
    private(set) var theme: Theme = DefaultTheme.theme

    /// Called on the main queue whenever the active theme changes.
    var onChange: ((Theme) -> Void)?

    private let preferences: Preferences
    private var watcher: FolderWatcher?

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    func start() {
        apply(name: preferences.themeName)
    }

    /// `nil` selects the built-in default.
    func select(name: String?) {
        preferences.themeName = name
        apply(name: name)
    }

    func reload() {
        apply(name: preferences.themeName)
    }

    private func apply(name: String?) {
        // Editing a PNG must re-skin as readily as editing the manifest.
        BackgroundRenderer.clearCache()
        theme = ThemeLoader.loadTheme(named: name)
        watchActiveFolder()
        onChange?(theme)
    }

    private func watchActiveFolder() {
        watcher?.stop()
        guard let folder = theme.folder else {
            watcher = nil
            return
        }
        watcher = FolderWatcher(url: folder, debounce: 0.25) { [weak self] in
            guard let self else { return }
            BackgroundRenderer.clearCache()
            self.theme = ThemeLoader.loadTheme(from: folder)
            self.onChange?(self.theme)
        }
        watcher?.start()
    }
}
