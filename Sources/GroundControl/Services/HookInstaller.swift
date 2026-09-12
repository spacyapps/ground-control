// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Runs the shipped installer and uninstaller from the menu.
///
/// The first thing a new user has to do is run a script from inside an app
/// bundle in Terminal, which is the least friendly step in the product and the
/// very first one. This offers the same scripts as menu items.
///
/// It does not blur `HookUpdater`'s rule that the app never installs uninvited:
/// choosing a menu item *is* the invitation. Nothing here runs on its own.
enum HookInstaller {
    enum Script: String {
        case install = "install-hooks.sh"
        case uninstall = "uninstall-hooks.sh"

        var url: URL? { Bundle.main.resourceURL?.appendingPathComponent(rawValue) }
    }

    /// Asks first, runs, then says what happened.
    ///
    /// Both scripts edit files that belong to other applications — Claude's
    /// settings and Cursor's hooks — so neither should ever run on a stray
    /// click. Both are safe to repeat, which is what makes a plain retry the
    /// right answer when something goes wrong.
    /// Which integration to act on. The scripts default to every one when no
    /// target is given, which is what the menu and the README have always done.
    enum Target: String {
        case all
        case claude
        case cursor
        case opencode
        case codex

        var label: String {
            switch self {
            case .all: return "every agent"
            case .claude: return "Claude Code and Grok"
            case .cursor: return "Cursor"
            case .opencode: return "opencode"
            case .codex: return "Codex"
            }
        }
    }

    static func run(_ script: Script, target: Target = .all, silent: Bool = false) {
        guard let url = script.url, FileManager.default.fileExists(atPath: url.path) else {
            report(title: "Script missing",
                   body: "\(script.rawValue) is not in this build. Reinstall the app.",
                   isError: true)
            return
        }
        guard silent || confirm(script) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [url.path, target.rawValue]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            // Read before waiting: a script that outfills the pipe buffer would
            // block forever waiting for someone to drain it.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            if !silent { finish(script, code: process.terminationStatus, output: text) }
        } catch {
            report(title: "Could not run \(script.rawValue)",
                   body: error.localizedDescription,
                   isError: true)
        }
    }

    private static func confirm(_ script: Script) -> Bool {
        let alert = NSAlert()
        switch script {
        case .install:
            alert.messageText = "Set up agent hooks?"
            alert.informativeText = """
                This registers Ground Control with Claude Code, Grok, and Cursor \
                if it is installed, so they report what they are doing.

                Your existing hooks are kept — it merges rather than replaces, \
                and backs up each file first. Safe to run again at any time.
                """
            alert.addButton(withTitle: "Set Up")
        case .uninstall:
            alert.messageText = "Remove agent hooks?"
            alert.informativeText = """
                This unregisters Ground Control from Claude Code, Grok and \
                Cursor, and removes the emitter. Do this before dragging the app \
                to the Trash.

                Hooks belonging to anything else are left alone, and your themes \
                are not touched.
                """
            alert.addButton(withTitle: "Remove")
        }
        alert.addButton(withTitle: "Cancel")
        // Menu-bar apps are accessories: without this the alert can open behind
        // whatever the user was looking at, and it is waiting for an answer.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func finish(_ script: Script, code: Int32, output: String) {
        guard code == 0 else {
            report(title: "\(script.rawValue) failed",
                   body: output.isEmpty ? "Exit code \(code)." : output,
                   isError: true)
            return
        }
        switch script {
        case .install:
            report(
                title: "Hooks are set up",
                body: """
                    Open a new terminal and start Claude Code or Grok — one \
                    already running has not loaded them yet.

                    If Cursor was running, restart it: it reads its hooks file \
                    at startup.
                    """,
                isError: false
            )
        case .uninstall:
            report(
                title: "Hooks removed",
                body: """
                    Agent sessions stop reporting from their next launch. Your \
                    themes are still in Application Support if you want them.

                    You can quit and delete Ground Control now.
                    """,
                isError: false
            )
        }
    }

    private static func report(title: String, body: String, isError: Bool) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = isError ? .warning : .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
