// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Turns a hook's `session_id` into the id Claude Desktop calls its own.
///
/// Claude for Desktop's Code tab spawns a real Claude Code as a child, so its
/// sessions report through the ordinary hooks and appear in the panel like any
/// other. Clicking one could only ever raise the app, though: the window opens
/// on whatever conversation was last shown, which is rarely the one you clicked.
///
/// The app answers a `claude://` URL, and `code/continue?session=local_…` opens
/// one named conversation. The name it wants is its own — `local_` plus a
/// UUID — and the hook gives us the CLI's UUID instead. The join is written
/// down by the app itself: one small JSON per session under
/// `claude-code-sessions/<account>/<workspace>/local_<uuid>.json`, carrying
/// **`cliSessionId`** beside its own `sessionId`.
///
/// So this reads those files. That makes Claude for Desktop the third
/// application whose private storage Ground Control looks at, after Grok Bot's
/// cache and Grok's session folder, and the privacy page says so — a page that
/// described hooks as the only source was already wrong once.
///
/// It is also an undocumented layout in somebody else's app, which moved under
/// this project once already (Grok Bot's roster, schemaVersion 3 → 4, took the
/// alarm with it). So every failure here is a shrug: no file, no match,
/// unreadable JSON, archived session — all return nil, and the click falls
/// back to raising the app exactly as it does today.
enum ClaudeDesktopSessions {
    static let bundleID = "com.anthropic.claudefordesktop"

    /// Its own ids look like `local_` + a UUID, which is what the app's URL
    /// handler validates against before it will act.
    private static let localID = #"^local_[A-Za-z0-9-]{1,64}$"#

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("claude-code-sessions", isDirectory: true)
    }

    /// The `local_…` id for a hook session id, or nil if it cannot be found.
    ///
    /// Archived sessions are skipped: the app's own handler filters them out,
    /// so a link naming one would land nowhere and look like a broken click.
    static func localSessionID(for sessionID: String, in directory: URL = defaultDirectory) -> String? {
        guard !sessionID.isEmpty else { return nil }

        for file in recordFiles(in: directory) {
            guard
                let data = BoundedRead.data(at: file, limit: BoundedRead.manifestLimit),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["cliSessionId"] as? String == sessionID,
                json["isArchived"] as? Bool != true,
                let local = json["sessionId"] as? String,
                local.range(of: localID, options: .regularExpression) != nil
            else { continue }
            return local
        }
        return nil
    }

    /// `<directory>/<account>/<workspace>/local_*.json`, two levels down.
    ///
    /// Enumerated rather than globbed so a folder that is absent, unreadable or
    /// shaped differently after an update is simply empty rather than an error.
    private static func recordFiles(in directory: URL) -> [URL] {
        let manager = FileManager.default
        func children(of url: URL) -> [URL] {
            (try? manager.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
        }
        return children(of: directory)
            .flatMap(children(of:))
            .flatMap(children(of:))
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("local_") }
    }

    /// The deep link that opens one conversation. `code/continue` is the app's
    /// own route, and it validates the id before acting.
    static func continueURL(localSessionID: String) -> URL? {
        guard localSessionID.range(of: localID, options: .regularExpression) != nil else { return nil }
        return URL(string: "claude://code/continue?session=\(localSessionID)&source=groundcontrol")
    }
}
