// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Puts the themes that ship with the app where the app looks for themes.
///
/// Themes are only ever read from `~/Library/Application Support`, which is
/// what makes them editable and hot-reloadable — a theme inside the bundle
/// could be neither. So the shipped ones are copied out on first launch and
/// then belong to whoever installed them.
///
/// **Never overwrites anything anyone has touched.** For years this meant never
/// overwriting at all, which was the right way round — losing someone's evening
/// of recolouring to an update is far worse than them keeping an older starting
/// point — but it also meant a theme fixed in a later release reached nobody who
/// already had the folder.
///
/// So the app remembers what it installed. On a later launch, a folder whose
/// contents still match what was written is replaced with the newer version; a
/// folder that differs by so much as a colour is left alone, permanently. A
/// folder seeded before this was recorded is also left alone, because there is
/// no way to tell an untouched copy from an edited one without a record.
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

            let name = folder.lastPathComponent
            let target = destination.appendingPathComponent(name)
            let present = manager.fileExists(atPath: target.path)

            if present && !isUntouched(target, named: name) { continue }
            // Already the version we would install; nothing to do and nothing
            // to say about it.
            if present && ThemeFingerprint.of(target) == ThemeFingerprint.of(folder) { continue }

            do {
                try manager.createDirectory(at: destination, withIntermediateDirectories: true)
                if present { try manager.removeItem(at: target) }
                try manager.copyItem(at: folder, to: target)
                remember(target, named: name)
                installed.append(name)
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

    /// Whether the folder still holds exactly what was installed there.
    ///
    /// No record means no answer, and no answer means hands off: a theme seeded
    /// by a build from before this existed could equally be pristine or a
    /// weekend's work.
    private static func isUntouched(_ folder: URL, named name: String) -> Bool {
        guard let installed = seeded[name] else { return false }
        return ThemeFingerprint.of(folder) == installed
    }

    private static func remember(_ folder: URL, named name: String) {
        guard let print = ThemeFingerprint.of(folder) else { return }
        var record = seeded
        record[name] = print
        UserDefaults.standard.set(record, forKey: seededKey)
    }

    private static var seeded: [String: String] {
        UserDefaults.standard.dictionary(forKey: seededKey) as? [String: String] ?? [:]
    }

    /// Kept in preferences rather than beside the themes: a stray dotfile in a
    /// folder people are invited to open and edit is one more thing to explain,
    /// and one more thing for somebody to delete.
    private static let seededKey = "seededThemeFingerprints"
}
