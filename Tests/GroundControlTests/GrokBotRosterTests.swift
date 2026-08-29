// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Parsing Grok Bot's undocumented `roster.last-roster` blob. Fixtures are cut
/// down from real captures (docs/GROK-BOT-INTEGRATION.md).
final class GrokBotRosterTests: XCTestCase {
    private func parse(_ json: String) -> Result<GrokBotRoster, GrokBotRoster.ParseError> {
        GrokBotRoster.parse(Data(json.utf8))
    }

    func testReadsABotWithNoPendingCard() throws {
        let roster = try parse(#"""
        {"schemaVersion":3,"value":{"rows":[
          {"id":"f31","name":"Researcher","updatedAt":1787981744887,
           "unreadCount":0,"awaitingUserResponse":null,
           "lastEntry":{"kind":"text","sessionPreview":null},
           "isHiddenFromSidebar":false,"isGroup":false}
        ]}}
        """#).get()

        XCTAssertEqual(roster.bots.count, 1)
        let bot = try XCTUnwrap(roster.bots.first)
        XCTAssertEqual(bot.name, "Researcher")
        XCTAssertNil(bot.sessionPreviewKind)
        XCTAssertFalse(bot.awaitingUser)
        XCTAssertEqual(bot.updatedAt, Date(timeIntervalSince1970: 1_787_981_744.887))
    }

    func testSeesAPendingDecisionCard() throws {
        let roster = try parse(#"""
        {"schemaVersion":3,"value":{"rows":[
          {"id":"f31","name":"Researcher","updatedAt":1787981015812,
           "lastEntry":{"kind":"text","sessionPreview":{"kind":"widget_options",
             "prompt":"Still holding on the mini?"}},
           "awaitingUserResponse":null,"isHiddenFromSidebar":false,"isGroup":false}
        ]}}
        """#).get()

        XCTAssertEqual(roster.bots.first?.sessionPreviewKind, "widget_options")
    }

    func testReadsAHardBlockOnAwaitingUserResponse() throws {
        let roster = try parse(#"""
        {"schemaVersion":3,"value":{"rows":[
          {"id":"f31","name":"Researcher","updatedAt":1,
           "awaitingUserResponse":{"reason":"captcha"},
           "lastEntry":{"kind":"text"},"isHiddenFromSidebar":false,"isGroup":false}
        ]}}
        """#).get()

        XCTAssertTrue(roster.bots.first?.awaitingUser == true)
    }

    func testMarksHiddenAndChannelRows() throws {
        let roster = try parse(#"""
        {"schemaVersion":3,"value":{"rows":[
          {"id":"a","name":"Hidden","updatedAt":1,"isHiddenFromSidebar":true,"isGroup":false},
          {"id":"b","name":"A Channel","updatedAt":1,"isHiddenFromSidebar":false,"isGroup":true}
        ]}}
        """#).get()

        XCTAssertTrue(roster.bots[0].isHidden)
        XCTAssertTrue(roster.bots[1].isChannel)
    }

    // MARK: - The format moved

    func testNotJSONFails() {
        XCTAssertEqual(parse("not json at all"), .failure(.notJSON))
    }

    func testADifferentSliceIsNotARoster() {
        // The composer-drafts blob: `value.agents`, no `value.rows`.
        let result = parse(#"{"schemaVersion":1,"value":{"agents":{}}}"#)
        guard case .failure(.unexpectedShape) = result else {
            return XCTFail("a non-roster blob must not parse as one")
        }
    }

    func testARowWithoutAnIdFailsRatherThanGuesses() {
        let result = parse(#"""
        {"schemaVersion":3,"value":{"rows":[{"name":"No Id","updatedAt":1}]}}
        """#)
        guard case .failure(.unexpectedShape) = result else {
            return XCTFail("a row with no id means the shape moved")
        }
    }

    func testAFutureSchemaStillParsesWhenTheShapeHolds() throws {
        // A bumped version we have never seen is fine as long as the fields we
        // read are still there — only a real shape change should degrade.
        let roster = try parse(#"""
        {"schemaVersion":9,"value":{"rows":[
          {"id":"a","name":"Still Works","updatedAt":1,"isHiddenFromSidebar":false,"isGroup":false}
        ]}}
        """#).get()
        XCTAssertEqual(roster.bots.first?.name, "Still Works")
    }
}
