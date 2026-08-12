// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// `contentInset` says where the frame ends in the artwork, so it has to be
/// scaled wherever the artwork is.
///
/// A locked skin is scaled bodily to the panel: a frame painted 20% into a
/// 900px image is 20% of the panel at every width, so a fixed number of points
/// is right at exactly one size. Nine-slice draws its corners at natural size,
/// so there the number needs no scaling at all.
@MainActor
final class ArtworkScaleTests: XCTestCase {
    private func window(locked: Bool, naturalWidth: CGFloat, shaped: Bool = true) -> Theme.Window {
        Theme.Window(
            shape: shaped
                ? BackgroundImage(url: URL(fileURLWithPath: "/x.png"), mode: .stretch, capInsets: NSEdgeInsets())
                : nil,
            locksAspect: locked,
            aspectRatio: 1,
            naturalWidth: naturalWidth
        )
    }

    func testLockedSkinScalesWithThePanel() {
        let locked = window(locked: true, naturalWidth: 900)
        XCTAssertEqual(locked.artworkScale(atPanelWidth: 900), 1, accuracy: 0.001)
        XCTAssertEqual(locked.artworkScale(atPanelWidth: 450), 0.5, accuracy: 0.001)
        XCTAssertEqual(locked.artworkScale(atPanelWidth: 1800), 2, accuracy: 0.001)
    }

    /// Nine-slice corners are drawn at natural size, so points and artwork
    /// pixels already agree and nothing may be scaled.
    func testSlicedSkinIsNeverScaled() {
        XCTAssertEqual(window(locked: false, naturalWidth: 900).artworkScale(atPanelWidth: 320), 1)
    }

    func testUnshapedAndUnmeasurableArtAreLeftAlone() {
        XCTAssertEqual(Theme.Window.standard.artworkScale(atPanelWidth: 320), 1)
        XCTAssertEqual(window(locked: true, naturalWidth: 0).artworkScale(atPanelWidth: 320), 1)
        XCTAssertEqual(window(locked: true, naturalWidth: 900, shaped: false)
            .artworkScale(atPanelWidth: 320), 1)
    }

    /// The panel puts its rows where the frame ends, at whatever width it is.
    func testPanelRowsTrackTheFrameAsItResizes() {
        var theme = DefaultTheme.theme
        theme.window = window(locked: true, naturalWidth: 900)
        theme.layout.contentInset = 180      // 20% into a 900px artwork

        for width in [CGFloat(600), 800] {
            let view = PanelBackgroundView()
            view.apply(theme: theme)
            view.frame = NSRect(x: 0, y: 0, width: width, height: 900)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(
                view.titleBar.frame.minX / width,
                0.2,
                accuracy: 0.02,
                "rows drifted off the frame at \(width)pt"
            )
        }
    }
}
