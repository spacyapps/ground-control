// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// Picking the analyser's colour.
///
/// The ramp is derived from one colour because two pickers to get one gradient
/// right is a worse deal than a sensible darkening — but derived is exactly the
/// kind of thing that quietly stops being sensible.
final class AnalyserTintTests: XCTestCase {
    private var matrix: Theme.Matrix { DefaultTheme.theme.matrix }

    private func rgb(_ colour: NSColor) -> NSColor {
        colour.usingColorSpace(.sRGB) ?? .black
    }

    private func brightness(_ colour: NSColor) -> CGFloat {
        let colour = rgb(colour)
        return 0.2126 * colour.redComponent
            + 0.7152 * colour.greenComponent
            + 0.0722 * colour.blueComponent
    }

    func testTheTopOfTheRampIsExactlyWhatWasPicked() {
        let picked = NSColor(srgbRed: 0.2, green: 0.7, blue: 1, alpha: 1)
        let high = rgb(matrix.tinted(picked).high)
        XCTAssertEqual(high.redComponent, 0.2, accuracy: 0.01)
        XCTAssertEqual(high.greenComponent, 0.7, accuracy: 0.01)
        XCTAssertEqual(high.blueComponent, 1, accuracy: 0.01)
    }

    /// A ramp needs somewhere to ramp from. Bars at rest use the low end, and a
    /// gradient between two identical colours is a flat bar.
    func testTheBottomOfTheRampIsDarkerThanTheTop() {
        for picked: NSColor in [.systemPink, .systemGreen, .white, .systemYellow] {
            let tinted = matrix.tinted(picked)
            XCTAssertLessThan(
                brightness(tinted.low),
                brightness(tinted.high),
                "\(picked) gave no ramp"
            )
        }
    }

    /// Red is the one thing in the panel that has to keep meaning what it
    /// means, so a chosen colour must not reach it — including a chosen red.
    func testTheAlarmIsNeverRetinted() {
        for picked: NSColor in [.systemBlue, .systemRed, .black] {
            XCTAssertEqual(matrix.tinted(picked).alarm, matrix.alarm)
        }
    }

    /// The sweeping word has to belong to the display. Left as the theme's, a
    /// green message crossed magenta bars and read as two unrelated things.
    func testTheMessageFollowsTheChosenColour() {
        let picked = NSColor(srgbRed: 0.85, green: 0.1, blue: 0.75, alpha: 1)
        let text = rgb(matrix.tinted(picked).text)
        XCTAssertGreaterThan(text.redComponent, 0.5, "the word lost the hue it was given")
        XCTAssertGreaterThan(text.blueComponent, 0.5, "the word lost the hue it was given")
    }

    /// But not the same colour as the bars: letters that match disappear into
    /// them, and all that shows the word is the dent it makes.
    func testTheMessageStaysReadableAgainstTheBars() {
        for picked: NSColor in [.systemPink, .systemBlue, .systemGreen, .black] {
            let tinted = matrix.tinted(picked)
            XCTAssertGreaterThan(
                brightness(tinted.text) - brightness(tinted.high),
                0.1,
                "\(picked) left the word too close to its bars"
            )
        }
    }

    /// The grid the bars sit in belongs to the theme, not to the choice.
    func testTheUnlitGridAndMessagesAreLeftAlone() {
        let tinted = matrix.tinted(.systemPurple)
        XCTAssertEqual(tinted.unlit, matrix.unlit)
        XCTAssertEqual(tinted.messages, matrix.messages)
    }

    /// Black is the case the derivation can break on: darkening it further
    /// leaves a ramp from black to black, and the analyser vanishes.
    func testAVeryDarkChoiceStillLeavesSomethingVisible() {
        let tinted = matrix.tinted(.black)
        XCTAssertEqual(brightness(tinted.high), 0, accuracy: 0.01)
        XCTAssertGreaterThan(
            tinted.peak.alphaComponent,
            0,
            "the peak mark is all that shows a black analyser"
        )
        XCTAssertGreaterThan(
            brightness(tinted.peak),
            0.2,
            "a black choice must not erase the analyser entirely"
        )
    }
}
