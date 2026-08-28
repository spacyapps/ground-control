// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The Tier-1 analyser knobs: named levels in, tuned numbers out
/// (docs/MATRIX-CUSTOMISATION.md).
final class MatrixFeelTests: XCTestCase {
    private func feel(_ json: String) throws -> MatrixFeel.Resolved {
        let manifest = try JSONDecoder().decode(
            ThemeManifest.self, from: Data(#"{"matrix":\#(json)}"#.utf8)
        )
        return MatrixFeel.resolve(manifest.matrix)
    }

    func testAbsentBlockIsExactlyTheShippedAnalyser() {
        XCTAssertEqual(MatrixFeel.resolve(nil), .standard)
        XCTAssertEqual(MatrixFeel.resolve(ThemeManifest.Matrix()), .standard)
    }

    func testFallMovesReleaseAndPeakTogether() throws {
        let slow = try feel(#"{"feel":{"fall":"slow"}}"#)
        let medium = MatrixFeel.Resolved.standard
        let fast = try feel(#"{"feel":{"fall":"fast"}}"#)
        XCTAssertLessThan(slow.release, medium.release)
        XCTAssertLessThan(medium.release, fast.release)
        XCTAssertLessThan(slow.peakFall, fast.peakFall)
    }

    func testUnknownLevelKeepsTheStandardValue() throws {
        let bogus = try feel(#"{"feel":{"fall":"gentle","speed":"warp"}}"#)
        XCTAssertEqual(bogus.release, MatrixFeel.Resolved.standard.release)
        XCTAssertEqual(bogus.phaseStep, MatrixFeel.Resolved.standard.phaseStep)
    }

    func testSensitivityBendsTheEnergyCurve() throws {
        let mellow = try feel(#"{"feel":{"sensitivity":"mellow"}}"#)
        let twitchy = try feel(#"{"feel":{"sensitivity":"twitchy"}}"#)
        XCTAssertLessThan(mellow.energyFloor, twitchy.energyFloor)
        XCTAssertLessThan(mellow.energyPerSession, twitchy.energyPerSession)
    }

    func testJitterIsAbsoluteAndOptional() throws {
        XCTAssertNil(MatrixFeel.Resolved.standard.jitter)
        XCTAssertEqual(try feel(#"{"feel":{"jitter":"none"}}"#).jitter, 1.0...1.0)
        let chaotic = try feel(#"{"feel":{"jitter":"chaotic"}}"#).jitter
        XCTAssertEqual(chaotic?.lowerBound, 0.45)
    }

    func testPatternHoldWidensAndNarrows() throws {
        XCTAssertEqual(try feel(#"{"patternHold":"short"}"#).patternHold, 5...9)
        XCTAssertEqual(try feel(#"{"patternHold":"long"}"#).patternHold, 16...28)
    }

    func testSleepIsOverridable() throws {
        let quiet = try feel(#"{"sleep":{"face":"(-.-)","zzz":false}}"#)
        XCTAssertEqual(quiet.sleepFace, "(-.-)")
        XCTAssertFalse(quiet.sleepZzz)
        // An empty face is ignored rather than blanking the display.
        XCTAssertEqual(try feel(#"{"sleep":{"face":""}}"#).sleepFace,
                       MatrixFeel.Resolved.standard.sleepFace)
    }
}
