// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import Foundation

/// Takes you to the session you clicked.
///
/// Best where it can be: iTerm2 and Terminal expose a tty per tab, so those
/// land on the exact tab. Nothing else does — VS Code and its forks, Warp,
/// Ghostty and WezTerm all own real ptys that belong to no scriptable tab — so
/// for those the destination is the application itself, which at least puts the
/// session in front of you instead of opening Finder at the folder.
///
/// The decision is separated from the doing so the whole matrix is testable
/// without a running app or an AppleScript permission prompt.
enum TerminalFocuser {
    /// Where a click should land, in order of how well it identifies the
    /// session.
    enum Destination: Equatable {
        /// An exact tab in a terminal we can script.
        case terminalTab(tty: String, bundleID: String)
        /// One named conversation inside Claude for Desktop, which has no
        /// terminal and no tab but does answer a `claude://` URL.
        case claudeDesktopSession(localID: String)
        /// The application hosting the terminal. No tab, but the right window
        /// manager, and better than a file browser.
        case application(bundleID: String)
        /// Nothing reachable; show the folder instead.
        case finder(path: String)
        case nowhere
    }

    /// The bits of the running system the decision depends on, injected so
    /// tests can state a machine rather than need one.
    struct Probe {
        var isBundleRunning: (String) -> Bool = { bundleID in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
        var bundleID: (String) -> String? = { path in
            Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
        }
        /// Claude for Desktop's own id for a hook session, read from its
        /// storage. Returns nil whenever anything is missing, which is what
        /// keeps this from becoming a dependency.
        var claudeDesktopSession: (String) -> String? = { sessionID in
            ClaudeDesktopSessions.localSessionID(for: sessionID)
        }
    }

    /// Terminals we know how to drive, in preference order.
    private struct SupportedTerminal {
        let bundleID: String
        let script: (String) -> String
    }

    private static let supported = [
        SupportedTerminal(bundleID: "com.googlecode.iterm2", script: iTermScript(tty:)),
        SupportedTerminal(bundleID: "com.apple.Terminal", script: terminalScript(tty:))
    ]

    // MARK: - Deciding

    /// Resolves where a session's click should go.
    ///
    /// An exact tab wins whenever one is available. The host application comes
    /// next — including when the tty is set but its tab has since been closed,
    /// where the app is still the right place to arrive.
    static func destination(tty: String?,
                            hostApp: String?,
                            hostID: String?,
                            fallbackPath: String?,
                            sessionID: String? = nil,
                            probe: Probe = Probe()) -> Destination {
        let host = hostBundleID(hostApp: hostApp, hostID: hostID, probe: probe)

        // Claude for Desktop has no tty to find and several conversations in
        // one window, so raising it lands on whichever was last open. Its own
        // URL handler will open a named one, if its id can be found; if it
        // cannot, this falls through and the app is raised as before.
        if host == ClaudeDesktopSessions.bundleID,
           let sessionID,
           let local = probe.claudeDesktopSession(sessionID) {
            return .claudeDesktopSession(localID: local)
        }

        // A tty belongs to whichever app opened it, so a session hosted by VS
        // Code has no tab in Terminal however many tabs Terminal has. Searching
        // there anyway found nothing and then raised Terminal — the wrong app,
        // and confidently. When the host is unknown, which is any session
        // written before host_app existed, searching every running terminal is
        // still the best available guess.
        if let tty, isDeviceTTY(tty) {
            for terminal in supported
            where probe.isBundleRunning(terminal.bundleID)
                && (host == nil || host == terminal.bundleID) {
                return .terminalTab(tty: tty, bundleID: terminal.bundleID)
            }
        }

        if let host, probe.isBundleRunning(host) {
            return .application(bundleID: host)
        }

        if let fallbackPath, !fallbackPath.isEmpty {
            return .finder(path: fallbackPath)
        }
        return .nowhere
    }

