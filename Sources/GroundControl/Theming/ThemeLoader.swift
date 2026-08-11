// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Finds themes on disk and resolves a manifest into a complete `Theme`.
///
/// Resolution is "manifest value, else code default", key by key — which is
/// the whole contract of docs/THEMING.md.
enum ThemeLoader {
    /// Theme folders in the user's Themes directory, sorted by name.
    static func availableThemes(in directory: URL = Paths.userThemes) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { url in
                FileManager.default.fileExists(atPath: url.appendingPathComponent("theme.json").path)
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent
                    .localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    static func loadTheme(named name: String?, in directory: URL = Paths.userThemes) -> Theme {
        guard let name, !name.isEmpty else { return DefaultTheme.theme }
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        return loadTheme(from: folder)
    }

    static func loadTheme(from folder: URL) -> Theme {
        let manifestURL = folder.appendingPathComponent("theme.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            Log.theming.notice("No theme.json in \(folder.lastPathComponent, privacy: .public); using defaults")
            return DefaultTheme.theme
        }
        do {
            let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)
            return resolve(manifest, folder: folder)
        } catch {
            let name = folder.lastPathComponent
            let reason = error.localizedDescription
            Log.theming.error("Bad theme.json in \(name, privacy: .public): \(reason, privacy: .public)")
            return DefaultTheme.theme
        }
    }

    static func resolve(_ manifest: ThemeManifest, folder: URL?) -> Theme {
        let palette = manifest.colors ?? [:]
        func color(_ key: String, _ fallback: NSColor) -> NSColor {
            guard let hex = palette[key], let parsed = NSColor(hex: hex) else { return fallback }
            return parsed
        }

        let base = DefaultTheme.colors
        let colors = Theme.Colors(
            windowBackground: color("windowBackground", base.windowBackground),
            titleBarBackground: color("titleBarBackground", base.titleBarBackground),
            titleBarText: color("titleBarText", base.titleBarText),
            rowBackground: color("rowBackground", base.rowBackground),
            rowBackgroundAlt: color("rowBackgroundAlt", base.rowBackgroundAlt),
            rowBackgroundHover: color("rowBackgroundHover", base.rowBackgroundHover),
            sessionName: color("sessionName", base.sessionName),
            message: color("message", base.message),
            messageDim: color("messageDim", base.messageDim),
            needsAction: color("needsAction", base.needsAction),
            working: color("working", base.working),
            idle: color("idle", base.idle),
            footerBackground: color("footerBackground", base.footerBackground),
            footerText: color("footerText", base.footerText),
            accent: color("accent", base.accent),
            divider: color("divider", base.divider)
        )

        let defaultLayout = DefaultTheme.layout
        let manifestLayout = manifest.layout
        let layout = Theme.Layout(
            contentInset: Theme.length(manifestLayout?.contentInset, defaultLayout.contentInset),
            rowMaxHeight: Theme.length(manifestLayout?.rowMaxHeight, defaultLayout.rowMaxHeight),
            rowPadding: Theme.length(manifestLayout?.rowPadding, defaultLayout.rowPadding),
            marqueeOnOverflow: manifestLayout?.marqueeOnOverflow ?? defaultLayout.marqueeOnOverflow,
            marqueeSpeed: Theme.length(manifestLayout?.marqueeSpeed, defaultLayout.marqueeSpeed),
            isCompact: (manifestLayout?.density ?? "").lowercased() == "compact"
        )

        let defaultType = DefaultTheme.typography
        let manifestType = manifest.typography
        let typography = Theme.Typography(
            fontFamily: manifestType?.fontFamily ?? defaultType.fontFamily,
            nameSize: Theme.length(manifestType?.nameSize, defaultType.nameSize),
            messageSize: Theme.length(manifestType?.messageSize, defaultType.messageSize),
            nameWeight: weight(manifestType?.nameWeight) ?? defaultType.nameWeight
        )

        return Theme(
            name: manifest.name ?? folder?.lastPathComponent ?? "Default",
            colors: colors,
            layout: layout,
            typography: typography,
            avatar: AssetResolver.avatar(
                from: manifest.avatar,
                folder: folder,
                fallback: DefaultTheme.avatar
            ),
            matrix: Self.matrix(manifest.matrix, colors: colors),
            backgrounds: AssetResolver.backgrounds(from: manifest.assets, folder: folder),
            folder: folder
        )
    }

    /// Matrix colours fall back to the row palette, so recolouring a theme
    /// restyles the meter too without naming a single matrix key.
    private static func matrix(_ declared: ThemeManifest.Matrix?, colors: Theme.Colors) -> Theme.Matrix {
        func color(_ hex: String?, _ fallback: NSColor) -> NSColor {
            guard let hex, let parsed = NSColor(hex: hex) else { return fallback }
            return parsed
        }
        return Theme.Matrix(
            low: color(declared?.low, colors.accent),
            high: color(declared?.high, colors.working),
            alarm: color(declared?.alarm, colors.needsAction),
            unlit: color(declared?.unlit, colors.divider.withAlphaComponent(0.10)),
            text: color(declared?.text, colors.titleBarText),
            peak: color(declared?.peak, colors.titleBarText.withAlphaComponent(0.7)),
            messages: MatrixMessages.usable(declared?.messages ?? [])
        )
    }

    private static func weight(_ name: String?) -> NSFont.Weight? {
        switch name?.lowercased() {
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        default: return nil
        }
    }
}
