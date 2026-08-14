// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// The gear train that replaced a symbol which visibly fell apart.
///
/// Two things here are worth holding: that neighbours mesh while everything
/// else stays clear, and that the speeds are the ones the tooth counts imply.
/// Both are the kind of wrong you cannot name but can see.
@MainActor
final class GearTrainTests: XCTestCase {
    private func train(_ side: CGFloat = 120) -> [CALayer] {
        GearTrain.layer(size: CGSize(width: side, height: side), colour: .white).sublayers ?? []
    }

    func testItHasAWholeTrain() {
        XCTAssertEqual(train().count, 3)
    }

    /// The first version placed each wheel relative to the one before, and the
    /// chain curled round until the third sat on the first — 20pt apart where
    /// it needed 63. On screen that read as a bite taken out of the big gear.
    func testWheelsThatShouldNotTouchDoNotTouch() {
        let gears = train()
        for first in 0..<gears.count {
            for second in stride(from: first + 2, to: gears.count, by: 1) {
                let dx = gears[first].position.x - gears[second].position.x
                let dy = gears[first].position.y - gears[second].position.y
                let distance = (dx * dx + dy * dy).squareRoot()
                let clearance = gears[first].bounds.width / 2 + gears[second].bounds.width / 2
                XCTAssertGreaterThan(
                    distance,
                    clearance * 0.75,
                    "wheels \(first) and \(second) are on top of each other"
                )
            }
        }
    }

    /// Meshed wheels turn opposite ways. Two neighbours turning together is the
    /// one thing that makes a gear train look like a sticker.
    func testNeighboursTurnOppositeWays() {
        let directions = train().map { gear -> Double in
            let spin = gear.animation(forKey: "spin") as? CABasicAnimation
            return (spin?.toValue as? Double ?? 0) < 0 ? -1 : 1
        }
        for index in 1..<directions.count {
            XCTAssertNotEqual(
                directions[index],
                directions[index - 1],
                "wheels \(index - 1) and \(index) turn the same way"
            )
        }
    }

    /// A small wheel driven by a big one turns faster, in proportion to teeth.
    /// Equal durations would be the giveaway that nothing is really meshing.
    func testSmallerWheelsTurnFaster() {
        let durations = train().map { gear -> Double in
            (gear.animation(forKey: "spin") as? CABasicAnimation)?.duration ?? 0
        }
        for index in 1..<durations.count {
            XCTAssertLessThan(
                durations[index],
                durations[index - 1],
                "wheel \(index) should come round quicker"
            )
        }
        XCTAssertTrue(durations.allSatisfy { $0 > 0 })
    }

    /// Every wheel has to fit the box it was asked for, or a row clips it.
    func testTheTrainFitsTheBoxItWasGiven() {
        let side: CGFloat = 40
        for gear in train(side) {
            let radius = gear.bounds.width / 2
            XCTAssertGreaterThanOrEqual(gear.position.x - radius, -0.5)
            XCTAssertGreaterThanOrEqual(gear.position.y - radius, -0.5)
            XCTAssertLessThanOrEqual(gear.position.x + radius, side + 0.5)
            XCTAssertLessThanOrEqual(gear.position.y + radius, side + 0.5)
        }
    }
}
