// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Part two asks before it draws.
///
/// The frame used to be described at the author in one block, which produced
/// frames nobody had chosen. It now opens with four questions — motif, colours,
/// what is in each corner, what runs along the edges — and the model is told to
/// wait. These tests pin the order, because a prompt that describes the artwork
/// before asking about it is a prompt the model starts drawing from.
final class ThemeBriefChoicesTests: XCTestCase {
    private func brief(key: String = "#00FF00") -> ThemeBrief {
        var brief = ThemeBrief.placeholder
        brief.background = "an ornate carved frame"
        brief.keyColour = key
        return brief
    }

    /// Every frame is a nine-grid now. The scaled-whole option was the default,
    /// so the easy path taught nothing that survives a resize.
    func testEveryFrameIsANineGrid() {
        let prompt = ThemePromptBuilder.prompt(for: brief())
        XCTAssertTrue(prompt.contains("corner │"), "the slicing diagram is not optional")
        XCTAssertTrue(prompt.contains("capInsets"))
        XCTAssertTrue(prompt.contains("450px"), "the size trap has to be stated")
        XCTAssertTrue(prompt.contains("seamless"), "edges must be told to tile")
        XCTAssertFalse(prompt.contains("The whole picture scales"), "the other branch is gone")
    }

    /// The questions come first, and the model is told not to start.
    func testTheQuestionsComeBeforeAnythingIsDrawn() {
        let frame = ThemePromptBuilder.partTwo(for: brief())
        guard let questions = frame.range(of: "Ask me these four questions first"),
              let defaults = frame.range(of: "do not ask me about these"),
              let grid = frame.range(of: "corner │"),
              let json = frame.range(of: "Produce it in exactly this shape") else {
            return XCTFail("part two lost its sections")
        }
        XCTAssertLessThan(questions.lowerBound, defaults.lowerBound)
        XCTAssertLessThan(defaults.lowerBound, grid.lowerBound)
        XCTAssertLessThan(grid.lowerBound, json.lowerBound, "a JSON block reads as permission to start")
        XCTAssertTrue(frame.contains("Do not draw anything until I answer"))
    }

    /// All four, or the model asks one and starts on a guess for the rest.
    func testAllFourQuestionsAreThere() {
        let frame = ThemePromptBuilder.partTwo(for: brief())
        XCTAssertTrue(frame.contains("What is this frame made of?"))
        XCTAssertTrue(frame.contains("What colours?"))
        XCTAssertTrue(frame.contains("What is in each of the four corners?"))
        XCTAssertTrue(frame.contains("What runs along the edges?"))
    }

    /// The defaults exist to stop the model asking about them. Naming them is
    /// the whole point: unstated, they come back as questions.
    func testTheDefaultsAreStatedRatherThanAsked() {
        let frame = ThemePromptBuilder.partTwo(for: brief())
        XCTAssertTrue(frame.contains("Overlay is on"))
        XCTAssertTrue(frame.contains("irregular, inside and out"))
        XCTAssertTrue(frame.contains("do not spend a question on"))
    }

    /// Nothing is animated until two separate yeses: the still is right, and
    /// these specific things move. Both gates were missing — the frame brief
    /// said "draw the still first" as a footnote under the animation rules,
    /// which is where a model looks *after* deciding to animate.
    func testNothingAnimatesBeforeTwoConfirmations() {
        let frame = ThemePromptBuilder.partTwo(for: brief())
        // Phrases unique to the headings, but without their `##` — part two
        // numbers headings as it assembles them, so the literal `## Show me`
        // never appears. They still have to be specific enough to miss the
        // stage table at the top, which paraphrases all three.
        guard let still = frame.range(of: "Show me the still and wait"),
              let choose = frame.range(of: "Once I confirm the still"),
              let make = frame.range(of: "Making the frames themselves") else {
            return XCTFail("part two lost its staging")
        }
        XCTAssertLessThan(still.lowerBound, choose.lowerBound, "confirm the still first")
        XCTAssertLessThan(choose.lowerBound, make.lowerBound, "then choose, then draw frames")
        XCTAssertTrue(frame.contains("do not animate anything before asking"))
    }

    /// The overhang distinction that nothing else in the prompt makes: inward
    /// over the opening is the look; sideways into an edge gets tiled.
    func testTheStillCheckAsksAboutCornersBleedingIntoEdges() {
        let frame = ThemePromptBuilder.partTwo(for: brief())
        XCTAssertTrue(frame.contains("run too far along an edge"))
        XCTAssertTrue(frame.contains("Hanging *inward* over the opening is"))
    }

    /// Motion is chosen per corner and per edge, which is the granularity the
    /// grid already has. "Animate the frame" gets the whole thing moving.
    func testMotionIsChosenPerCornerAndPerEdge() {
        let frame = ThemePromptBuilder.partTwo(for: brief())
        XCTAssertTrue(frame.contains("Which corners move"))
        XCTAssertTrue(frame.contains("Which edges move"))
        XCTAssertTrue(frame.contains("A still frame is a perfectly good answer"))
    }

