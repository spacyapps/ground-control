// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// A resolved background image and how it should fill a box that changes size.
struct BackgroundImage: Equatable {
    let url: URL
    let mode: Mode
    let capInsets: NSEdgeInsets
    /// Applied once when the image is decoded, so a generated file works
    /// without any separate tool.
    let removeBackground: ImageKeyer.Key?

    /// Most backgrounds carry their own alpha, so keying defaults to off.
    init(url: URL,
         mode: Mode,
         capInsets: NSEdgeInsets,
         removeBackground: ImageKeyer.Key? = nil) {
        self.url = url
        self.mode = mode
        self.capInsets = capInsets
        self.removeBackground = removeBackground
    }

    /// Whether AppKit draws this through its resizable-image path rather than
    /// simply painting the picture into the rect.
    ///
    /// `tile` always does — it repeats the art whether or not caps divide it —
    /// and `stretch` does once caps are set. The two paths disagree about which
    /// way up a flipped context is, so the renderer has to know which it will
    /// get. Established by measuring all four combinations, not from the docs.
    var usesResizableDrawing: Bool {
        switch mode {
        case .tile: return true
        case .stretch:
            return capInsets.top + capInsets.left + capInsets.bottom + capInsets.right > 0
        case .center, .aspectFill: return false
        }
    }

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
            && lhs.removeBackground == rhs.removeBackground
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
        return "\(url.path)|\(mode.rawValue)|\(insets)|\(String(describing: removeBackground))"
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
