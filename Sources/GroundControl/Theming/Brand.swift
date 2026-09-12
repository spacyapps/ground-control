// SPDX-License-Identifier: AGPL-3.0-or-later
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

    /// Where more themes come from.
    ///
    /// Named here beside the website rather than written into a button, because
    /// it is the only route out of the app to anything for sale and it should
    /// be findable in one place when it moves.
    static let themeStore = URL(string: "https://www.spacyapps.com/apps/ground-control/themes")

    /// The running version as `0.7.3 (8)` — marketing version, then the build
    /// number in parentheses, the macOS convention.
    ///
    /// Read from the app bundle's `Info.plist`, which `build-app.sh` copies from
    /// `Packaging/Info.plist`. A `swift run` executable carries neither key, so
    /// that case says so rather than showing a blank.
    static var versionLine: String {
        versionLine(
            short: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
    }

    /// The formatting, split out so a test can pin it without a bundle.
    static func versionLine(short: String?, build: String?) -> String {
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        default: return "dev build"
        }
    }

    static func openWebsite() {
        guard let website else { return }
        NSWorkspace.shared.open(website)
    }

    static func openThemeStore() {
        guard let themeStore else { return }
        NSWorkspace.shared.open(themeStore)
    }

    /// Full lockup — mark plus wordmark. Illegible below ~120pt wide.
    ///
    /// This is SpacyApps, the maker, and stays that way: Settings is where you
    /// see who wrote the thing.
    static var lockup: NSImage? { image(named: "logo-lockup") }

    /// The app's own icon, for the panel — that surface is Ground Control
    /// rather than its publisher, and the icon is what a person recognises it
    /// by everywhere else.
    static var glyph: NSImage? { image(named: "app-mark") }

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