    /// A tty is a device path — `/dev/ttys008` — and it is about to be pasted
    /// into an AppleScript source string. Anything with a quote, a space, a
    /// newline or a `..` in it did not come from a terminal: it was written
    /// into a `.jsonl` file to break out of that string and run its own script.
    /// Such a value is treated as "no tty" — the click lands on the host app
    /// instead, which is a worse landing, not a compromised one.
    static func isDeviceTTY(_ tty: String) -> Bool {
        tty.range(of: #"^/dev/[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }

    /// The app that owns the session, as a bundle id.
    ///
    /// The path is preferred over the inherited id: it reports what actually
    /// spawned this session, where `__CFBundleIdentifier` reports what was
    /// inherited — stale if the editor was itself launched from a terminal.
    private static func hostBundleID(hostApp: String?,
                                     hostID: String?,
                                     probe: Probe) -> String? {
        for candidate in [hostApp.flatMap(probe.bundleID), hostID] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }

    // MARK: - Doing

    /// Goes there. Returns whether the click actually landed on the session —
    /// which is what decides whether its alarm may be cleared, so revealing a
    /// folder does not count.
    @discardableResult
    static func focus(tty: String?,
                      hostApp: String?,
                      hostID: String?,
                      fallbackPath: String?,
                      sessionID: String? = nil) -> Bool {
        let target = destination(
            tty: tty,
            hostApp: hostApp,
            hostID: hostID,
            fallbackPath: fallbackPath,
            sessionID: sessionID
        )
        switch target {
        case .terminalTab(let tty, let bundleID):
            if let terminal = supported.first(where: { $0.bundleID == bundleID }),
               run(terminal.script(tty)) {
                return true
            }
            // The tab has been closed. Ask again as if there were no tty at
            // all, which lands on the host app or the folder — never on the
            // terminal we just failed to find it in.
            Log.integration.notice("No tab matched \(tty, privacy: .public); trying the host")
            return focus(tty: nil, hostApp: hostApp, hostID: hostID, fallbackPath: fallbackPath)

        case .claudeDesktopSession(let localID):
            guard let url = ClaudeDesktopSessions.continueURL(localSessionID: localID) else {
                return activate(bundleID: ClaudeDesktopSessions.bundleID)
            }
            NSWorkspace.shared.open(url)
            return true

        case .application(let bundleID):
            return activate(bundleID: bundleID)

        case .finder(let path):
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            return false

        case .nowhere:
            return false
        }
    }

    /// Whether a click has anywhere to land — the cheap question, asked once
    /// per row on every list update. `destinationName` answers a richer one and
    /// costs a display-name lookup for it.
    static func canReach(tty: String?, hostApp: String?, hostID: String?) -> Bool {
        switch destination(tty: tty, hostApp: hostApp, hostID: hostID, fallbackPath: nil) {
        case .terminalTab, .application, .claudeDesktopSession: return true
        case .finder, .nowhere: return false
        }
    }

    /// A human-readable name for where a click will go, for the row's menu.
    ///
    /// Both cases name the app itself rather than a category: a session in
    /// iTerm said "Jump to Terminal", which is the name of a different app.
    ///
    /// The bundle's name on disk is preferred over the running process's:
    /// `localizedName` for VS Code is "Code", so the menu offered "Jump to
    /// Code" for something every person calls Visual Studio Code.
    static func destinationName(tty: String?, hostApp: String?, hostID: String?) -> String? {
        switch destination(tty: tty, hostApp: hostApp, hostID: hostID, fallbackPath: nil) {
        // Not passed a session id, so this never resolves to a named
        // conversation — the menu says "Jump to Claude", which is true of
        // either landing and does not promise the exact one.
        case .claudeDesktopSession:
            return FileManager.default.displayName(atPath: "/Applications/Claude.app")
                .replacingOccurrences(of: ".app", with: "")
        case .terminalTab(_, let bundleID), .application(let bundleID):
            let running = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first
            if let path = running?.bundleURL?.path {
                // displayName keeps the extension unless Finder is set to hide
                // it, and "Jump to Visual Studio Code.app" reads like a file.
                var name = FileManager.default.displayName(atPath: path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                if !name.isEmpty { return name }
            }
            return running?.localizedName
        case .finder, .nowhere:
            return nil
        }
    }

    private static func activate(bundleID: String) -> Bool {
        // Never launched, only raised: a session lives in an app that is
        // already running, and starting an empty copy would be a lie about
        // having arrived.
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first else { return false }

        // Through NSWorkspace rather than NSRunningApplication.activate:
        // recent macOS only lets the frontmost app raise another, and this one
        // is an accessory whose panel is deliberately non-activating, so it is
        // never frontmost. openApplication is the sanctioned route and, for an
        // app already running, activates rather than launching a second copy.
        guard let url = app.bundleURL else { return app.activate() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                let reason = error.localizedDescription
                Log.integration.error("Could not raise \(bundleID, privacy: .public): \(reason, privacy: .public)")
            }
        }
        return true
    }

    // MARK: - Scripts

    /// iTerm2 exposes the tty per session directly, so the match is exact.
    /// Addressed by bundle id rather than name so a missing app errors quietly
    /// instead of prompting.
    private static func iTermScript(tty: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            select t
                            select s
                            activate
                            return "yes"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "no"
        """
    }

    /// Terminal.app exposes `tty` on a tab and needs the window raised
    /// separately — weaker than iTerm's path, but it does match exactly.
    private static func terminalScript(tty: String) -> String {
        """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "yes"
                    end if
                end repeat
            end repeat
        end tell
        return "no"
        """
    }

    private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        let result = script.executeAndReturnError(&error)
        if let error {
            Log.integration.error("AppleScript failed: \(String(describing: error), privacy: .public)")
            return false
        }
        return result.stringValue == "yes"
    }
}