    /// An author cannot weigh a cost nobody mentioned. Both parts say it now,
    /// because both can spend an afternoon of image generation.
    func testBothPartsWarnThatFramesAreGeneratedImages() {
        let frame = ThemePromptBuilder.partTwo(for: brief())
        XCTAssertTrue(frame.contains("Every frame is a separately generated image"))

        var animated = brief()
        animated.wantsAnimation = true
        let moods = ThemePromptBuilder.partOne(for: animated)
        // Matched in fragments that cannot span a wrap: these strings are
        // hand-wrapped source, so a phrase long enough to be unambiguous is
        // also long enough to contain a newline.
        XCTAssertTrue(moods.contains("Every frame is a separate generated"))
        XCTAssertTrue(moods.contains("is 32 images, not two"), "the arithmetic persuades")
    }

    /// Both parts open with the whole job on one screen. The staging was
    /// already written down, but scattered through the sections, where it reads
    /// as advice rather than as the shape of the work — and got walked past.
    func testBothPartsOpenWithTheirStages() {
        let moods = ThemePromptBuilder.partOne(for: brief())
        XCTAssertTrue(moods.contains("| Stage | What happens | Ends when |"))
        XCTAssertTrue(moods.contains("You hand the four files back"))

        let frame = ThemePromptBuilder.partTwo(for: brief())
        XCTAssertTrue(frame.contains("| Stage | What happens | Ends when |"))
        XCTAssertTrue(frame.contains("the two places you stop and wait"))

        // The table has to arrive before the work it describes, or it is a
        // summary rather than a plan.
        guard let table = frame.range(of: "| Stage |"),
              let first = frame.range(of: "Ask me these four questions") else {
            return XCTFail("part two lost its header")
        }
        XCTAssertLessThan(table.lowerBound, first.lowerBound)
    }

    /// The bug this prevents: a magenta-keyed theme handed a prompt that says
    /// green everywhere, so the model fills green and the frame keeps it.
    func testTheChosenKeyColourReplacesEveryMention() {
        let prompt = ThemePromptBuilder.prompt(for: brief(key: "#FF00FF"))
        XCTAssertTrue(prompt.contains("#FF00FF"), "the chosen colour is never named")
        XCTAssertFalse(prompt.contains("#00FF00"), "green is still named")
    }

    /// And part one does not mention the frame at all, or the split achieves
    /// nothing.
    func testPartOneDoesNotTalkAboutTheFrame() {
        let moods = ThemePromptBuilder.partOne(for: brief())
        XCTAssertFalse(moods.contains("capInsets"), "the frame belongs to part two")
        XCTAssertFalse(moods.contains("four questions"), "and so do its questions")
        XCTAssertTrue(moods.contains("The four moods"), "and the moods to part one")
    }

    /// A theme with no background art is asked nothing about frames.
    func testNoBackgroundMeansNoFrameSection() {
        var plain = ThemeBrief.placeholder
        plain.background = ""
        let prompt = ThemePromptBuilder.prompt(for: plain)
        XCTAssertFalse(prompt.contains("Ask me these four questions"))
        XCTAssertFalse(prompt.contains("corner │"), "no artwork, no frame instructions")
    }
}

/// Motion is reserved for the two states that are asking for attention. Four
/// looping avatars means nothing stands out, which is the opposite of the
/// point.
final class AnimatedStateTests: XCTestCase {
    private var animated: ThemeBrief {
        var brief = ThemeBrief.placeholder
        brief.wantsAnimation = true
        return brief
    }

    func testWorkingAndNeedsInputAnimate() {
        let prompt = ThemePromptBuilder.prompt(for: animated)
        XCTAssertTrue(prompt.contains("working.gif"))
        XCTAssertTrue(prompt.contains("needs-input.gif"))
    }

    /// The resting states stay still whatever the author asked for.
    func testIdleAndDoneNeverAnimate() {
        for wants in [true, false] {
            var brief = ThemeBrief.placeholder
            brief.wantsAnimation = wants
            let prompt = ThemePromptBuilder.prompt(for: brief)
            XCTAssertTrue(prompt.contains("idle.png"))
            XCTAssertTrue(prompt.contains("done.png"))
            XCTAssertFalse(prompt.contains("idle.gif"))
            XCTAssertFalse(prompt.contains("done.gif"))
        }
    }

    /// The starter manifest has to name the same files the prompt asked for, or
    /// the author draws a GIF the theme never loads.
    func testTheManifestNamesTheAnimatedFiles() throws {
        let json = ThemeStarterManifest.text(for: animated)
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.avatar?.states?["working"]?.image, "working.gif")
        XCTAssertEqual(manifest.avatar?.states?["needsInput"]?.image, "needs-input.gif")
        XCTAssertEqual(manifest.avatar?.states?["idle"]?.image, "idle.png")
        XCTAssertEqual(manifest.avatar?.states?["done"]?.image, "done.png")
    }

    /// Small is the only size these are ever seen at, so the prompt has to say
    /// what carries each state when a face is a few dozen pixels.
    func testThePromptSaysHowToMakeStatesReadableWhenSmall() {
        let prompt = ThemePromptBuilder.prompt(for: animated)
        XCTAssertTrue(prompt.contains("stop and look"), "needsInput needs to be called out")
        XCTAssertTrue(
            prompt.contains("Check these before you show me anything"),
            "the checks an author can actually perform, before anything is sent"
        )
        XCTAssertTrue(prompt.contains("shrunk to"), "and they have to be judged at real size")
    }
}
