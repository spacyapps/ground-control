import Foundation

/// What the author wants, gathered from a few questions in Settings and turned
/// into a prompt for an image-capable LLM.
struct ThemeBrief: Equatable {
    var name: String
    var subject: String
    var style: String
    var mood: String
    var wantsAnimation: Bool
    var avatarSize: Int
    var position: String

    static let placeholder = ThemeBrief(
        name: "My Theme",
        subject: "a sleepy robot",
        style: "16-bit pixel art, chunky outlines",
        mood: "warm amber on near-black",
        wantsAnimation: true,
        avatarSize: 48,
        position: "right"
    )

    /// Folder name on disk. Themes are picked by folder, so this has to be a
    /// filename, not a title.
    var slug: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let separators = CharacterSet(charactersIn: " /\\:._")

        // Punctuation becomes a separator rather than vanishing, so "My / Theme"
        // does not collapse into "mytheme"; runs are then squeezed to one dash.
        let cleaned = name
            .lowercased()
            .unicodeScalars
            .map { separators.contains($0) ? "-" : (allowed.contains($0) ? String($0) : "") }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")

        return cleaned.isEmpty ? "my-theme" : cleaned
    }

    /// Rendered at `avatarSize` points on a Retina display, so art wants to be
    /// at least 2x that. 192 is a comfortable round number that stays crisp if
    /// the author later scales the avatar up.
    var recommendedPixels: Int {
        max(192, avatarSize * 4)
    }
}
