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
        theme.layout.contentInset = NSEdgeInsets(top: 180, left: 180, bottom: 180, right: 180)

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

/// `contentCornerRadius` lets a skin with a rounded opening stop framing a
/// square-cornered screen. It is measured in artwork pixels like `contentInset`,
/// so it scales with a locked skin too.
@MainActor
final class ContentCornerTests: XCTestCase {
    private func laidOut(radius: CGFloat, width: CGFloat = 600) -> PanelBackgroundView {
        var theme = DefaultTheme.theme
        theme.window = Theme.Window(
            shape: BackgroundImage(
                url: URL(fileURLWithPath: "/x.png"),
                mode: .stretch,
                capInsets: NSEdgeInsets()
            ),
            locksAspect: true,
            aspectRatio: 1,
            naturalWidth: 900
        )
        theme.layout.contentCornerRadius = radius

        let view = PanelBackgroundView()
        view.apply(theme: theme)
        view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testRadiusScalesWithTheArtworkLikeTheInset() {
        let view = laidOut(radius: 90)          // 10% into a 900px artwork
        XCTAssertEqual(view.titleBar.layer?.cornerRadius ?? 0, 60, accuracy: 0.5)
        XCTAssertEqual(view.list.layer?.cornerRadius ?? 0, 60, accuracy: 0.5)
    }

    /// The strip caps the block and the list closes it, so between them they
    /// round all four outer corners and neither touches the seam.
    func testEachViewRoundsOnlyItsOwnOuterPair() {
        let view = laidOut(radius: 60)
        let top = view.titleBar.layer?.maskedCorners ?? []
        let bottom = view.list.layer?.maskedCorners ?? []
        XCTAssertTrue(top.isDisjoint(with: bottom), "a corner is rounded twice")
        XCTAssertEqual(top.union(bottom).rawValue, CACornerMask([
            .layerMinXMinYCorner, .layerMaxXMinYCorner,
            .layerMinXMaxYCorner, .layerMaxXMaxYCorner
        ]).rawValue)
    }

    /// A theme that says nothing gets square corners and no clipping.
    func testNoRadiusMeansNoClipping() {
        let view = laidOut(radius: 0)
        XCTAssertEqual(view.titleBar.layer?.cornerRadius ?? 0, 0)
        XCTAssertEqual(view.list.layer?.masksToBounds, false)
    }
}
