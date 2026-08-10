import AppKit
import Foundation

/// Jumps to the terminal tab a session is running in, matched on tty.
///
/// Jump is **best-effort** (docs/SPEC.md §7): `tty` can be nil when a session
/// started outside a terminal or the script's process-tree walk failed. A nil
/// tty degrades one row's click, never the row itself — so callers get a Bool
/// and fall back to revealing the folder.
///
/// The first AppleScript triggers a one-time macOS Automation permission
/// prompt.
enum TerminalFocuser {
    @discardableResult
    static func focus(tty: String?, fallbackPath: String?) -> Bool {
        if let tty, !tty.isEmpty, jump(to: tty) { return true }

        if let fallbackPath, !fallbackPath.isEmpty {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fallbackPath)
            return false
        }
        return false
    }

    private static func jump(to tty: String) -> Bool {
        for script in [iTermScript(tty: tty), terminalScript(tty: tty)] where run(script) {
            return true
        }
        Log.integration.notice("No terminal tab matched \(tty, privacy: .public)")
        return false
    }

    /// iTerm2 exposes the tty per session directly, so the match is exact.
    private static func iTermScript(tty: String) -> String {
        """
        tell application "System Events"
            if not (exists process "iTerm2") then return "no"
        end tell
        tell application "iTerm2"
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
        tell application "System Events"
            if not (exists process "Terminal") then return "no"
        end tell
        tell application "Terminal"
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
