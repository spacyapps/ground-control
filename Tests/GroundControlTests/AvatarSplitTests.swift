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

    /// The seam turns like a clock hand, so the composite at two times is two
    /// different pictures — that motion is the whole point of the unknown mood.
    func testTheSeamMovesWithTheClock() {
        let theme = DefaultTheme.theme
        let flat = AvatarView.splitFace(left: .idle, right: .done, theme: theme, angle: 0)
        let quarter = AvatarView.splitFace(left: .idle, right: .done, theme: theme, angle: .pi / 2)
        XCTAssertNotEqual(flat.tiffRepresentation, quarter.tiffRepresentation)
    }

    /// A seam is what stops it reading as one odd portrait. Sampled across the
    /// divider — which at angle 0 runs left-to-right — the centre differs from
    /// the face above and the face below.
    func testTheSplitFaceHasASeamAcrossTheDivider() throws {
        let theme = try XCTUnwrap(ThemeLoader.loadTheme(named: "spacyAppsLunarAvatar"))
        let image = AvatarView.splitFace(left: .idle, right: .done, theme: theme, angle: 0)
        var rect = NSRect(origin: .zero, size: image.size)
        let rep = NSBitmapImageRep(
            cgImage: try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        )

        let midX = rep.pixelsWide / 2
        let midY = rep.pixelsHigh / 2
        let centre = try XCTUnwrap(rep.colorAt(x: midX, y: midY))
        let above = try XCTUnwrap(rep.colorAt(x: midX, y: midY - rep.pixelsHigh / 3))
        let below = try XCTUnwrap(rep.colorAt(x: midX, y: midY + rep.pixelsHigh / 3))

        XCTAssertFalse(
            centre.isClose(to: above) && centre.isClose(to: below),
            "the seam colour sits between the two faces"
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
