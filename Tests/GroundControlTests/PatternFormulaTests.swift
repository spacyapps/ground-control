// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The Tier-2 formula language (docs/MATRIX-CUSTOMISATION.md). Every assertion
/// here is something a theme author could write and expect to hold.
final class PatternFormulaTests: XCTestCase {
    private let ctx = PatternFormula.Context(
        pos: 0.25, phase: 1.0, energy: 0.5, bar: 2, count: 8
    )

    private func eval(_ source: String, _ context: PatternFormula.Context? = nil) throws -> Double {
        let formula = try XCTUnwrap(PatternFormula.parse(source), "did not parse: \(source)")
        return formula.value(context ?? ctx)
    }

    // MARK: - Arithmetic and precedence

    func testPrecedence() throws {
        XCTAssertEqual(try eval("1 + 2 * 3"), 7, accuracy: 1e-9)
        XCTAssertEqual(try eval("(1 + 2) * 3"), 9, accuracy: 1e-9)
        XCTAssertEqual(try eval("10 - 2 - 3"), 5, accuracy: 1e-9, "subtraction is left-assoc")
        XCTAssertEqual(try eval("12 / 2 / 3"), 2, accuracy: 1e-9, "division is left-assoc")
    }

    func testPowerIsRightAssociativeAndUnderUnary() throws {
        XCTAssertEqual(try eval("2 ^ 3 ^ 2"), 512, accuracy: 1e-9)
        XCTAssertEqual(try eval("-2 ^ 2"), -4, accuracy: 1e-9, "the school reading")
        XCTAssertEqual(try eval("2 ^ -2"), 0.25, accuracy: 1e-9, "a negative exponent still parses")
    }

    func testDivideByZeroIsZeroNotNaN() throws {
        let value = try eval("1 / 0")
        XCTAssertEqual(value, 0)
        XCTAssertFalse(value.isNaN)
    }

    // MARK: - Variables

    func testVariablesReadTheContext() throws {
        XCTAssertEqual(try eval("pos"), 0.25, accuracy: 1e-9)
        XCTAssertEqual(try eval("phase"), 1.0, accuracy: 1e-9)
        XCTAssertEqual(try eval("energy"), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try eval("bar"), 2, accuracy: 1e-9)
        XCTAssertEqual(try eval("count"), 8, accuracy: 1e-9)
    }

    // MARK: - Functions

    func testMathFunctions() throws {
        XCTAssertEqual(try eval("sin(0)"), 0, accuracy: 1e-9)
        XCTAssertEqual(try eval("abs(0 - 3)"), 3, accuracy: 1e-9)
        XCTAssertEqual(try eval("floor(2.9)"), 2, accuracy: 1e-9)
        XCTAssertEqual(try eval("min(4, 9)"), 4, accuracy: 1e-9)
        XCTAssertEqual(try eval("max(4, 9)"), 9, accuracy: 1e-9)
        XCTAssertEqual(try eval("sqrt(0 - 1)"), 0, "a negative root is 0, not NaN")
    }

    func testStepPulseWrap() throws {
        XCTAssertEqual(try eval("step(0.5, 0.4)"), 0)
        XCTAssertEqual(try eval("step(0.5, 0.6)"), 1)
        XCTAssertEqual(try eval("pulse(0.5, 0.2, 0.5)"), 1, accuracy: 1e-9, "1 at the centre")
        XCTAssertEqual(try eval("pulse(0.5, 0.2, 0.8)"), 0, accuracy: 1e-9, "0 beyond the width")
        XCTAssertEqual(try eval("wrap(3.25)"), 0.25, accuracy: 1e-9)
    }

    func testBuiltInPatternsAreCallable() throws {
        // pyramid(0.5) is the tallest point of the triangle, at any phase.
        let value = try eval("pyramid(0.5)")
        XCTAssertGreaterThan(value, 0.9)
    }

    // MARK: - Rejections

    func testUnknownNameFailsToParse() {
        XCTAssertNil(PatternFormula.parse("pos * gremlin"))
        XCTAssertNil(PatternFormula.parse("wiggle(pos)"))
    }

