// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import XCTest
@testable import GroundControl

/// Every child row drew its name in `messageDim` whatever it was doing, which
/// left a dot a couple of millimetres wide carrying the entire difference
/// between a bot mid-task and a bot asleep. Unicorn Overlord sets `working`
/// #a78bfa against `idle` #c4b5fd — neighbouring violets — so on that theme the
/// dot said nothing at all.
final class ChildNameEmphasisTests: XCTestCase {
    private let colors = DefaultTheme.colors

    func testAWorkingChildGetsTheBrightName() {
        XCTAssertEqual(colors.childName(for: .working), colors.message)
    }

    func testAChildWaitingOnYouGetsTheBrightName() {
        XCTAssertEqual(colors.childName(for: .needsInput), colors.message)
    }

    func testAQuietChildStaysDim() {
        XCTAssertEqual(colors.childName(for: .idle), colors.messageDim)
    }

    /// The point of the change: the two states a person most needs to tell
    /// apart must not be painted the same.
    func testBusyAndQuietAreNotTheSameColour() {
        XCTAssertNotEqual(colors.childName(for: .working), colors.childName(for: .idle))
    }
}
