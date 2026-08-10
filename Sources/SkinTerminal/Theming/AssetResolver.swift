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

    static func avatar(from manifest: ThemeManifest.Avatar?,
                       folder: URL?,
                       fallback: Theme.Avatar) -> Theme.Avatar {
        guard let manifest else { return fallback }

        let declaredPosition = Theme.Avatar.Position(rawValue: manifest.position?.lowercased() ?? "")
        return Theme.Avatar(
            size: length(manifest.size, fallback.size),
            position: declaredPosition ?? fallback.position,
            cornerRadius: length(manifest.cornerRadius, fallback.cornerRadius),
            states: states(from: manifest.states, folder: folder)
        )
    }

    /// Spelled out rather than `.map(CGFloat.init)`, which the type checker
    /// cannot resolve inside a multi-argument initialiser.
    private static func length(_ value: Double?, _ fallback: CGFloat) -> CGFloat {
        guard let value else { return fallback }
        return CGFloat(value)
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

        if let image = entry.image, let url = existingFile(image, in: folder) {
            guard imageExtensions.contains(url.pathExtension.lowercased()) else {
                Log.theming.notice("Unsupported avatar image \(url.lastPathComponent, privacy: .public)")
                return nil
            }
            return .image(url)
        }

        return nil
    }

    private static func existingFile(_ path: String, in folder: URL) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = folder.appendingPathComponent(trimmed)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.theming.notice("Avatar file not found: \(trimmed, privacy: .public)")
            return nil
        }
        return url
    }
}
