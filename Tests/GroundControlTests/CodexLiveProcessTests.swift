// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Parsing is tested from output captured off a real running `codex`
/// (2026-09-11), not invented — the shapes below are verbatim.
final class CodexLiveProcessTests: XCTestCase {
    // MARK: - ps

    func testOnlyProcessesNamedExactlyCodexCount() {
        let listing = """
        33266 codex
        33270 Code Helper
        33280 codex-helper
        33290 codexd
          412 Terminal
        """
        XCTAssertEqual(CodexLiveProcess.pids(fromPS: listing), [33266])
    }

    func testAnEmptyListingIsNoProcesses() {
        XCTAssertTrue(CodexLiveProcess.pids(fromPS: "").isEmpty)
    }

    // MARK: - lsof

    /// Verbatim from `lsof -p 33266` on a live session.
    private let realLsof = """
    COMMAND   PID      USER   FD   TYPE DEVICE  SIZE/OFF     NODE NAME
    codex   33266 waltermak  cwd    DIR   1,18        64 12172415 /Users/waltermak/github/empty2
    codex   33266 waltermak  txt    REG   1,18   4067968 14775871 /opt/homebrew/bin/codex
    codex   33266 waltermak   0u    CHR  16,12 0t1612933     1011 /dev/ttys012
    codex   33266 waltermak   1u    CHR  16,12 0t1612933     1011 /dev/ttys012
    codex   33266 waltermak   2w    CHR    3,2       0t0      336 /dev/null
    codex   33266 waltermak  10u    CHR  16,12 0t1612933     1011 /dev/ttys012
    """

    func testRealLsofYieldsBothCwdAndTTY() throws {
        let found = try XCTUnwrap(CodexLiveProcess.cwdAndTTY(fromLsof: realLsof))
        XCTAssertEqual(found.cwd, "/Users/waltermak/github/empty2")
        XCTAssertEqual(found.tty, "/dev/ttys012")
    }

    func testDevNullIsNotMistakenForATTY() throws {
        let onlyNull = """
        codex 33266 waltermak  cwd    DIR   1,18        64 12172415 /Users/you/repo
        codex 33266 waltermak   2w    CHR    3,2       0t0      336 /dev/null
        """
        let found = try XCTUnwrap(CodexLiveProcess.cwdAndTTY(fromLsof: onlyNull))
        XCTAssertEqual(found.cwd, "/Users/you/repo")
        XCTAssertNil(found.tty, "only /dev/ttys… is a terminal; /dev/null is not")
    }

    func testNoCwdRowMeansNoMatchAtAll() {
        let noCwd = "codex 33266 waltermak   0u    CHR  16,12 0t1612933     1011 /dev/ttys012"
        XCTAssertNil(CodexLiveProcess.cwdAndTTY(fromLsof: noCwd))
    }

    /// A path with spaces must survive — NAME is everything from field 8 on,
    /// not just the last whitespace-separated token.
    func testAPathWithSpacesIsNotTruncated() throws {
        let spaced = "codex 33266 waltermak  cwd    DIR   1,18   64 12172415 /Users/you/My Projects/thing"
        let found = try XCTUnwrap(CodexLiveProcess.cwdAndTTY(fromLsof: spaced))
        XCTAssertEqual(found.cwd, "/Users/you/My Projects/thing")
    }

    // MARK: - Finding the app in an ancestry

    func testTheOutermostBundleWins() {
        XCTAssertEqual(
            CodexLiveProcess.appBundlePath(
                fromCommand: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
            ),
            "/System/Applications/Utilities/Terminal.app"
        )
    }

    /// The trap `cc-notify` already documents: an Electron helper is a bundle
    /// inside a bundle, and the nearest one is the wrong answer — every
    /// Electron app shares it.
    func testANestedHelperResolvesToTheOuterApp() {
        XCTAssertEqual(
            CodexLiveProcess.appBundlePath(
                fromCommand: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
            ),
            "/Applications/Visual Studio Code.app"
        )
    }

    func testAPlainShellIsNotAnApp() {
        XCTAssertNil(CodexLiveProcess.appBundlePath(fromCommand: "-zsh"))
        XCTAssertNil(CodexLiveProcess.appBundlePath(fromCommand: "login"))
        XCTAssertNil(CodexLiveProcess.appBundlePath(fromCommand: "codex"))
    }

    // MARK: - The walk, against a captured ancestry

    /// Verbatim from the real chain: codex → zsh → login → Terminal.app.
    func testTheWalkReachesTheTerminalApp() throws {
        let chain: [String: String] = [
            "33266": "17729 codex",
            "17729": "17728 -zsh",
            "17728": "1407 login",
            "1407": "1 /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
        ]
        let runner: ([String]) -> String? = { arguments in
            guard arguments.first == "/bin/ps", let pid = arguments.last else { return nil }
            return chain[pid]
        }
        let match = CodexLiveProcess.terminal(forPID: 33266, tty: "/dev/ttys012", runner: runner)
        XCTAssertEqual(match.tty, "/dev/ttys012")
        XCTAssertEqual(match.hostApp, "/System/Applications/Utilities/Terminal.app")
    }

    func testAWalkThatNeverFindsAnAppGivesNoHost() {
        let runner: ([String]) -> String? = { _ in "1 launchd" }
        let match = CodexLiveProcess.terminal(forPID: 42, tty: "/dev/ttys001", runner: runner)
        XCTAssertEqual(match.tty, "/dev/ttys001", "a tty with no nameable host is still a tty")
        XCTAssertNil(match.hostApp)
    }

    func testAWalkThatLoopsTerminatesRatherThanSpinning() {
        // Every pid claims the same parent — bounded, so this must return.
        let runner: ([String]) -> String? = { _ in "99 some-process" }
        let match = CodexLiveProcess.terminal(forPID: 99, tty: nil, runner: runner)
        XCTAssertNil(match.hostApp)
    }

    // MARK: - Not asking the system more than it is worth

    func testASecondLookupInsideTheWindowIsServedFromCache() {
        CodexLiveProcess.clearCache()
        var calls = 0
        let runner: ([String]) -> String? = { arguments in
            calls += 1
            if arguments.first == "/bin/ps" { return "33266 codex" }
            return "codex 33266 you cwd DIR 1,18 64 1 /Users/you/repo"
        }
        let start = Date()
        _ = CodexLiveProcess.all(now: start, runner: runner)
        let afterFirst = calls
        XCTAssertGreaterThan(afterFirst, 0, "the first lookup must actually ask")

        _ = CodexLiveProcess.all(now: start.addingTimeInterval(1), runner: runner)
        _ = CodexLiveProcess.all(now: start.addingTimeInterval(2), runner: runner)
        XCTAssertEqual(calls, afterFirst, "polls inside the window must cost nothing")
    }

    func testThCacheExpiresSoANewlyStartedCodexIsStillFound() {
        CodexLiveProcess.clearCache()
        var calls = 0
        let runner: ([String]) -> String? = { arguments in
            calls += 1
            if arguments.first == "/bin/ps" { return "33266 codex" }
            return "codex 33266 you cwd DIR 1,18 64 1 /Users/you/repo"
        }
        let start = Date()
        _ = CodexLiveProcess.all(now: start, runner: runner)
        let afterFirst = calls
        _ = CodexLiveProcess.all(
            now: start.addingTimeInterval(CodexLiveProcess.cacheLifetime + 1), runner: runner
        )
        XCTAssertGreaterThan(calls, afterFirst, "past the window it must ask again")
    }
}
