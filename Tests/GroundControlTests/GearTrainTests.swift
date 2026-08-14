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
        XCTAssertEqual(train().count, 2)
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

    /// The train deliberately overflows and is clipped by the avatar's plate:
    /// fitted inside, the teeth were too small to see turning. What must hold
    /// is that every wheel still has its centre on screen — a wheel cropped to
    /// an arc reads as a stray curve rather than as a gear.
    func testEveryWheelKeepsItsCentreInTheBox() {
        let side: CGFloat = 40
        for gear in train(side) {
            XCTAssertTrue((0...side).contains(gear.position.x), "x \(gear.position.x)")
            XCTAssertTrue((0...side).contains(gear.position.y), "y \(gear.position.y)")
        }
    }

    /// And it does overflow — otherwise the teeth are back to a blur.
    func testTheTrainIsDrawnLargerThanTheBox() {
        let side: CGFloat = 40
        let widest = train(side).map(\.bounds.width).max() ?? 0
        XCTAssertGreaterThan(widest, side * 0.6, "the wheels shrank back to nothing")
    }
}
