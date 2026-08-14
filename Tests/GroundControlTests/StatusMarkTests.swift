// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// A round mark reports fully; a square one cannot.
///
/// Cursor's agent fires no hook while it waits for approval, so its rows never
/// turn red however stuck they are. Showing that in the same dot every other
/// row uses would be a quiet lie, and the shape says it without spending a
/// colour a theme might need.
@MainActor
final class StatusMarkTests: XCTestCase {
    func testCursorIsMarkedAsLimited() {
        XCTAssertEqual(StatusDotView.Mark.forSource("cursor"), .square)
    }

    /// The CLIs whose alarm works must keep the plain dot, or the shape stops
    /// meaning anything.
    func testEveryOtherSourceKeepsTheDot() {
        for source in ["claude", "grok", "codex", "unknown", ""] {
            XCTAssertEqual(StatusDotView.Mark.forSource(source), .round, "source: \(source)")
        }
    }

    /// The two shapes have to be distinguishable at the size they are drawn.
    /// Rendered rather than reasoned about: a rounded rect with too large a
    /// radius is a circle, and nothing in the type system says otherwise.
    func testTheShapesActuallyDiffer() throws {
        func pixels(_ mark: StatusDotView.Mark) throws -> [UInt8] {
            let view = StatusDotView()
            view.frame = NSRect(x: 0, y: 0, width: 10, height: 10)
            view.color = .white
            view.isProminent = true
            view.mark = mark
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            return (0..<(rep.pixelsWide * rep.pixelsHigh)).map { index in
                let x = index % rep.pixelsWide, y = index / rep.pixelsWide
                return UInt8(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.5 ? 1 : 0)
            }
        }
        let round = try pixels(.round), square = try pixels(.square)
        XCTAssertNotEqual(round, square, "the square draws the same as the dot")
        // A square covers its corners; a circle does not. That is the whole
        // difference, so it is what to count.
        XCTAssertGreaterThan(square.reduce(0) { $0 + Int($1) },
                             round.reduce(0) { $0 + Int($1) },
                             "the square should cover more area than the circle")
    }
}
