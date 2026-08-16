// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// AppKit's tooltips are shown only for the active application, and this one is
/// an accessory whose panel is deliberately non-activating — so `toolTip` was
/// set on every control and silently did nothing. The panel draws its own.
@MainActor
final class HintViewTests: XCTestCase {
    private func container() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        return view
    }

    private func settled(_ hint: HintView) {
        // The show is scheduled rather than immediate, so that a pointer
        // crossing a list does not flicker hints all the way down it.
        let wait = expectation(description: "hint settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { wait.fulfill() }
        wait_for(wait)
    }

    private func wait_for(_ expectation: XCTestExpectation) {
        wait(for: [expectation], timeout: 2)
    }

    func testItAppearsWithText() {
        let host = container()
        let hint = HintView()
        host.addSubview(hint)
        hint.show("Jump to Terminal", near: NSRect(x: 40, y: 40, width: 20, height: 20), in: host)
        settled(hint)
        XCTAssertFalse(hint.isHidden)
        XCTAssertGreaterThan(hint.frame.width, 0)
    }

    func testNilHidesIt() {
        let host = container()
        let hint = HintView()
        host.addSubview(hint)
        hint.show("Menu", near: NSRect(x: 40, y: 40, width: 20, height: 20), in: host)
        settled(hint)
        hint.show(nil, near: .zero, in: host)
        settled(hint)
        XCTAssertTrue(hint.isHidden)
    }

    /// A hint that runs off the panel explains nothing, so it flips above the
    /// control and is pulled back inside the edges.
    func testItStaysInsideThePanel() {
        let host = container()
        let hint = HintView()
        host.addSubview(hint)

        hint.show("Jump to Visual Studio Code", near: NSRect(x: 300, y: 225, width: 16, height: 16), in: host)
        settled(hint)
        XCTAssertLessThanOrEqual(hint.frame.maxX, host.bounds.maxX)
        XCTAssertGreaterThanOrEqual(hint.frame.minX, 0)
        XCTAssertLessThanOrEqual(hint.frame.maxY, host.bounds.maxY)
    }

    /// It sits under the pointer, so swallowing the click of the control it
    /// describes would be a cruel joke.
    func testItNeverTakesAClick() {
        let hint = HintView()
        hint.frame = NSRect(x: 0, y: 0, width: 100, height: 24)
        XCTAssertNil(hint.hitTest(NSPoint(x: 50, y: 12)))
    }
}
