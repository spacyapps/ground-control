// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import SkinTerminal

/// The marquee is only worth having if the letters are actually readable, so
/// the glyph grid is worth pinning down.
final class MatrixFontTests: XCTestCase {
    /// Renders a string to text art so a wrong glyph is visible in the failure.
    private func render(_ text: String) -> [String] {
        (0..<MatrixFont.height).map { row in
            (0..<MatrixFont.columns(for: text)).map { column in
                MatrixFont.isLit(text: text, column: column, row: row) ? "#" : "."
            }.joined()
        }
    }

    func testColumnsIncludeGapsButNotATrailingOne() {
        XCTAssertEqual(MatrixFont.columns(for: "A"), 3)
        XCTAssertEqual(MatrixFont.columns(for: "AB"), 7)
        XCTAssertEqual(MatrixFont.columns(for: ""), 0)
    }

    func testLetterAIsShapedLikeAnA() {
        XCTAssertEqual(render("A"), [".#.", "#.#", "###", "#.#", "#.#"])
    }

    func testSpaceIsBlank() {
        XCTAssertEqual(render(" "), Array(repeating: "...", count: 5))
    }

    /// Five rows cannot carry descenders, so everything renders in capitals.
    func testLowercaseRendersAsUppercase() {
        XCTAssertEqual(render("a"), render("A"))
    }

    func testUnknownCharactersFallBackToBlankRatherThanCrashing() {
        XCTAssertEqual(render("~"), Array(repeating: "...", count: 5))
    }

    func testOutOfRangeLookupsAreSafe() {
        XCTAssertFalse(MatrixFont.isLit(text: "A", column: -1, row: 0))
        XCTAssertFalse(MatrixFont.isLit(text: "A", column: 99, row: 0))
        XCTAssertFalse(MatrixFont.isLit(text: "A", column: 0, row: 9))
    }

    /// The word the marquee actually shows must be fully mapped.
    func testEveryLetterOfTheMarqueeHasAGlyph() {
        for character in "SPACYAPPS" {
            let lit = (0..<MatrixFont.height).contains { row in
                (0..<MatrixFont.width).contains { column in
                    MatrixFont.isLit(text: String(character), column: column, row: row)
                }
            }
            XCTAssertTrue(lit, "\(character) renders blank")
        }
    }
}
