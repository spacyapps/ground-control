// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Where a click lands, decided against a stated machine rather than the one
/// running the tests.
///
/// A tty only identifies a tab inside iTerm or Terminal. A session in VS Code's
/// integrated terminal has a perfectly good pty belonging to no scriptable tab,
/// so before `host_app` every one of those clicks opened Finder — and, because
/// only a landed jump clears an alarm, left the row's alarm up afterwards.
final class TerminalFocuserTests: XCTestCase {
    private let iTerm = "com.googlecode.iterm2"
    private let terminal = "com.apple.Terminal"
    private let vsCodePath = "/Applications/Visual Studio Code.app"
    private let vsCode = "com.microsoft.VSCode"

    /// A machine: which apps are running, and what each path's bundle id is.
    private func probe(running: Set<String>,
                       ids: [String: String] = [:]) -> TerminalFocuser.Probe {
        TerminalFocuser.Probe(
            isBundleRunning: { running.contains($0) },
            bundleID: { ids[$0] }
        )
    }

    /// A tab is the most precise destination there is, so it wins whenever the
    /// session is genuinely in a terminal we can script.
    ///
    /// This test used to pass a VS Code host and still expect an iTerm tab,
    /// which is exactly the bug that shipped: the tty belongs to whoever opened
    /// it, so searching iTerm for it found nothing and then raised iTerm.
    func testExactTabWinsWhenTheSessionIsInThatTerminal() {
        let iTermPath = "/Applications/iTerm.app"
        let destination = TerminalFocuser.destination(
            tty: "/dev/ttys008",
            hostApp: iTermPath,
            hostID: iTerm,
            fallbackPath: "/repo",
            probe: probe(running: [iTerm, vsCode], ids: [iTermPath: iTerm])
        )
        XCTAssertEqual(destination, .terminalTab(tty: "/dev/ttys008", bundleID: iTerm))
    }

    /// The case this was all for: a real tty that belongs to no tab.
    func testHostAppIsUsedWhenNoScriptableTerminalIsRunning() {
        let destination = TerminalFocuser.destination(
            tty: "/dev/ttys008",
            hostApp: vsCodePath,
            hostID: vsCode,
            fallbackPath: "/repo",
            probe: probe(running: [vsCode], ids: [vsCodePath: vsCode])
        )
        XCTAssertEqual(destination, .application(bundleID: vsCode))
    }

    /// The inherited bundle id stands in when the process walk found nothing —
    /// a session under tmux inside an editor, say.
    func testBundleIdFallsBackToTheInheritedOne() {
        let destination = TerminalFocuser.destination(
            tty: nil,
            hostApp: nil,
            hostID: vsCode,
            fallbackPath: "/repo",
            probe: probe(running: [vsCode])
        )
        XCTAssertEqual(destination, .application(bundleID: vsCode))
    }

    /// The path is the better witness: it says what spawned this session, where
    /// an inherited id can name whatever launched the editor.
    func testThePathIsPreferredOverTheInheritedID() {
        let destination = TerminalFocuser.destination(
            tty: nil,
            hostApp: vsCodePath,
            hostID: terminal,
            fallbackPath: nil,
            probe: probe(running: [vsCode, terminal], ids: [vsCodePath: vsCode])
        )
        XCTAssertEqual(destination, .application(bundleID: vsCode))
    }

    /// An app that has since quit is not somewhere to arrive.
    func testAClosedHostAppFallsThroughToTheFolder() {
        let destination = TerminalFocuser.destination(
            tty: nil,
            hostApp: vsCodePath,
            hostID: vsCode,
            fallbackPath: "/repo",
            probe: probe(running: [], ids: [vsCodePath: vsCode])
        )
        XCTAssertEqual(destination, .finder(path: "/repo"))
    }

    /// Sessions written by an older cc-notify carry no host at all, and must
    /// behave exactly as they did before.
    func testOlderSessionsWithoutAHostStillRevealTheFolder() {
        let destination = TerminalFocuser.destination(
            tty: nil,
            hostApp: nil,
            hostID: nil,
            fallbackPath: "/repo",
            probe: probe(running: [iTerm])
        )
        XCTAssertEqual(destination, .finder(path: "/repo"))
    }

    func testNothingKnownGoesNowhere() {
        let destination = TerminalFocuser.destination(
            tty: nil,
            hostApp: nil,
            hostID: nil,
            fallbackPath: nil,
            probe: probe(running: [iTerm])
        )
        XCTAssertEqual(destination, .nowhere)
    }

    /// A tty whose terminal is not running is not a tab any more.
    func testTtyWithoutItsTerminalDoesNotClaimATab() {
        let destination = TerminalFocuser.destination(
            tty: "/dev/ttys008",
            hostApp: nil,
            hostID: nil,
            fallbackPath: "/repo",
            probe: probe(running: [])
        )
        XCTAssertEqual(destination, .finder(path: "/repo"))
    }

    /// Empty strings arrive from a manifest or a half-written line as readily
    /// as nil does.
    func testEmptyStringsCountAsMissing() {
        let destination = TerminalFocuser.destination(
            tty: "",
            hostApp: "",
            hostID: "",
            fallbackPath: "/repo",
            probe: probe(running: [iTerm])
        )
        XCTAssertEqual(destination, .finder(path: "/repo"))
    }

