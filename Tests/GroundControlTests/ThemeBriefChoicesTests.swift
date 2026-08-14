// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The two questions that govern every image an author is about to draw: how
/// the frame meets a resize, and which colour is being keyed out.
///
/// Neither can be deduced from the artwork afterwards. A nine-grid needs
/// corners drawn as corners and edges that tile, decided before a pixel exists;
/// and a key colour has to be one the art never uses, so a fixed green erases
/// any theme that happens to be green.
final class ThemeBriefChoicesTests: XCTestCase {
    private func brief(_ frame: ThemeBrief.Frame, key: String = "#00FF00") -> ThemeBrief {
        var brief = ThemeBrief.placeholder
        brief.background = "an ornate carved frame"
        brief.frame = frame
        brief.keyColour = key
        return brief
    }

    func testSimpleAsksForOneScaledPicture() {
        let prompt = ThemePromptBuilder.prompt(for: brief(.simple))
        XCTAssertTrue(prompt.contains("\"lockAspect\": true"))
        XCTAssertTrue(prompt.contains("\"resize\": \"aspect\""))
        XCTAssertFalse(prompt.contains("corner │"), "simple frames get no slicing diagram")
        XCTAssertTrue(prompt.contains("The whole picture scales"))
    }

    func testNinegridAsksForCornersAndTilingEdges() {
        let prompt = ThemePromptBuilder.prompt(for: brief(.ninegrid))
        XCTAssertTrue(prompt.contains("\"lockAspect\": false"))
        XCTAssertTrue(prompt.contains("capInsets"))
        XCTAssertTrue(prompt.contains("\"resize\": \"free\""))
        XCTAssertTrue(prompt.contains("450px"), "the size trap has to be stated")
        XCTAssertTrue(prompt.contains("seamless"), "edges must be told to tile")
    }

    /// The bug this prevents: a magenta-keyed theme handed a prompt that says
    /// green everywhere, so the model fills green and the frame keeps it.
    func testTheChosenKeyColourReplacesEveryMention() {
        for frame in ThemeBrief.Frame.allCases {
            let prompt = ThemePromptBuilder.prompt(for: brief(frame, key: "#FF00FF"))
            XCTAssertTrue(prompt.contains("#FF00FF"), "\(frame) never names the chosen colour")
            XCTAssertFalse(prompt.contains("#00FF00"), "\(frame) still names green")
        }
    }

    func testTheChoicesAreStatedBeforeTheArtworkIsDescribed() {
        let prompt = ThemePromptBuilder.prompt(for: brief(.ninegrid))
        guard let choices = prompt.range(of: "Two things that govern everything below"),
              let drawing = prompt.range(of: "capInsets") else {
            return XCTFail("prompt lost its sections")
        }
        XCTAssertLessThan(choices.lowerBound, drawing.lowerBound)
    }

    /// A theme with no background art asks neither question.
    func testNoBackgroundMeansNoFrameSection() {
        var plain = ThemeBrief.placeholder
        plain.background = ""
        let prompt = ThemePromptBuilder.prompt(for: plain)
        XCTAssertFalse(prompt.contains("Two things that govern"))
        XCTAssertFalse(prompt.contains("corner │"), "no artwork, no frame instructions")
    }
}
