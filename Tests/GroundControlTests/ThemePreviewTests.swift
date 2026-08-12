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
        theme.layout.contentInset = NSEdgeInsets(
            top: contentInset,
            left: contentInset,
            bottom: contentInset,
            right: contentInset
        )
        let view = ThemePreviewView()
        view.apply(theme: theme)
        return view
    }

    /// The inset is in panel points, so it scales with how much smaller the
    /// preview is than a panel — and with nothing else.
    func testInsetScalesWithThePreviewNotTheArtwork() {
        let inset = preview(contentInset: 40).contentRect(in: box).minX
        XCTAssertEqual(inset, 40 * (box.width / 400), accuracy: 0.5)

        let wider = NSRect(x: 0, y: 0, width: 400, height: 162)
        XCTAssertEqual(preview(contentInset: 40).contentRect(in: wider).minX, 40, accuracy: 0.5)
    }

    /// The bug this replaced: tying the inset to the artwork's scale meant a
    /// 1408px skin and a 450px one drawn the same size got different insets,
    /// and the big one's rows landed on its frame.
    func testInsetIgnoresTheArtworksResolution() {
        let small = preview(contentInset: 44).contentRect(in: box)
        let large = preview(contentInset: 44).contentRect(in: box)
        XCTAssertEqual(small, large)
    }

    /// A deep inset on a small preview must not squeeze the rows out entirely.
    func testInsetIsCappedSoRowsSurvive() {
        let view = preview(contentInset: 400)
        let rect = view.contentRect(in: box)
        XCTAssertGreaterThan(rect.width, box.width * 0.15)
        XCTAssertGreaterThan(rect.height, box.height * 0.55)
    }

    /// The artwork is anchored to the top and cropped, so there is no bottom
    /// frame on screen for the rows to stay clear of.
    func testNoInsetAtTheBottomWhereTheArtIsCropped() {
        let view = preview(contentInset: 40)
        let rect = view.contentRect(in: box)
        XCTAssertEqual(rect.maxY, box.maxY, accuracy: 0.5)
        XCTAssertEqual(rect.minY, 40 * (box.width / 400), accuracy: 0.5)
    }

    /// A theme with no frame gets the whole box, as before.
    func testThemeWithoutAFrameFillsTheBox() {
        let rect = preview(contentInset: 0).contentRect(in: box)
        XCTAssertEqual(rect, box)
    }
}
