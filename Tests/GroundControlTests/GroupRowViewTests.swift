// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

final class GroupRowViewTests: XCTestCase {
    /// `intrinsicContentSize` under-measures a label by a few points (30 for
    /// "alpha" at 11pt semibold, where the cell needs 33.8), so a frame sized
    /// from it clips the name to "al…" with plenty of room beside it.
    func testNameLabelIsWideEnoughForItsWholeName() throws {
        let row = GroupRowView()
        row.frame = NSRect(x: 0, y: 0, width: 390, height: 30)
        let child = AgentRow(
            id: "a1",
            displayName: "alpha",
            message: "Sent pong to beta. Standing by.",
            state: .done,
            needsAction: false,
            source: "claude",
            lastActivity: Date()
        )
        row.configure(child: child, theme: DefaultTheme.theme)
        row.layoutSubtreeIfNeeded()

        let name = try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.first)
        let needed = try XCTUnwrap(name.cell?.cellSize.width)
        XCTAssertGreaterThanOrEqual(name.frame.width, needed)
    }
}
