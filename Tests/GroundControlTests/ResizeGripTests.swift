// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The grip is the only way to resize a shaped panel, so where it lands is
/// load-bearing: a framed skin holds its artwork `contentInset` points clear of
/// the window edge, and a handle sitting out in that margin is a handle on
/// transparent pixels — invisible, and click-through on a shaped theme.
@MainActor
final class ResizeGripTests: XCTestCase {
    private func laidOut(contentInset: CGFloat, width: CGFloat = 420) -> PanelBackgroundView {
        var theme = DefaultTheme.theme
        theme.layout.contentInset = contentInset

        let view = PanelBackgroundView()
        view.apply(theme: theme)
        view.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testGripStaysInsideTheFramedArtwork() {
        for inset in [0.0, 14.0, 75.0] {
            let view = laidOut(contentInset: inset)
            let grip = view.resizeGrip.frame
            XCTAssertLessThanOrEqual(
                grip.maxX,
                view.bounds.width - inset,
                "grip escaped the \(inset)pt frame onto the window edge"
            )
            XCTAssertGreaterThanOrEqual(grip.minX, inset)
            XCTAssertTrue(view.bounds.contains(grip))
        }
    }

    /// A narrow panel with a deep inset must not push the grip off the left
    /// side or invert it.
    func testGripSurvivesAnInsetWiderThanThePanel() {
        let view = laidOut(contentInset: 75, width: 260)
        XCTAssertGreaterThanOrEqual(view.resizeGrip.frame.minX, 0)
        XCTAssertGreaterThan(view.resizeGrip.frame.width, 0)
    }

    /// Dragging the grip must not be stolen by drag-to-move-the-window.
    func testGripDoesNotMoveTheWindow() {
        XCTAssertFalse(ResizeGripView().mouseDownCanMoveWindow)
    }
}
