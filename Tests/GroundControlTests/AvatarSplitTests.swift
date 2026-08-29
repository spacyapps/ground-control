// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// The Grok Bot parent's face: half idle, half done, because the cache cannot
/// say which (docs/GROK-BOT-GROUPING.md).
@MainActor
final class AvatarSplitTests: XCTestCase {
    private func imageView(of avatar: AvatarView) -> NSImageView? {
        avatar.subviews.compactMap { $0 as? NSImageView }.first
    }

    func testTheSplitFaceIsItsOwnComposite() {
        let theme = DefaultTheme.theme
        let split = AvatarView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
        split.configureSplit(left: .idle, right: .done, theme: theme)
        let idle = AvatarView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
        idle.configure(asset: nil, state: .idle, theme: theme)

        let splitImage = imageView(of: split)?.image
        XCTAssertNotNil(splitImage)
        XCTAssertNotEqual(
            splitImage?.tiffRepresentation,
            imageView(of: idle)?.image?.tiffRepresentation,
            "the split face is not just the idle face"
        )
    }

    func testTheSplitFaceIsNotRecomposedForTheSamePair() {
        let view = AvatarView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
        view.configureSplit(left: .idle, right: .done, theme: DefaultTheme.theme)
        let first = imageView(of: view)?.image

        view.configureSplit(left: .idle, right: .done, theme: DefaultTheme.theme)
        XCTAssertTrue(first === imageView(of: view)?.image, "the same pair reuses the composed image")
    }

    /// The seam is what stops it reading as one odd portrait. Rendered rather
    /// than assumed: a full-bleed split with no divider looks like a bug.
    func testTheSplitFaceHasASeamDownTheMiddle() throws {
        let theme = try XCTUnwrap(ThemeLoader.loadTheme(named: "spacyAppsLunarAvatar"))
        let view = AvatarView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        view.configureSplit(left: .idle, right: .done, theme: theme)

        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        // The centre column should not match either its left or right neighbour
        // — the seam colour sits between the two faces.
        let midX = rep.pixelsWide / 2
        let y = rep.pixelsHigh / 2
        let centre = try XCTUnwrap(rep.colorAt(x: midX, y: y))
        let left = try XCTUnwrap(rep.colorAt(x: midX - rep.pixelsWide / 6, y: y))
        let right = try XCTUnwrap(rep.colorAt(x: midX + rep.pixelsWide / 6, y: y))

        XCTAssertFalse(
            centre.isClose(to: left) && centre.isClose(to: right),
            "the centre seam differs from the faces on either side"
        )
    }
}

private extension NSColor {
    func isClose(to other: NSColor, tolerance: CGFloat = 0.12) -> Bool {
        guard
            let lhs = usingColorSpace(.deviceRGB),
            let rhs = other.usingColorSpace(.deviceRGB)
        else { return false }
        return abs(lhs.redComponent - rhs.redComponent) < tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) < tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) < tolerance
    }
}
