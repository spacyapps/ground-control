// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import AppKit

/// Turns the manifest's avatar block into resolved file URLs.
///
/// Two rules from docs/THEMING.md drive everything here:
/// - paths are relative to the theme folder, and files can be named anything;
/// - a state whose file is missing resolves to nothing rather than failing, so
///   a typo costs you one avatar, not the whole theme.
enum AssetResolver {
    /// Formats AppKit can display as a still or self-animating image.
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "apng", "heic", "tiff", "pdf"]
    /// Formats AVFoundation plays. `.webm` is deliberately absent — macOS has
    /// no native decoder for it.
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    /// Resolves the `assets` block. Anything missing, unreadable or of an
    /// unsupported type resolves to nil, leaving the painted surface in place.
    static func backgrounds(from assets: [String: ThemeManifest.Asset?]?,
                            folder: URL?) -> Theme.Backgrounds {
        guard let assets, let folder else { return .none }

        func background(_ key: String) -> BackgroundImage? {
            guard let entry = assets[key]?.flatMap({ $0 }),
                  let url = imageFile(entry.image, in: folder) else { return nil }

            let insets = entry.capInsets
            return BackgroundImage(
                url: url,
                // Tiling is the safe default for a bare filename: a texture
                // tiles cleanly, whereas stretching one looks broken.
                mode: BackgroundImage.Mode(rawValue: entry.mode ?? "") ?? .tile,
                capInsets: NSEdgeInsets(
                    top: CGFloat(insets?.top ?? 0),
                    left: CGFloat(insets?.left ?? 0),
                    bottom: CGFloat(insets?.bottom ?? 0),
                    right: CGFloat(insets?.right ?? 0)
                )
            )
        }

        func plainImage(_ key: String) -> URL? {
            imageFile(assets[key]?.flatMap({ $0 })?.image, in: folder)
        }

        return Theme.Backgrounds(
            window: background("windowBackground"),
            titleBar: background("titleBarBackground"),
            footer: background("footerBackground"),
            needsActionDot: plainImage("needsActionDot"),
            brandMark: plainImage("brandMark")
        )
    }

    static func avatar(from manifest: ThemeManifest.Avatar?,
                       folder: URL?,
                       fallback: Theme.Avatar) -> Theme.Avatar {
        guard let manifest else { return fallback }

        let declaredPosition = Theme.Avatar.Position(rawValue: manifest.position?.lowercased() ?? "")
        return Theme.Avatar(
            size: Theme.length(manifest.size, fallback.size),
            position: declaredPosition ?? fallback.position,
            cornerRadius: Theme.length(manifest.cornerRadius, fallback.cornerRadius),
            states: states(from: manifest.states, folder: folder)
        )
    }

    private static func states(from declared: [String: ThemeManifest.Avatar.State]?,
                               folder: URL?) -> [SessionState: Theme.Avatar.Asset] {
        guard let declared, let folder else { return [:] }

        var resolved: [SessionState: Theme.Avatar.Asset] = [:]
        for state in SessionState.allCases {
            guard let entry = declared[state.rawValue],
                  let asset = asset(for: entry, in: folder) else { continue }
            resolved[state] = asset
        }
        return resolved
    }

    private static func asset(for entry: ThemeManifest.Avatar.State,
                              in folder: URL) -> Theme.Avatar.Asset? {
        // A video key wins if both are set — the author asked for motion.
        if let video = entry.video, let url = existingFile(video, in: folder) {
            guard videoExtensions.contains(url.pathExtension.lowercased()) else {
                Log.theming.notice("Unsupported avatar video \(url.lastPathComponent, privacy: .public)")
                return nil
            }
            return .video(url, loop: entry.loop ?? true, muted: entry.muted ?? true)
        }

        if let url = imageFile(entry.image, in: folder) {
            return .image(url)
        }

        return nil
    }

    /// Resolve-and-validate, the shape every asset lookup needs: a name the
    /// author wrote, a file that exists, and a format we can actually display.
    private static func imageFile(_ name: String?, in folder: URL) -> URL? {
        guard let name, let url = existingFile(name, in: folder) else { return nil }
        guard imageExtensions.contains(url.pathExtension.lowercased()) else {
            Log.theming.notice("Unsupported image \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        return url
    }

    private static func existingFile(_ path: String, in folder: URL) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = folder.appendingPathComponent(trimmed)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.theming.notice("Theme file not found: \(trimmed, privacy: .public)")
            return nil
        }
        return url
    }
}
