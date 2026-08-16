// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Keeps the installed hook emitter in step with the app that reads it.
///
/// `cc-notify` and Ground Control are two halves of one contract: the script
/// writes the fields the app draws from. They are installed separately, so they
/// drift — and the failure is silent, because an older script simply omits
/// fields and the app falls back. A whole morning went into a click landing in
/// Finder that turned out to be a binary forty-four seconds newer than the
/// process running it.
///
/// So on launch, if the emitter is already installed and differs from the copy
/// inside the app, it is replaced with ours.
///
/// **This direction is only right when the app is the newer half**, which it
/// always is for anyone who installed it. While developing it is backwards: run
/// a stale build after editing `cc-notify` and the app quietly puts its own
/// older copy back, the hook loses whatever was just added, and the symptom
/// appears in code that is perfectly correct. It cost an hour once — every
/// Cursor row came out named `.cursor` because the reinstalled emitter had been
/// replaced by a build from before `workspace_roots` was understood. Rebuild
/// after touching the script, and the bundle carries what you wrote.
///
/// **Only ever updates, never installs.** An absent `cc-notify` means the user
/// has not run the installer, and writing one uninvited is not this app's
/// business — nor would it help, since nothing would be registered to call it.
/// The menu offers to run the installer; that is an invitation, not an
/// assumption. Settings are never touched: the registration lives in
/// `~/.claude/settings.json` and is the installer's job alone.
enum HookUpdater {
    /// Where the installer puts it. Must match `install-hooks.sh`, or the app
    /// keeps a file up to date that nothing calls.
    static var installed: URL {
        Paths.binRoot.appendingPathComponent("cc-notify")
    }

    /// The copy that shipped inside the app.
    static var bundled: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("cc-notify")
    }

    @discardableResult
    static func updateIfNeeded(bundled source: URL? = bundled,
                               installed target: URL = installed) -> Bool {
        let manager = FileManager.default
        guard let source,
              manager.fileExists(atPath: source.path),
              manager.fileExists(atPath: target.path) else { return false }

        guard let shipped = try? Data(contentsOf: source) else { return false }
        // Byte comparison rather than dates: a reinstall, a copy, or a clock
        // that went backwards all move the timestamp without changing what the
        // script does.
        if let current = try? Data(contentsOf: target), current == shipped { return false }

        do {
            try shipped.write(to: target, options: .atomic)
            // An atomic write replaces the file, and the replacement does not
            // inherit the executable bit — without which the hook silently
            // stops running, which is the exact failure this is meant to end.
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            Log.integration.notice("Updated cc-notify to the version shipped with this app")
            return true
        } catch {
            Log.integration.error("Could not update cc-notify: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
