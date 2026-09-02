// SPDX-License-Identifier: AGPL-3.0-or-later
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
                ),
                removeBackground: ImageKeyer.Key(entry.removeBackground)
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

    /// The window silhouette.
    ///
    /// Three decisions and no more: which image, whether to keep its
    /// proportions, and how to get transparency out of it.
    static func window(from manifest: ThemeManifest.Window?, folder: URL?) -> Theme.Window {
        guard let manifest, let folder, let url = imageFile(manifest.file, in: folder) else {
            return .standard
        }

        let locked = manifest.lockAspect ?? true
        let insets = manifest.capInsets
        return Theme.Window(
            shape: BackgroundImage(
                url: url,
                // A locked skin is scaled whole, so slicing never applies and
                // stretch is simply "draw it at this size".
                mode: locked ? .stretch : (BackgroundImage.Mode(rawValue: manifest.mode ?? "") ?? .tile),
                capInsets: locked ? NSEdgeInsets() : NSEdgeInsets(
                    top: Theme.length(insets?.top, 0),
                    left: Theme.length(insets?.left, 0),
                    bottom: Theme.length(insets?.bottom, 0),
                    right: Theme.length(insets?.right, 0)
                ),
                removeBackground: ImageKeyer.Key(manifest.removeBackground)
            ),
            locksAspect: locked,
            aspectRatio: measure(url).ratio,
            drawsOverContent: manifest.overlay ?? false,
            bodyFadesBelowAnalyser: manifest.bodyFade ?? false,
            naturalWidth: measure(url).width
        )
    }

    /// The artwork's proportions and its own width, so the panel can derive its
    /// height from one and scale the theme's insets by the other.
    private static func measure(_ url: URL) -> (ratio: CGFloat, width: CGFloat) {
        guard let image = NSImage(contentsOf: url), image.size.height > 0 else { return (1, 0) }
        return (image.size.width / image.size.height, image.size.width)
    }

    static func avatar(from manifest: ThemeManifest.Avatar?,
                       folder: URL?,
                       fallback: Theme.Avatar) -> Theme.Avatar {
        guard let manifest else { return fallback }

        let declaredPosition = Theme.Avatar.Position(rawValue: manifest.position?.lowercased() ?? "")
        // Clamped rather than trusted: a negative size is meaningless and a
        // huge one only wastes memory decoding artwork no row can show.
        let declaredSize = Theme.length(manifest.size, fallback.size)
        return Theme.Avatar(
            size: declaredSize <= 0 ? 0 : min(declaredSize, 256),
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

    /// The `cornerDecorations` block: up to four independent slots, each
    /// resolving to nothing rather than failing the whole theme if its file
    /// is missing or unsupported — the same forgiving contract every other
    /// asset lookup here follows.
    static func cornerDecorations(from manifest: ThemeManifest.CornerDecorations?,
                                  folder: URL?) -> Theme.CornerDecorations {
        guard let manifest, let folder else { return .none }
        return Theme.CornerDecorations(
            topLeft: decoration(from: manifest.topLeft, in: folder),
            topRight: decoration(from: manifest.topRight, in: folder),
            bottomLeft: decoration(from: manifest.bottomLeft, in: folder),
            bottomRight: decoration(from: manifest.bottomRight, in: folder)
        )
    }

    /// A video key wins if both are set, same rule as an avatar state.
    private static func decoration(from entry: ThemeManifest.CornerDecoration?,
                                   in folder: URL) -> Theme.CornerDecoration? {
        guard let entry else { return nil }
        let offset = CGSize(width: entry.offset?.x ?? 0, height: entry.offset?.y ?? 0)
        // 0 or negative would hide or invert the art, neither of which is a
        // meaningful "scale" — fall back to the real size rather than do that.
        let declaredScale = CGFloat(entry.scale ?? 1)
        let scale = declaredScale > 0 ? declaredScale : 1

        if let video = entry.video, let url = existingFile(video, in: folder) {
            guard videoExtensions.contains(url.pathExtension.lowercased()) else {
                Log.theming.notice(
                    "Unsupported corner decoration video \(url.lastPathComponent, privacy: .public)"
                )
                return nil
            }
            return Theme.CornerDecoration(
                asset: .video(url, loop: entry.loop ?? true, muted: entry.muted ?? true),
                offset: offset,
                scale: scale
            )
        }

        let key = ImageKeyer.Key(entry.removeBackground)
        let backgrounds = (entry.image ?? []).compactMap { name -> BackgroundImage? in
            guard let url = imageFile(name, in: folder) else { return nil }
            // Meaningless for a corner decoration, but BackgroundImage still
            // needs a value — .center is the "draw at natural size" mode, and
            // capInsets zero means no slicing is even attempted.
            return BackgroundImage(url: url, mode: .center, capInsets: NSEdgeInsets(), removeBackground: key)
        }
        guard !backgrounds.isEmpty else { return nil }
        return Theme.CornerDecoration(asset: .image(backgrounds), offset: offset, scale: scale)
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
        // A theme is a folder you may have been handed. Its manifest names its
        // own files — `"image": "../../secret.png"` is reaching for someone
        // else's, and while the worst it wins is a picture on screen (there is
        // no network), it does not get even that.
        guard isInside(url, folder) else {
            Log.theming.notice("Theme asset \(trimmed, privacy: .public) points outside its folder")
            return nil
        }
        if FileManager.default.fileExists(atPath: url.path) { return url }

        if let sibling = siblingWithAnotherExtension(of: url) {
            Log.theming.notice(
                "Theme asked for \(trimmed, privacy: .public), using \(sibling.lastPathComponent, privacy: .public)"
            )
            return sibling
        }

        Log.theming.notice("Theme file not found: \(trimmed, privacy: .public)")
        return nil
    }

    /// Whether `url` resolves to a location within `folder` — `..` walked out
    /// and symlinks followed, on both sides, so neither a `../` in the name nor
    /// a planted symlink escapes.
    static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let base = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        return target == base || target.hasPrefix(base + "/")
    }

    /// Accepts `cat.gif` when the manifest asked for `cat.png`.
    ///
    /// Image models happily return an animated GIF for a state the manifest
    /// declared as a PNG, and the mismatch is invisible: the asset resolves to
    /// nothing and the built-in face draws instead, so the author sees a theme
    /// that "did not work" with no clue why. The name is what the author meant;
    /// the extension is a detail their tool chose.
    private static func siblingWithAnotherExtension(of url: URL) -> URL? {
        let stem = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        // Prefer image formats, so a still or animation wins over video when
        // both happen to exist under the same name.
        let matches = candidates.filter { $0.deletingPathExtension().lastPathComponent == stem }
        let chosen = matches.first { imageExtensions.contains($0.pathExtension.lowercased()) }
            ?? matches.first { videoExtensions.contains($0.pathExtension.lowercased()) }

        // Rebuild from the folder we were given: directory enumeration returns
        // symlink-resolved paths (/private/var), and handing back a differently
        // shaped URL than every other lookup makes assets compare unequal.
        return chosen.map { folder.appendingPathComponent($0.lastPathComponent) }
    }
}
