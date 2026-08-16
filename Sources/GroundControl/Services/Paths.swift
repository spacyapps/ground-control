// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Canonical folder locations.
///
/// The app only ever reads the sessions folder. Everything environment-shaped
/// (session id, display name, tty) is resolved by `Scripts/cc-notify` and
/// written into the JSON lines — see docs/STRUCTURE.md.
enum Paths {
    /// `${TMPDIR}/groundcontrol/`, falling back to `/tmp/groundcontrol/`.
    /// Must stay in step with `sessions_dir()` in Scripts/cc-notify.
    static var sessionsRoot: URL {
        let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        return URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent("groundcontrol", isDirectory: true)
    }

    /// One file per subagent, named `<session_id>__<agent_id>.jsonl`.
    static var agentsRoot: URL {
        sessionsRoot.appendingPathComponent("agents", isDirectory: true)
    }

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("GroundControl", isDirectory: true)
    }

    /// Where users drop theme folders. Each subfolder holds one `theme.json`.
    static var userThemes: URL {
        applicationSupport.appendingPathComponent("Themes", isDirectory: true)
    }

    /// The emitter and the uninstaller: `~/.groundcontrol/bin`.
    ///
    /// **The path must not contain a space.** Claude Code runs a hook command
    /// through `/bin/sh`, which word-splits — an emitter under "Application
    /// Support" was executed as `/Users/you/Library/Application` and failed on
    /// every event. Quoting the registration would fix that runner and might
    /// break Cursor, which may exec directly and would then look for a path
    /// containing quote characters.
    ///
    /// Not inside the app: a registration is an absolute path and bundles move.
    /// Not `~/bin`, which belongs to the user. `~/.groundcontrol` sits beside
    /// `~/.claude` and `~/.cursor`, which is the company it keeps.
    static var binRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".groundcontrol", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    /// Creates the folders the app expects to read. Safe to call repeatedly.
    static func ensureFoldersExist() {
        for url in [sessionsRoot, agentsRoot, userThemes] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
