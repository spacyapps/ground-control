// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

final class BrandVersionTests: XCTestCase {
    func testShortAndBuildReadAsVersionParenBuild() {
        XCTAssertEqual(Brand.versionLine(short: "0.7.3", build: "8"), "0.7.3 (8)")
    }

    /// A `swift run` executable has a short version but no build number.
    func testShortWithoutBuildDropsTheParens() {
        XCTAssertEqual(Brand.versionLine(short: "0.7.3", build: nil), "0.7.3")
    }

    /// Neither key present — the plain executable, running from the debugger.
    /// Better to say so than to show an empty line under the wordmark.
    func testNeitherKeyFallsBackToADevMarker() {
        XCTAssertEqual(Brand.versionLine(short: nil, build: nil), "dev build")
        XCTAssertEqual(Brand.versionLine(short: nil, build: "8"), "dev build")
    }
}
