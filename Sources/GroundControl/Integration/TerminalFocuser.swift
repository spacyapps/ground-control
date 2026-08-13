// SPDX-License-Identifier: GPL-3.0-or-later
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
                            probe: Probe = Probe()) -> Destination {
        if let tty, !tty.isEmpty {
            for terminal in supported where probe.isBundleRunning(terminal.bundleID) {
                return .terminalTab(tty: tty, bundleID: terminal.bundleID)
            }
        }

        // The path is preferred over the inherited bundle id: it reports what
        // actually spawned the session, where `__CFBundleIdentifier` reports
        // what was inherited — which is stale if the app was launched from
        // another terminal.
        for candidate in [hostApp.flatMap(probe.bundleID), hostID] {
            if let candidate, !candidate.isEmpty, probe.isBundleRunning(candidate) {
                return .application(bundleID: candidate)
            }
        }

        if let fallbackPath, !fallbackPath.isEmpty {
            return .finder(path: fallbackPath)
        }
        return .nowhere
    }

    // MARK: - Doing

    /// Goes there. Returns whether the click actually landed on the session —
    /// which is what decides whether its alarm may be cleared, so revealing a
    /// folder does not count.
    @discardableResult
    static func focus(tty: String?,
                      hostApp: String?,
                      hostID: String?,
                      fallbackPath: String?) -> Bool {
        switch destination(tty: tty, hostApp: hostApp, hostID: hostID, fallbackPath: fallbackPath) {
        case .terminalTab(let tty, let bundleID):
            guard let terminal = supported.first(where: { $0.bundleID == bundleID }) else { return false }
            if run(terminal.script(tty)) { return true }
            // The tab has gone but the app is still up: arriving at the app
            // beats dropping the user in Finder.
            Log.integration.notice("No tab matched \(tty, privacy: .public); raising the app")
            return activate(bundleID: bundleID)

        case .application(let bundleID):
            return activate(bundleID: bundleID)

        case .finder(let path):
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            return false

        case .nowhere:
            return false
        }
    }

    /// A human-readable name for where a click will go, for the row's menu.
    static func destinationName(tty: String?, hostApp: String?, hostID: String?) -> String? {
        switch destination(tty: tty, hostApp: hostApp, hostID: hostID, fallbackPath: nil) {
        case .terminalTab:
            return "Terminal"
        case .application(let bundleID):
            return NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first?.localizedName
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
        return app.activate(options: [.activateAllWindows])
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
