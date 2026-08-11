// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import SkinTerminal

/// Patterns are pure functions, so their shape can be checked rather than
/// eyeballed — a pattern that silently clips or flatlines looks like a bug in
/// the meter.
final class VisualizerPatternTests: XCTestCase {
    private let samples = stride(from: CGFloat(0), through: 1, by: 0.02)

    func testEveryPatternStaysInRange() {
        for pattern in VisualizerPattern.allCases {
            for phase in stride(from: CGFloat(0), through: 20, by: 0.37) {
                for position in samples {
                    let value = pattern.shape(position: position, phase: phase)
                    XCTAssertGreaterThanOrEqual(value, 0, "\(pattern) went negative")
                    XCTAssertLessThanOrEqual(value, 1, "\(pattern) exceeded 1")
                }
            }
        }
    }

    /// A pattern that never varies across the row is indistinguishable from a
    /// solid block — the bug that flattened the old spectrum.
    func testEveryPatternVariesAcrossTheRow() {
        for pattern in VisualizerPattern.allCases {
            let spread = stride(from: CGFloat(0), through: 6, by: 0.5).map { phase in
                let values = samples.map { pattern.shape(position: $0, phase: phase) }
                return (values.max() ?? 0) - (values.min() ?? 0)
            }.max() ?? 0
            XCTAssertGreaterThan(spread, 0.25, "\(pattern) is nearly flat across the row")
        }
    }

    /// …and one that never changes over time reads as a frozen picture.
    func testEveryPatternMovesOverTime() {
        for pattern in VisualizerPattern.allCases {
            let motion = samples.map { position in
                let values = stride(from: CGFloat(0), through: 8, by: 0.25)
                    .map { pattern.shape(position: position, phase: $0) }
                return (values.max() ?? 0) - (values.min() ?? 0)
            }.max() ?? 0
            XCTAssertGreaterThan(motion, 0.2, "\(pattern) does not animate")
        }
    }

    func testChaseWrapsWithoutADiscontinuity() {
        // The band must not vanish as it crosses the end of the row.
        let peak = stride(from: CGFloat(0), through: 12, by: 0.1).map { phase in
            samples.map { VisualizerPattern.chase.shape(position: $0, phase: phase) }.max() ?? 0
        }.min() ?? 0
        XCTAssertGreaterThan(peak, 0.4, "the chase band disappears at the wrap point")
    }

    func testNextNeverRepeatsTheCurrentPattern() {
        for pattern in VisualizerPattern.allCases {
            XCTAssertNotEqual(VisualizerPattern.next(avoiding: pattern), pattern)
        }
    }
}
