// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

final class MatrixMessagesTests: XCTestCase {
    func testBrandAppearsOnEveryThirdTurn() {
        XCTAssertEqual(MatrixMessages.next(turn: 3, avoiding: nil), MatrixMessages.brand)
        XCTAssertEqual(MatrixMessages.next(turn: 6, avoiding: nil), MatrixMessages.brand)
    }

    func testNeverRepeatsThePreviousMessage() {
        let previous = MatrixMessages.jokes[0]
        for turn in [1, 2, 4, 5] {
            XCTAssertNotEqual(MatrixMessages.next(turn: turn, avoiding: previous), previous)
        }
    }

    /// Anything it can say must be drawable, or it renders as gaps.
    func testEveryCannedMessageIsFullyDrawable() {
        for message in MatrixMessages.jokes + [MatrixMessages.brand] {
            XCTAssertTrue(
                message.allSatisfy(MatrixFont.supports),
                "\(message) contains a character the font cannot draw"
            )
        }
    }

    // MARK: - Harvesting

    func testHarvestPullsInterestingWordsFromSessionOutput() {
        let words = MatrixMessages.harvest(from: [
            "Bash: swiftlint --strict passed",
            "Write: VisualizerView.swift"
        ])
        XCTAssertTrue(words.contains("SWIFTLINT"))
        XCTAssertTrue(words.contains("STRICT"))
        XCTAssertTrue(words.contains("PASSED"))
    }

    func testHarvestSkipsOrdinaryWordsAndShortOnes() {
        let words = MatrixMessages.harvest(from: ["This should have been about that thing"])
        XCTAssertFalse(words.contains("SHOULD"))
        XCTAssertFalse(words.contains("ABOUT"))
        XCTAssertFalse(words.contains("HAVE"), "four letters is too short to be worth spelling")
    }

    /// Punctuation and paths must not smuggle in undrawable characters.
    func testHarvestedWordsAreAlwaysDrawable() {
        let words = MatrixMessages.harvest(from: [
            "Read: /Users/w/github/avaterm/Sources/Theme.swift — done, ~90% cached"
        ])
        for word in words {
            XCTAssertTrue(word.allSatisfy(MatrixFont.supports), "\(word) is not drawable")
        }
        XCTAssertTrue(words.contains("USERS") || words.contains("GITHUB") || words.contains("AVATERM"))
    }

    func testHarvestDeduplicates() {
        let words = MatrixMessages.harvest(from: ["SWIFTLINT swiftlint SwiftLint"])
        XCTAssertEqual(words.filter { $0 == "SWIFTLINT" }.count, 1)
    }

    func testHarvestedWordsArePreferredButNotRequired() {
        let onlyCanned = MatrixMessages.next(turn: 1, avoiding: nil, harvested: [])
        XCTAssertTrue(MatrixMessages.jokes.contains(onlyCanned) || onlyCanned == MatrixMessages.brand)
    }
}

extension MatrixMessagesTests {
    // MARK: - Theme-supplied phrases

    func testAThemesOwnPhrasesReplaceTheBuiltInOnes() {
        let themed = ["SYSTEM ONLINE", "NEURAL LINK"]
        for turn in [1, 2, 4, 5] {
            let chosen = MatrixMessages.next(turn: turn, avoiding: nil, themed: themed)
            XCTAssertTrue(themed.contains(chosen), "a stock joke leaked into a themed panel: \(chosen)")
        }
    }

    /// Words from your own sessions are not decoration, so a theme does not
    /// get to silence them.
    func testHarvestedWordsSurviveAThemesVoice() {
        var seen: Set<String> = []
        for turn in 1...60 where turn % 3 != 0 {
            seen.insert(MatrixMessages.next(
                turn: turn, avoiding: nil, harvested: ["SWIFTLINT"], themed: ["SYSTEM ONLINE"]
            ))
        }
        XCTAssertTrue(seen.contains("SWIFTLINT"))
    }

    func testTheBrandStillAppearsInAThemedPanel() {
        XCTAssertEqual(
            MatrixMessages.next(turn: 3, avoiding: nil, themed: ["SYSTEM ONLINE"]),
            MatrixMessages.brand
        )
    }

    // MARK: - Validation at load

    func testPhrasesAreUppercasedAndTrimmed() {
        XCTAssertEqual(MatrixMessages.usable([" System online "]), ["SYSTEM ONLINE"])
    }

    /// An undrawable character renders as a gap mid-word, which reads as a bug
    /// in the app rather than a typo in the theme.
    func testUndrawableOrOverlongPhrasesAreDropped() {
        let kept = MatrixMessages.usable([
            "GOOD ONE",
            "CAFÉ CRASH",                 // accent has no glyph
            "THIS PHRASE IS FAR TOO LONG" // past maxLength
        ])
        XCTAssertEqual(kept, ["GOOD ONE"])
    }

    func testEmptyThemeListFallsBackToTheBuiltInPhrases() {
        let chosen = MatrixMessages.next(turn: 1, avoiding: nil, themed: [])
        XCTAssertTrue(MatrixMessages.jokes.contains(chosen) || chosen == MatrixMessages.brand)
    }
}