    func testWrongArgumentCountFailsToParse() {
        XCTAssertNil(PatternFormula.parse("min(1)"))
        XCTAssertNil(PatternFormula.parse("wave(pos, phase)"))
        XCTAssertNil(PatternFormula.parse("sin(1, 2)"))
    }

    func testSyntaxErrorsFailToParse() {
        XCTAssertNil(PatternFormula.parse(""))
        XCTAssertNil(PatternFormula.parse("1 +"))
        XCTAssertNil(PatternFormula.parse("(1 + 2"))
        XCTAssertNil(PatternFormula.parse("1 2 3"))
        XCTAssertNil(PatternFormula.parse("* 4"))
    }

    // MARK: - The sampler

    func testSamplerClampsToUnitRange() throws {
        let hot = try XCTUnwrap(PatternFormula.parse("5")).sampler(phase: 0, energy: 1, count: 10)
        let cold = try XCTUnwrap(PatternFormula.parse("0 - 5")).sampler(phase: 0, energy: 1, count: 10)
        XCTAssertEqual(hot.height(pos: 0, bar: 0), 1)
        XCTAssertEqual(cold.height(pos: 0, bar: 0), 0)
    }

    // MARK: - decay(), the done-only function

    func testDecayIsRejectedOutsideADoneFormula() {
        XCTAssertNil(PatternFormula.parse("pyramid(pos) * decay(0.6)"))
    }

    func testDecayRampsOneToZeroOverItsSpan() throws {
        let formula = try XCTUnwrap(
            PatternFormula.parse("decay(0.6)", key: "matrix.shape.done", allowsDecay: true)
        )
        func atElapsed(_ seconds: TimeInterval) -> CGFloat {
            formula.sampler(phase: 0, energy: 0, count: 1, decayElapsed: seconds).height(pos: 0, bar: 0)
        }
        XCTAssertEqual(atElapsed(0), 1, accuracy: 1e-9)
        XCTAssertEqual(atElapsed(0.3), 0.5, accuracy: 1e-9)
        XCTAssertEqual(atElapsed(0.6), 0, accuracy: 1e-9)
        XCTAssertEqual(atElapsed(2.0), 0, "never goes negative")
    }

    // MARK: - The documented swell example

    /// A guard, not a benchmark: `height` runs ~60 times a frame, 24 frames a
    /// second, so a formula eval that turned pathological (an allocation per
    /// node, a quadratic parse cached wrong) would show here long before a
    /// person felt it. The bound is loose enough never to flake.
    func testEvaluatingASwellForManyFramesStaysCheap() throws {
        let swell = try XCTUnwrap(PatternFormula.parse("""
        exp(-((max(0, wrap(phase * 0.15) - pos) * 0.7 \
        + max(0, pos - wrap(phase * 0.15)) * 4.0) ^ 2) / 0.05)
        """))
        let began = Date()
        for frame in 0..<200 {
            let sampler = swell.sampler(phase: CGFloat(frame) * 0.1, energy: 1, count: 64)
            for bar in 0..<64 { _ = sampler.height(pos: Double(bar) / 63, bar: bar) }
        }
        // 12,800 evals of a ~15-node tree. Real cost is well under a millisecond
        // in total; 100ms catches a 100x regression without ever being tight.
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.1)
    }

    func testSwellExampleParsesAndStaysInRange() throws {
        let swell = """
        exp(-((max(0, wrap(phase * 0.15) - pos) * 0.7 \
        + max(0, pos - wrap(phase * 0.15)) * 4.0) ^ 2) / 0.05)
        """
        let formula = try XCTUnwrap(PatternFormula.parse(swell))
        for step in 0..<40 {
            let phase = CGFloat(step) * 0.3
            let sampler = formula.sampler(phase: phase, energy: 1, count: 24)
            for bar in 0..<24 {
                let height = sampler.height(pos: Double(bar) / 23, bar: bar)
                XCTAssertTrue((0...1).contains(height), "swell out of range: \(height)")
            }
        }
    }
}
