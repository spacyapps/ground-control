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
        for agent in SetupStatus.agents(sessions: []) {
            let row = HookMenuRow(agent: agent, width: 340) { _ in }
            XCTAssertEqual(row.frame.width, 340, "\(agent.name)")
            XCTAssertGreaterThan(row.frame.height, 20, "\(agent.name) would collapse in a menu")
            for view in row.subviews {
                XCTAssertTrue(
                    row.bounds.contains(view.frame),
                    "\(agent.name): a subview escapes the row and will not be drawn"
                )
            }
        }
    }

    /// The row grows for an agent that has a limitation to explain, so the
    /// caveat is never clipped.
    func testARowWithACaveatIsTaller() throws {
        try requiresWindowServer()
        let rows = SetupStatus.agents(sessions: []).map { agent in
            (agent, HookMenuRow(agent: agent, width: 340) { _ in })
        }
        let plain = rows.first { $0.0.caveat == nil }?.1
        let explained = rows.first { $0.0.caveat != nil }?.1
        guard let plain, let explained else { return XCTFail("expected one of each") }
        XCTAssertGreaterThan(explained.frame.height, plain.frame.height)
    }

    /// Flicking the switch reports which way it went, so the caller can install
    /// or uninstall rather than guess.
    func testTheSwitchReportsItsNewState() throws {
        try requiresWindowServer()
        let agent = try XCTUnwrap(SetupStatus.agents(sessions: []).first { $0.target != nil })
        var reported: [Bool] = []
        let row = HookMenuRow(agent: agent, width: 340) { reported.append($0) }
        let toggle = try XCTUnwrap(row.subviews.compactMap { $0 as? HookSwitch }.first)
        let before = toggle.isOn
        toggle.mouseDown(with: NSEvent())
        XCTAssertEqual(reported, [!before], "the switch reports its new state, not its old one")
        XCTAssertEqual(toggle.isOn, !before)
    }
}
