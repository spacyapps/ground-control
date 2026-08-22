// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Which application a row belongs to, decided in `cc-notify` by climbing the
/// process tree.
///
/// This is the field that decides where a click lands, and it is invisible
/// until it is wrong: the row appears, the alarm works, and then clicking it
/// opens Finder. It cost a real report — Claude for Desktop runs its own bundled
/// copy of the CLI from `~/Library/Application Support`, which is a genuine
/// `.app` and so was the first match while never being an app anyone can switch
/// to.
///
/// Exercised against synthetic ancestries rather than the live tree, because
/// the interesting cases are hosts that are not running while the tests are.
final class HostAppResolutionTests: XCTestCase {
    /// Runs `resolve_host_app` against a fabricated chain of executables,
    /// innermost first, and returns what it picked.
    private func hostApp(for chain: [String]) throws -> String {
        let emitter = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/cc-notify").path

        let harness = """
        import importlib.util, os, json, sys
        mod = importlib.util.module_from_spec(
            importlib.util.spec_from_loader("ccn", loader=None))
        exec(compile(open(sys.argv[1]).read(), "cc-notify", "exec"), mod.__dict__)
        chain, BASE = json.loads(sys.argv[2]), 100
        class Fake:
            def entry(self, pid):
                i = pid - BASE
                return None if i < 0 or i >= len(chain) else (pid + 1, None, chain[i])
        os.getppid = lambda: BASE
        print(mod.resolve_host_app(Fake()) or "")
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        let json = String(data: try JSONSerialization.data(withJSONObject: chain), encoding: .utf8)
        process.arguments = ["-c", harness, emitter, json ?? "[]"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The report: the click went to Finder because the inner bundle is not a
    /// switchable app, so `isBundleRunning` was false and the destination fell
    /// through. The answer has to be the app in the Dock.
    func testDesktopAppResolvesToTheAppYouCanSwitchTo() throws {
        let inner = "\(NSHomeDirectory())/Library/Application Support/Claude"
            + "/claude-code/2.1.237/claude.app/Contents/MacOS/claude"
        let resolved = try hostApp(for: [
            "/bin/zsh",
            inner,
            "/Applications/Claude.app/Contents/MacOS/Claude",
            "/sbin/launchd"
        ])
        XCTAssertEqual(resolved, "/Applications/Claude.app")
    }

    /// The hosts that already worked must keep resolving to the same app, which
    /// is the whole risk in preferring the topmost ancestor over the first.
    func testTheHostsThatAlreadyWorkedAreUnchanged() throws {
        let terminal = "/System/Applications/Utilities/Terminal.app"
        XCTAssertEqual(
            try hostApp(for: ["/bin/zsh", "/x/claude", terminal + "/Contents/MacOS/Terminal", "/sbin/launchd"]),
            terminal
        )
        XCTAssertEqual(
            try hostApp(for: ["/bin/zsh", "/Applications/Xcode.app/Contents/MacOS/Xcode", "/sbin/launchd"]),
            "/Applications/Xcode.app"
        )
    }

    /// A helper nested inside a real app was already handled, by climbing out
    /// of the bundle path. This checks the two mechanisms agree rather than
    /// fight: the renderer is inside Code.app, and Code.app is also an ancestor.
    func testANestedHelperStillNamesItsOwnApp() throws {
        let code = "/Applications/Visual Studio Code.app"
        let resolved = try hostApp(for: [
            "/bin/zsh",
            code + "/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper",
            code + "/Contents/MacOS/Electron",
            "/sbin/launchd"
        ])
        XCTAssertEqual(resolved, code)
    }

    /// No app in the ancestry at all is the normal case under tmux or a daemon,
    /// and must stay empty rather than inventing a host.
    func testAnAncestryWithNoAppNamesNothing() throws {
        XCTAssertEqual(
            try hostApp(for: ["/bin/zsh", "/usr/local/bin/tmux", "/sbin/launchd"]),
            ""
        )
    }
}
