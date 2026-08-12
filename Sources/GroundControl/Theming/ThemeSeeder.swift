// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Puts the themes that ship with the app where the app looks for themes.
///
/// Themes are only ever read from `~/Library/Application Support`, which is
/// what makes them editable and hot-reloadable — a theme inside the bundle
/// could be neither. So the shipped ones are copied out on first launch and
/// then belong to whoever installed them.
///
/// **Never overwrites.** A folder that already exists is left exactly as it is,
/// including one the user has since edited. The cost is that a theme improved
/// in a later release will not reach anyone who already has that folder, which
/// is the right way round: losing someone's work to an update is worse than
/// them keeping an older starting point.
enum ThemeSeeder {
    /// Where the shipped copies live inside `GroundControl.app`.
    static var bundled: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Themes", isDirectory: true)
    }

    @discardableResult
    static func seed(from source: URL? = bundled, into destination: URL = Paths.userThemes) -> [String] {
        guard let source else { return [] }

        let manager = FileManager.default
        let candidates = (try? manager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var installed: [String] = []
        for folder in candidates {
            // A folder without a manifest is not a theme, whatever else it is.
            guard manager.fileExists(
                atPath: folder.appendingPathComponent("theme.json").path
            ) else { continue }

            let target = destination.appendingPathComponent(folder.lastPathComponent)
            guard !manager.fileExists(atPath: target.path) else { continue }

            do {
                try manager.createDirectory(at: destination, withIntermediateDirectories: true)
                try manager.copyItem(at: folder, to: target)
                installed.append(folder.lastPathComponent)
            } catch {
                // A theme that fails to install is a missing option, not a
                // reason to stop launching.
                Log.theming.notice(
                    "Could not install bundled theme \(folder.lastPathComponent, privacy: .public)"
                )
            }
        }

        if !installed.isEmpty {
            Log.theming.notice("Installed bundled themes: \(installed.joined(separator: ", "), privacy: .public)")
        }
        return installed
    }
}
