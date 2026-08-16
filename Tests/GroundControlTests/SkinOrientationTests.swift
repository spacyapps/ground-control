// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// A skin must be drawn the way up its author drew it.
///
/// Every surface that draws one is `isFlipped`, and AppKit's resizable-image
/// path ignores that: it lays the pieces out in image order, so the bottom cap
/// lands at the top and the whole skin comes out mirrored. `respectFlipped:`
/// does not reach that path.
///
/// It went unnoticed through two station frames because both were near enough
/// symmetric top-to-bottom to look the same either way up. The third had solar
/// arrays pointing up at the top corners and down at the bottom, and the panel
/// drew them upside down.
@MainActor
final class SkinOrientationTests: XCTestCase {
    /// Red top band, blue bottom band, and a white pip in the very top-left —
    /// so a swap of the caps *and* a mirror of their contents both show up.
    private func artwork() throws -> URL {
        let side = 60
        var px = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                px[index + 3] = 255
                if y < 20 {
                    px[index] = 255
                } else if y >= 40 {
                    px[index + 2] = 255
                } else {
                    px[index + 1] = 120
                }
                if y < 6 && x < 6 {
                    px[index] = 255; px[index + 1] = 255; px[index + 2] = 255
                }
            }
        }
        let context = CGContext(
            data: &px,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "skin-orientation.png")
        try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(context?.makeImage()))
            .representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    /// Drawn through the real overlay view, which is where the flip lives.
    private func drawn(_ mode: BackgroundImage.Mode, caps: CGFloat) throws -> NSBitmapImageRep {
        let view = SkinOverlayView()
        var theme = DefaultTheme.theme
        theme.window = Theme.Window(
            shape: BackgroundImage(
                url: try artwork(),
                mode: mode,
                capInsets: NSEdgeInsets(top: caps, left: caps, bottom: caps, right: caps)
            ),
            locksAspect: false,
            aspectRatio: 1,
            drawsOverContent: true
        )
        view.apply(theme: theme)
        // A whole number of tiles: at a fraction, the top of the view is the
        // middle of a tile and says nothing about orientation.
        view.frame = NSRect(x: 0, y: 0, width: 60, height: 120)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func assertUpright(_ mode: BackgroundImage.Mode,
                               caps: CGFloat,
                               line: UInt = #line) throws {
        let rep = try drawn(mode, caps: caps)
        let upended = "\(mode) caps \(caps): the bottom cap is at the top"
        let top = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: 4)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(top.redComponent, 0.5, upended, line: line)
        XCTAssertLessThan(top.blueComponent, 0.5, upended, line: line)

        let mirrored = "\(mode) caps \(caps): the top-left corner is not top-left"
        let pip = try XCTUnwrap(rep.colorAt(x: 3, y: 3)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(pip.greenComponent, 0.8, mirrored, line: line)
    }

    /// The case that was broken: nine-slice, which every shaped frame theme uses.
    func testNineSliceDrawsTheRightWayUp() throws {
        try assertUpright(.tile, caps: 20)
        try assertUpright(.stretch, caps: 20)
    }

    /// And the case that must not be "fixed" into being wrong: plain drawing
    /// already honours the flip, so correcting it would turn it upside down.
    func testUnslicedArtIsLeftAlone() throws {
        try assertUpright(.tile, caps: 0)
        try assertUpright(.stretch, caps: 0)
    }
}
