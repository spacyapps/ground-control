// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import Foundation

/// Canonical folder locations.
///
/// The app only ever reads the sessions folder. Everything environment-shaped
/// (session id, display name, tty) is resolved by `Scripts/cc-notify` and
/// written into the JSON lines — see docs/STRUCTURE.md.
enum Paths {
    /// `${TMPDIR}/skinterminal/`, falling back to `/tmp/skinterminal/`.
    /// Must stay in step with `sessions_dir()` in Scripts/cc-notify.
    static var sessionsRoot: URL {
        let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        return URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent("skinterminal", isDirectory: true)
    }

    /// One file per subagent, named `<session_id>__<agent_id>.jsonl`.
    static var agentsRoot: URL {
        sessionsRoot.appendingPathComponent("agents", isDirectory: true)
    }

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("SkinTerminal", isDirectory: true)
    }

    /// Where users drop theme folders. Each subfolder holds one `theme.json`.
    static var userThemes: URL {
        applicationSupport.appendingPathComponent("Themes", isDirectory: true)
    }

    /// Creates the folders the app expects to read. Safe to call repeatedly.
    static func ensureFoldersExist() {
        for url in [sessionsRoot, agentsRoot, userThemes] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
