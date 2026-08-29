// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import MatrixKit

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
            .filter { !isReference($0) }
            .sorted { lhs, rhs in
                lhs.lastPathComponent
                    .localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    /// A manifest that documents the format rather than describing a look.
    ///
    /// Read from the raw JSON rather than a resolved `Theme`, because the whole
    /// point of such a file is that resolving it produces the built-in theme —
    /// by the time it is a `Theme` there is nothing left to tell it apart.
    static func isReference(_ folder: URL) -> Bool {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("theme.json")),
              let manifest = try? JSONDecoder().decode(ThemeManifest.self, from: forgiving(data))
        else { return false }
        return manifest.reference == true
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
            return failed(folder, because: "There is no theme.json in this folder.")
        }
        do {
            let manifest = try JSONDecoder().decode(ThemeManifest.self, from: forgiving(data))
            return resolve(manifest, folder: folder)
        } catch {
            let name = folder.lastPathComponent
            let reason = error.localizedDescription
            Log.theming.error("Bad theme.json in \(name, privacy: .public): \(reason, privacy: .public)")
            return failed(folder, because: """
                This theme's theme.json could not be read, so the built-in \
                default is being shown instead. \(reason)
                """)
        }
    }

    /// `layout.resize`, falling back to the older `window.lockAspect`.
    ///
    /// `lockAspect` said the same thing in fewer words and could not express
    /// a freely resizable panel, so it stays readable rather than being broken:
    /// themes written before this key still mean what they meant.
    private static func resizeMode(_ declared: String?, lockAspect: Bool?) -> Theme.Resize {
        let cleaned = declared?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if let mode = Theme.Resize(rawValue: cleaned) { return mode }
        guard let lockAspect else { return DefaultTheme.layout.resize }
        return lockAspect ? .aspect : .content
    }

    /// The default theme, but saying so.
    ///
    /// Falling back silently is what makes a broken manifest so hard to place:
    /// Settings names the theme you picked in the picker while showing the
    /// built-in one beside it, and nothing anywhere connects the two. A stale
    /// build reading a newer manifest looks exactly the same as a typo.
    private static func failed(_ folder: URL, because reason: String) -> Theme {
        var theme = DefaultTheme.theme
        theme.warnings = [reason.replacingOccurrences(of: "\n", with: " ")]
        return theme
    }

    private static func layout(
        from manifestLayout: ThemeManifest.Layout?,
        window: ThemeManifest.Window?
    ) -> Theme.Layout {
        let defaultLayout = DefaultTheme.layout
        return Theme.Layout(
            resize: resizeMode(manifestLayout?.resize, lockAspect: window?.lockAspect),
            contentInset: NSEdgeInsets(
                top: Theme.length(manifestLayout?.contentInset?.top, defaultLayout.contentInset.top),
                left: Theme.length(manifestLayout?.contentInset?.left, defaultLayout.contentInset.left),
                bottom: Theme.length(
                    manifestLayout?.contentInset?.bottom,
                    defaultLayout.contentInset.bottom
                ),
                right: Theme.length(
                    manifestLayout?.contentInset?.right,
                    defaultLayout.contentInset.right
                )
            ),
            contentCornerRadius: Theme.length(
                manifestLayout?.contentCornerRadius,
                defaultLayout.contentCornerRadius
            ),
            rowMaxHeight: Theme.length(manifestLayout?.rowMaxHeight, defaultLayout.rowMaxHeight),
            rowPadding: Theme.length(manifestLayout?.rowPadding, defaultLayout.rowPadding),
            marqueeOnOverflow: manifestLayout?.marqueeOnOverflow ?? defaultLayout.marqueeOnOverflow,
            marqueeSpeed: Theme.length(manifestLayout?.marqueeSpeed, defaultLayout.marqueeSpeed),
            isCompact: (manifestLayout?.density ?? "").lowercased() == "compact"
        )
    }

    /// An overlay skin whose centre does not key out covers the whole panel, so
    /// it is measured before it is trusted and demoted to an ordinary
    /// background if it would. Behind the rows the same artwork is merely
    /// imperfect; in front of them it is an app that vanished.
    private static func verifiedWindow(
        from manifest: ThemeManifest,
        folder: URL?
    ) -> (window: Theme.Window, warnings: [String]) {
        let window = AssetResolver.window(from: manifest.window, folder: folder)
        guard window.drawsOverContent,
              let shape = window.shape,
              SkinCheck.hidesContent(shape) else { return (window, []) }

        Log.theming.notice("Overlay skin has a solid centre; drawing it behind the rows instead")
        var demoted = window
        demoted.drawsOverContent = false
        demoted.bodyFadesBelowAnalyser = false   // meaningless once it draws behind
        return (demoted, [
            """
            This skin is set to draw in front, but its middle is solid, which \
            would hide the panel — so it is drawn behind instead. Fill the \
            centre with the same colour as the outside edges to use overlay.
            """
        ])
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

        let layout = self.layout(from: manifest.layout, window: manifest.window)

        let defaultType = DefaultTheme.typography
        let manifestType = manifest.typography
        let typography = Theme.Typography(
            fontFamily: manifestType?.fontFamily ?? defaultType.fontFamily,
            nameSize: Theme.length(manifestType?.nameSize, defaultType.nameSize),
            messageSize: Theme.length(manifestType?.messageSize, defaultType.messageSize),
            nameWeight: weight(manifestType?.nameWeight) ?? defaultType.nameWeight
        )

        let checked = verifiedWindow(from: manifest, folder: folder)
        return Theme(
            name: manifest.name ?? folder?.lastPathComponent ?? "Default",
            author: manifest.author,
            summary: manifest.description,
            warnings: checked.warnings,
            colors: colors,
            layout: layout,
            typography: typography,
            avatar: AssetResolver.avatar(
                from: manifest.avatar,
                folder: folder,
                fallback: DefaultTheme.avatar
            ),
            matrix: Self.matrix(manifest.matrix, colors: colors),
            window: checked.window,
            backgrounds: AssetResolver.backgrounds(from: manifest.assets, folder: folder),
            cornerDecorations: AssetResolver.cornerDecorations(
                from: manifest.cornerDecorations,
                folder: folder
            ),
            folder: folder
        )
    }

    /// Strips the two things an LLM adds to JSON that JSON does not allow.
    ///
    /// Themes are increasingly written by models, and they emit `//` comments
    /// and trailing commas by habit. Strict decoding turns either into a silent
    /// fallback to the default theme — the author sees "my theme did nothing"
    /// with no clue why. Being lenient here costs a pass over the text and
    /// removes a whole class of invisible failure.
    static func forgiving(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }

        // Line comments, but not `//` inside a string such as a URL.
        text = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var insideString = false
            var escaped = false
            let characters = Array(line)
            for index in characters.indices {
                let character = characters[index]
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == "\"" { insideString.toggle(); continue }
                if !insideString, character == "/", index + 1 < characters.count,
                   characters[index + 1] == "/" {
                    return String(characters[..<index])
                }
            }
            return String(line)
        }.joined(separator: "\n")

        // Trailing commas before a closing brace or bracket.
        while let range = text.range(of: ",[ \t\n\r]*[}\\]]", options: .regularExpression) {
            let closing = text[range].last.map(String.init) ?? "}"
            text.replaceSubrange(range, with: closing)
        }
        return Data(text.utf8)
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
            messages: MatrixMessages.usable(declared?.messages ?? []),
            feel: MatrixFeel.resolve(declared),
            patterns: VisualizerPattern.rotation(from: declared?.patterns ?? []),
            workingShape: shape(declared?.shape?.working, "matrix.shape.working"),
            needsInputShape: shape(declared?.shape?.needsInput, "matrix.shape.needsInput"),
            doneShape: shape(declared?.shape?.done, "matrix.shape.done", allowsDecay: true),
            idleShape: shape(declared?.shape?.idle, "matrix.shape.idle")
        )
    }

    /// Parses one per-state formula. A miss logs (inside `PatternFormula.parse`)
    /// and stays nil, so the state falls back to its built-in behaviour.
    private static func shape(_ source: String?, _ key: String, allowsDecay: Bool = false)
        -> PatternFormula? {
        source.flatMap { PatternFormula.parse($0, key: key, allowsDecay: allowsDecay) }
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
