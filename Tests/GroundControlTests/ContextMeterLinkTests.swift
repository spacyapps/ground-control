// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import XCTest
@testable import GroundControl

/// The Hooks menu's "how to enable" line for the context meter. The meter is a
/// Claude Code mod the user loads themselves, so the app's only part is a link
/// to the README section that explains it — and a link has three ways to rot:
/// the heading is renamed, the menu line goes missing, or the privacy page stops
/// naming where the app can send you.
final class ContextMeterLinkTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// GitHub's anchor for a heading: lowercased, punctuation dropped, spaces to hyphens.
    private func anchor(_ heading: String) -> String {
        let kept = heading.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }
        return kept.replacingOccurrences(of: " ", with: "-")
    }

    /// Renaming the README heading would send people to the top of the page
    /// without anything failing. This is what makes it fail.
    func testTheLinkPointsAtARealREADMEHeading() throws {
        let url = try XCTUnwrap(Brand.contextMeterGuide)
        XCTAssertEqual(url.host, "github.com")
        let fragment = try XCTUnwrap(url.fragment)
        let readme = try String(contentsOf: repoRoot.appendingPathComponent("README.md"), encoding: .utf8)
        let anchors = readme.split(separator: "\n")
            .filter { $0.hasPrefix("#") }
            .map { anchor($0.drop(while: { $0 == "#" || $0 == " " }).description) }
        XCTAssertTrue(anchors.contains(fragment), "no README heading has the anchor #\(fragment)")
    }

    func testTheHooksMenuCarriesTheLinkWithItsDestinationInTheTooltip() throws {
        let actions = StatusMenu.Actions(
            togglePanel: {},
            toggleAlwaysOnTop: {},
            toggleAllSpaces: {},
            selectTheme: { _ in },
            openThemesFolder: {},
            openSettings: {},
            toggleHook: { _, _ in },
            currentSessions: { [] },
            quit: {}
        )
        let menu = StatusMenu(actions: actions).build(panelVisible: true, activeTheme: DefaultTheme.theme)
        let hooks = try XCTUnwrap(menu.items.first { $0.title.hasPrefix("Hooks") })
        let rows = hooks.submenu?.items.compactMap { $0.view as? MenuLinkRow } ?? []
        let row = try XCTUnwrap(rows.first, "the Hooks menu has no context-meter row")
        let title = row.linkButton.attributedTitle.string
        XCTAssertTrue(title.contains("Context meter"))
        XCTAssertTrue(title.hasSuffix("↗"), "leaving the app is marked like Get More Themes")
        XCTAssertEqual(row.linkButton.toolTip, Brand.contextMeterGuide?.absoluteString)
        XCTAssertNotNil(row.linkButton.action, "it must be clickable, not a grey note")
    }

    /// The privacy page says the list of things the app can open is exhaustive.
    /// A link to GitHub makes that false unless the page names it.
    func testThePrivacyPageNamesGitHub() {
        XCTAssertTrue(LegalText.privacy.contains("GitHub"))
    }
}
