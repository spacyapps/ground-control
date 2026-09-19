// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import XCTest
@testable import GroundControl

/// The Settings window cannot be resized, so its buttons either fit the column
/// they sit in or they are silently truncated. That is how "Get More Themes ↗"
/// — the only route from the app to a paid theme — came to render as a tinted
/// stub showing half an arrow: four buttons wanted ~474pt of a 360pt column,
/// and AppKit ate the first one.
///
/// These measure the labels against the column rather than trusting the layout
/// to complain, because it never does.
final class SettingsButtonRowTests: XCTestCase {
    private let spacing: CGFloat = 8

    private func button(_ title: String, weight: NSFont.Weight = .regular) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        if weight != .regular {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.systemFont(ofSize: 13, weight: weight)]
            )
        }
        return button
    }

    /// The three local utilities share the second row and must all fit it.
    func testTheUtilityButtonsFitTheSettingsColumn() {
        let titles = ["Create a Theme…", "Open Folder…", "Refresh"]
        let widths = titles.map { button($0).fittingSize.width }
        let total = widths.reduce(0, +) + spacing * CGFloat(titles.count - 1)

        XCTAssertLessThanOrEqual(
            total,
            SettingsView.contentWidth,
            "\(titles.joined(separator: " / ")) need \(total)pt of a "
                + "\(SettingsView.contentWidth)pt column — one of them will truncate"
        )
    }

    /// The store button is semibold and carries an arrow, so it is the widest
    /// of the four. On its own row it has the whole column.
    func testTheStoreButtonFitsItsOwnRow() {
        let store = button("Get More Themes ↗", weight: .semibold)

        XCTAssertLessThanOrEqual(
            store.fittingSize.width,
            SettingsView.contentWidth,
            "the one control that leads to a paid theme does not fit the column"
        )
    }

    /// The arrangement this replaced, kept as the reason it was replaced: all
    /// four on one line overflow, so a future tidy-up that puts them back finds
    /// out here rather than in a screenshot.
    func testAllFourOnOneRowWouldNotFit() {
        let store = button("Get More Themes ↗", weight: .semibold)
        let rest = ["Create a Theme…", "Open Folder…", "Refresh"].map { button($0) }
        // 18pt after the store button, 8pt between the other three.
        let total = ([store] + rest).map(\.fittingSize.width).reduce(0, +) + 18 + spacing * 2

        XCTAssertGreaterThan(
            total,
            SettingsView.contentWidth,
            "all four now fit on one line — the two-row split in buttonRow() can go back"
        )
    }
}
