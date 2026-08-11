import AppKit

/// A resolved background image and how it should fill a box that changes size.
struct BackgroundImage: Equatable {
    let url: URL
    let mode: Mode
    let capInsets: NSEdgeInsets

    /// How the art fills a box larger than itself.
    ///
    /// `tile` and `stretch` both honour `capInsets` — that is the nine-slice
    /// behaviour, where corners hold their size and only the edges and centre
    /// grow. `center` and `aspectFill` ignore insets and are for art that must
    /// stay proportional, like a mascot painted into the background.
    enum Mode: String {
        case tile
        case stretch
        case center
        case aspectFill
    }

    static func == (lhs: BackgroundImage, rhs: BackgroundImage) -> Bool {
        lhs.url == rhs.url
            && lhs.mode == rhs.mode
            && lhs.capInsets.top == rhs.capInsets.top
            && lhs.capInsets.left == rhs.capInsets.left
            && lhs.capInsets.bottom == rhs.capInsets.bottom
            && lhs.capInsets.right == rhs.capInsets.right
    }

    var hasCaps: Bool {
        capInsets.top > 0 || capInsets.left > 0 || capInsets.bottom > 0 || capInsets.right > 0
    }

    /// A stable key for caching the configured `NSImage`. Cap insets and
    /// resizing mode are properties *of* an NSImage, so two assets pointing at
    /// the same file with different settings must not share one instance.
    var cacheKey: String {
        let insets = "\(capInsets.top),\(capInsets.left),\(capInsets.bottom),\(capInsets.right)"
        return "\(url.path)|\(mode.rawValue)|\(insets)"
    }
}

extension Theme {
    /// Optional images that replace painted surfaces. Every one is nil by
    /// default; a theme that sets none looks exactly as it does today.
    struct Backgrounds: Equatable {
        var window: BackgroundImage?
        var titleBar: BackgroundImage?
        var footer: BackgroundImage?
        /// Replaces the drawn attention dot. Not a nine-slice — it is a small
        /// fixed badge, so it is simply scaled to fit.
        var needsActionDot: URL?
        /// Replaces the mark in the title bar. A theme that dresses the whole
        /// panel should be able to put its own stamp there.
        var brandMark: URL?

        static let none = Backgrounds()
    }
}
