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

    // MARK: - Where themes come from

    /// The one route out of the app to anything for sale, and a typo in it
    /// fails silently: the button still opens, the browser still loads, and
    /// what a buyer lands on is a 404 nobody hears about.
    func testTheThemeStoreURLIsTheOneWeMeant() throws {
        let store = try XCTUnwrap(Brand.themeStore)
        XCTAssertEqual(store.absoluteString, "https://www.spacyapps.com/apps/ground-control/themes")
    }

    /// Same host as the site, so moving the domain breaks both together and
    /// gets noticed, rather than leaving the store pointing at the old one.
    func testTheStoreLivesOnTheSameHostAsTheWebsite() throws {
        let store = try XCTUnwrap(Brand.themeStore)
        let site = try XCTUnwrap(Brand.website)
        XCTAssertEqual(store.host, site.host)
        XCTAssertEqual(store.scheme, "https", "it is a link handed to a buyer")
    }
}
