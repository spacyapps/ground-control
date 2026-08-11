// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The SpacyApps mark, bundled with the app.
///
/// Loaded through `Bundle.module`, so it works identically from `swift run` and
/// from a packaged `.app`. A theme may replace the panel's mark via the
/// `brandMark` asset key; the Settings window always shows the real one, since
/// that surface belongs to the app rather than to a theme.
enum Brand {
    static let name = "SpacyApps"
    static let website = URL(string: "https://www.spacyapps.com")

    static func openWebsite() {
        guard let website else { return }
        NSWorkspace.shared.open(website)
    }

    /// Full lockup — mark plus wordmark. Illegible below ~120pt wide.
    static var lockup: NSImage? { image(named: "logo-lockup") }

    /// The mark alone, for anywhere too small for the wordmark.
    static var glyph: NSImage? { image(named: "logo-glyph") }

    private static let cache = NSCache<NSString, NSImage>()

    private static func image(named name: String) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            Log.ui.notice("Brand asset missing: \(name, privacy: .public)")
            return nil
        }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}
