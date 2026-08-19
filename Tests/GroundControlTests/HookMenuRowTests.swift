// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// A menu sizes a custom item from its view's frame and never runs a layout
/// pass to work one out. Left unresolved the row appears — with the right
/// height, even — and every label lands outside the box, so the menu opens
/// looking empty. It shipped that way once.
@MainActor
final class HookMenuRowTests: XCTestCase {
    func testEveryRowCarriesAResolvedFrame() throws {
        try requiresWindowServer()
        let row = HookMenuRow(agent: SetupStatus.summary(sessions: []), width: 340) { _ in }
        XCTAssertEqual(row.frame.width, 340)
        XCTAssertGreaterThan(row.frame.height, 20, "it would collapse in a menu")
        for view in row.subviews {
            XCTAssertTrue(
                row.bounds.contains(view.frame),
                "a subview escapes the row and will not be drawn"
            )
        }
    }

    /// A row grows for anything it has to explain, so a longer line is never
    /// clipped.
    func testARowGrowsForALongerLine() throws {
        try requiresWindowServer()
        let plain = SetupStatus.summary(sessions: [])
        let wordy = SetupStatus.Agent(
            name: plain.name,
            detected: true,
            registered: false,
            lastEvent: Date(),
            caveat: nil,
            target: .all
        )
        let short = HookMenuRow(agent: plain, width: 340) { _ in }
        let tall = HookMenuRow(agent: wordy, width: 340) { _ in }
        XCTAssertGreaterThan(tall.frame.height, short.frame.height)
    }

    /// Flicking the switch reports which way it went, so the caller can install
    /// or uninstall rather than guess.
    func testTheSwitchReportsItsNewState() throws {
        try requiresWindowServer()
        let agent = SetupStatus.summary(sessions: [])
        var reported: [Bool] = []
        let row = HookMenuRow(agent: agent, width: 340) { reported.append($0) }
        let toggle = try XCTUnwrap(row.subviews.compactMap { $0 as? HookSwitch }.first)
        let before = toggle.isOn
        toggle.mouseDown(with: NSEvent())
        XCTAssertEqual(reported, [!before], "the switch reports its new state, not its old one")
        XCTAssertEqual(toggle.isOn, !before)
    }

    /// The state that looked like a bug: switched off, and still reporting.
    /// An agent reads its hook configuration when it starts, so a session that
    /// was already running keeps calling us until it restarts. A row that says
    /// only "off" while events arrive from it reads as broken.
    func testItSaysWhenSomethingIsOffButStillReporting() {
        let stillGoing = SetupStatus.Agent(
            name: "Cursor's own agent",
            detected: true,
            registered: false,
            lastEvent: Date().addingTimeInterval(-36),
            caveat: nil,
            target: .cursor
        )
        let summary = HookMenuRow.summary(of: stillGoing)
        XCTAssertTrue(summary.contains("still"), summary)
        XCTAssertTrue(summary.contains("restarts"), "and how to make it stop: \(summary)")

        let quiet = SetupStatus.Agent(
            name: "Cursor's own agent",
            detected: true,
            registered: false,
            lastEvent: nil,
            caveat: nil,
            target: .cursor
        )
        XCTAssertEqual(
            HookMenuRow.summary(of: quiet),
            "off",
            "with nothing arriving, off is the whole story"
        )
    }
}
