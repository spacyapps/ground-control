// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import SkinTerminal

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
