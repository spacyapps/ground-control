// SPDX-License-Identifier: AGPL-3.0-or-later
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

    /// Grok Bot can say "a card is waiting" but not what it is doing otherwise,
    /// so its quiet dot is the split idle|done mark (docs/GROK-BOT-GROUPING.md).
    func testGrokBotIsMarkedUnknown() {
        XCTAssertEqual(StatusDotView.Mark.forSource("grokbot"), .unknown)
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

    /// The quiet `.unknown` dot must actually show two different colours — the
    /// left half idle, the right half done — at the size a parent row draws it.
    /// A plain dot draws one colour edge to edge, so left ≠ right is the test.
    func testTheUnknownDotDrawsTwoHalves() throws {
        func halves(_ mark: StatusDotView.Mark) throws -> (NSColor, NSColor) {
            let view = StatusDotView()
            view.frame = NSRect(x: 0, y: 0, width: 14, height: 14)
            view.mark = mark
            view.color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
            view.altColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
            view.isProminent = false
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            // colorAt takes device pixels, which are 2x points on a Retina rep.
            let midY = rep.pixelsHigh / 2
            return (
                try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 4, y: midY)),
                try XCTUnwrap(rep.colorAt(x: rep.pixelsWide * 3 / 4, y: midY))
            )
        }

        let (roundLeft, roundRight) = try halves(.round)
        XCTAssertEqual(
            roundLeft.redComponent,
            roundRight.redComponent,
            accuracy: 0.05,
            "a plain dot is one colour across"
        )

        let (left, right) = try halves(.unknown)
        XCTAssertGreaterThan(left.redComponent - right.redComponent, 0.4, "left half is idle, right is not")
        XCTAssertGreaterThan(right.blueComponent - left.blueComponent, 0.4, "right half is done, left is not")
    }

    /// Since 2026-09-19 a Grok Bot row can know it is working — it owes the
    /// user a reply, or it spoke seconds ago. A row that knows should look like
    /// every other row that knows, or the split face reads as "asleep" while
    /// the bot is mid-task.
    func testAWorkingGrokBotRowGetsAnOrdinaryDot() {
        XCTAssertEqual(StatusDotView.Mark.forSource("grokbot", state: .working), .round)
    }

    func testAWaitingGrokBotRowGetsAnOrdinaryDot() {
        XCTAssertEqual(StatusDotView.Mark.forSource("grokbot", state: .needsInput), .round)
    }

    /// Quiet is the one state the cache genuinely cannot read: finished,
    /// waiting on you, or tasked and not yet started. That is what the split
    /// was invented for, and all it should still cover.
    func testAQuietGrokBotRowKeepsTheSplitDot() {
        XCTAssertEqual(StatusDotView.Mark.forSource("grokbot", state: .idle), .unknown)
    }

    /// Cursor's square is about the source, not the state: it can never say it
    /// is blocked, whatever it is doing.
    func testCursorStaysSquareInEveryState() {
        for state in SessionState.allCases {
            XCTAssertEqual(StatusDotView.Mark.forSource("cursor", state: state), .square)
        }
    }
}