    /// The tty is pasted into an AppleScript string. A value carrying a quote,
    /// a space or a `..` was written to break out of it — it is not a tty, so
    /// it does not claim a tab, and the click falls through to the host.
    func testAttackerControlledTtyDoesNotReachAScript() {
        let hostile = "/dev/ttys008\" \n do shell script \"touch /tmp/pwned\" \n if \"x\" is \""
        let destination = TerminalFocuser.destination(
            tty: hostile,
            hostApp: nil,
            hostID: iTerm,
            fallbackPath: "/repo",
            probe: probe(running: [iTerm])
        )
        XCTAssertEqual(destination, .application(bundleID: iTerm), "no tab for a non-tty")

        XCTAssertTrue(TerminalFocuser.isDeviceTTY("/dev/ttys008"))
        XCTAssertTrue(TerminalFocuser.isDeviceTTY("/dev/ttyp3"))
        for bad in [hostile, "../../x", "/dev/ttys008; rm -rf ~", "/dev/pts/0", "ttys008", ""] {
            XCTAssertFalse(TerminalFocuser.isDeviceTTY(bad), "\(bad) is not a device path")
        }
    }
}

/// The bug the first version shipped: a session in VS Code has a real tty, and
/// with Terminal.app running the decision claimed a Terminal tab, found no such
/// tab, and then raised Terminal — the wrong app, confidently.
final class HostAwareTabTests: XCTestCase {
    private let terminal = "com.apple.Terminal"
    private let vsCodePath = "/Applications/Visual Studio Code.app"
    private let vsCode = "com.microsoft.VSCode"

    private func probe(running: Set<String>,
                       ids: [String: String] = [:]) -> TerminalFocuser.Probe {
        TerminalFocuser.Probe(
            isBundleRunning: { running.contains($0) },
            bundleID: { ids[$0] }
        )
    }

    /// A tty belongs to whichever app opened it. Terminal cannot hold a tab for
    /// a session hosted by VS Code, however many tabs Terminal has open.
    func testAKnownNonTerminalHostIsNotSearchedForInTerminal() {
        let destination = TerminalFocuser.destination(
            tty: "/dev/ttys010",
            hostApp: vsCodePath,
            hostID: vsCode,
            fallbackPath: "/repo",
            probe: probe(running: [terminal, vsCode], ids: [vsCodePath: vsCode])
        )
        XCTAssertEqual(destination, .application(bundleID: vsCode))
    }

    /// The host being a terminal we *can* script is exactly when the tab search
    /// is right.
    func testAKnownTerminalHostStillGetsItsExactTab() {
        let destination = TerminalFocuser.destination(
            tty: "/dev/ttys008",
            hostApp: "/System/Applications/Utilities/Terminal.app",
            hostID: terminal,
            fallbackPath: "/repo",
            probe: probe(
                running: [terminal],
                ids: ["/System/Applications/Utilities/Terminal.app": terminal]
            )
        )
        XCTAssertEqual(destination, .terminalTab(tty: "/dev/ttys008", bundleID: terminal))
    }

    /// Cursor's own agent has no terminal at all — Composer is not a shell — so
    /// the row carries a host and no tty. Values below are the real ones a
    /// Composer turn wrote on 2026-08-14, including the outermost bundle id
    /// rather than the `com.github.Electron.helper` every Electron app shares.
    func testCursorsOwnAgentJumpsToCursor() {
        let cursor = "com.todesktop.230313mzl4w4u92"
        let destination = TerminalFocuser.destination(
            tty: nil,
            hostApp: "/Applications/Cursor.app",
            hostID: cursor,
            fallbackPath: "/Users/waltermak/github/empty",
            probe: probe(running: [cursor, terminal],
                         ids: ["/Applications/Cursor.app": cursor])
        )
        XCTAssertEqual(destination, .application(bundleID: cursor))
    }

    /// With Cursor closed there is nothing to raise, and revealing the folder
    /// beats launching a fresh empty window.
    func testAClosedCursorFallsBackToFinder() {
        let destination = TerminalFocuser.destination(
            tty: nil,
            hostApp: "/Applications/Cursor.app",
            hostID: "com.todesktop.230313mzl4w4u92",
            fallbackPath: "/Users/waltermak/github/empty",
            probe: probe(running: [terminal])
        )
        XCTAssertEqual(destination, .finder(path: "/Users/waltermak/github/empty"))
    }

    /// Sessions written before host_app existed name no host, so every running
    /// terminal is still worth searching — that is all we ever had.
    func testAnUnknownHostStillSearchesRunningTerminals() {
        let destination = TerminalFocuser.destination(
            tty: "/dev/ttys008",
            hostApp: nil,
            hostID: nil,
            fallbackPath: "/repo",
            probe: probe(running: [terminal])
        )
        XCTAssertEqual(destination, .terminalTab(tty: "/dev/ttys008", bundleID: terminal))
    }

    /// With the tty ignored — which is what happens after a tab search fails —
    /// the host app is where the click should land.
    func testDroppingTheTtyLandsOnTheHost() {
        let destination = TerminalFocuser.destination(
            tty: nil,
            hostApp: vsCodePath,
            hostID: vsCode,
            fallbackPath: "/repo",
            probe: probe(running: [terminal, vsCode], ids: [vsCodePath: vsCode])
        )
        XCTAssertEqual(destination, .application(bundleID: vsCode))
    }
}
