// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import XCTest
@testable import GroundControl

/// The meter's look, rendered offscreen and read back as pixels — "tested but
/// never seen" has been wrong here more than once, so the fill is measured
/// rather than assumed.
final class ContextMeterRenderTests: XCTestCase {
    private let width = 200
    private let height = 4

    /// Draws one meter onto a transparent bitmap, white ink.
    private func render(_ percent: Int) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        ContextMeter(percent: percent).draw(
            in: NSRect(x: 0, y: 0, width: width, height: height), ink: .white)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func alpha(_ bitmap: NSBitmapImageRep, x: Int) -> CGFloat {
        bitmap.colorAt(x: x, y: height / 2)?.alphaComponent ?? 0
    }

    func testTheFillCoversThePercentAndTheTrackTheRest() throws {
        let bitmap = try render(50)
        let filled = alpha(bitmap, x: 50)
        let empty = alpha(bitmap, x: 150)
        XCTAssertGreaterThan(filled, empty + 0.2, "left half is filled, right half is bare track")
        XCTAssertGreaterThan(empty, 0.05, "the track shows where the meter ends")
    }

    func testNothingIsDrawnForNoReading() throws {
        let bitmap = try render(0)
        for x in stride(from: 0, to: width, by: 20) {
            XCTAssertEqual(alpha(bitmap, x: x), 0, "x=\(x)")
        }
    }

    func testNearlyFullTurnsRed() throws {
        let color = try XCTUnwrap(render(90).colorAt(x: 100, y: height / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, color.greenComponent + 0.3)
        XCTAssertGreaterThan(color.redComponent, color.blueComponent + 0.3)
    }

    func testALowReadingIsNotRed() throws {
        let color = try XCTUnwrap(render(30).colorAt(x: 20, y: height / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(color.redComponent, color.greenComponent + 0.1, "muted ink, not the warning red")
    }

    func testTheWarningThresholdIsWhereTheDocsSayIt() {
        XCTAssertFalse(ContextMeter(percent: ContextMeter.warnPercent - 1).isNearlyFull)
        XCTAssertTrue(ContextMeter(percent: ContextMeter.warnPercent).isNearlyFull)
    }
}
