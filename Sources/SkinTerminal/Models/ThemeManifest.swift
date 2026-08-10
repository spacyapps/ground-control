import Foundation

/// A decoded `theme.json`. Pure data — no AppKit, per the layering rule in
/// docs/STRUCTURE.md.
///
/// **Everything is optional.** A theme overrides only what it sets and an empty
/// `{}` is valid; code defaults fill the rest (docs/THEMING.md). That is why
/// every property here is an Optional rather than carrying its own default —
/// "absent" and "explicitly set" must stay distinguishable so merging works.
struct ThemeManifest: Decodable, Equatable {
    var manifestVersion: Int?
    var name: String?
    var author: String?
    var description: String?
    var colors: [String: String]?
    var assets: [String: String?]?
    var avatar: Avatar?
    var layout: Layout?
    var typography: Typography?

    struct Avatar: Decodable, Equatable {
        var size: Double?
        var position: String?
        var cornerRadius: Double?
        var states: [String: State]?

        struct State: Decodable, Equatable {
            var image: String?
            var video: String?
            var loop: Bool?
            var muted: Bool?
        }
    }

    struct Layout: Decodable, Equatable {
        var rowMaxHeight: Double?
        var rowPadding: Double?
        var marqueeOnOverflow: Bool?
        var marqueeSpeed: Double?
        var density: String?
    }

    struct Typography: Decodable, Equatable {
        var fontFamily: String?
        var nameSize: Double?
        var messageSize: Double?
        var nameWeight: String?
    }

    static let empty = ThemeManifest()
}
