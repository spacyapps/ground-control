// SPDX-License-Identifier: GPL-3.0-or-later
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

    func testExactTabWinsWhenItsTerminalIsRunning() {
        let destination = TerminalFocuser.destination(
            tty: "/dev/ttys008",
            hostApp: vsCodePath,
            hostID: vsCode,
            fallbackPath: "/repo",
            probe: probe(running: [iTerm, vsCode], ids: [vsCodePath: vsCode])
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
}
