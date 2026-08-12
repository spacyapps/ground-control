// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The preview drew its rows across the full width while the skin's frame ran
/// down both sides, so a station hull ended up with rows printed over its
/// pillars. `contentInset` is what keeps them apart in the real panel; the
/// preview has to honour it at its own scale.
@MainActor
final class ThemePreviewTests: XCTestCase {
    private let box = NSRect(x: 0, y: 0, width: 340, height: 162)

    private func preview(contentInset: CGFloat) -> ThemePreviewView {
        var theme = DefaultTheme.theme
        theme.layout.contentInset = contentInset
        let view = ThemePreviewView()
        view.apply(theme: theme)
        return view
    }

    /// The panel draws its frame 1:1 while the preview scales the whole image
    /// down, so the inset has to scale by the same factor to land on it.
    func testInsetFollowsTheScaleTheArtworkWasDrawnAt() {
        let view = preview(contentInset: 60)
        let half = view.contentRect(in: box, artScale: 0.5)
        XCTAssertEqual(half.minX, 30, accuracy: 0.5)
        XCTAssertEqual(half.width, box.width - 60, accuracy: 0.5)

        let quarter = view.contentRect(in: box, artScale: 0.25)
        XCTAssertEqual(quarter.minX, 15, accuracy: 0.5)
    }

    /// A deep inset on a small preview must not squeeze the rows out entirely.
    func testInsetIsCappedSoRowsSurvive() {
        let view = preview(contentInset: 400)
        let rect = view.contentRect(in: box, artScale: 1)
        XCTAssertGreaterThan(rect.width, box.width * 0.35)
        XCTAssertGreaterThan(rect.height, box.height * 0.65)
    }

    /// The artwork is anchored to the top and cropped, so there is no bottom
    /// frame on screen for the rows to stay clear of.
    func testNoInsetAtTheBottomWhereTheArtIsCropped() {
        let view = preview(contentInset: 40)
        let rect = view.contentRect(in: box, artScale: 1)
        XCTAssertEqual(rect.maxY, box.maxY, accuracy: 0.5)
        XCTAssertEqual(rect.minY, 40, accuracy: 0.5)
    }

    /// A theme with no frame gets the whole box, as before.
    func testThemeWithoutAFrameFillsTheBox() {
        let rect = preview(contentInset: 0).contentRect(in: box, artScale: 1)
        XCTAssertEqual(rect, box)
    }
}
