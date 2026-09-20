// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Grok Bot's cache moved from schemaVersion 3 to 4 on 2026-09-19 and took the
/// alarm with it: the reader looked for `lastEntry.sessionPreview.kind`, v4
/// dropped that wrapper, the field went nil everywhere, and no row could turn
/// red again. Nothing threw and nothing logged — the panel just went quiet,
/// which is this project's worst failure mode.
///
/// These pin both shapes, and the two ways a bot is known to be working.
final class GrokBotWorkingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func bot(
        _ name: String,
        kind: String? = nil,
        text: String? = nil,
        secondsIdle: TimeInterval = 10_000
    ) -> GrokBotRoster.Bot {
        GrokBotRoster.Bot(
            id: name.lowercased(),
            name: name,
            updatedAt: now.addingTimeInterval(-secondsIdle),
            lastEntryKind: kind,
            lastEntryText: text,
            awaitingUser: false,
            unreadCount: 0,
            isHidden: false,
            isChannel: false
        )
    }

    private func rows(_ bots: [GrokBotRoster.Bot], awaiting: Set<String> = []) -> [AgentRow] {
        GrokBotWatcher.sessions(
            from: [.success(GrokBotRoster(bots: bots))],
            at: now,
            awaitingReply: awaiting
        ).first?.children ?? []
    }

    // MARK: - Both schema shapes

    /// v4: the card kind sits directly on `lastEntry`.
    func testAPendingCardIsSeenInTheFlatV4Shape() throws {
        let json = #"""
        {"schemaVersion":4,"value":{"rows":[
          {"id":"f31","name":"Researcher","updatedAt":1787981015812,
           "lastEntry":{"kind":"widget_options","text":"Still holding?"},
           "awaitingUserResponse":null,"isHiddenFromSidebar":false,"isGroup":false}
        ]}}
        """#
        let roster = try GrokBotRoster.parse(Data(json.utf8)).get()

        XCTAssertEqual(roster.bots.first?.lastEntryKind, GrokBotRoster.cardPendingKind)
    }

    /// v3: both fields exist and the flat one lies. `lastEntry.kind` reads
    /// "text" while the card is pending, so the wrapper has to win — reading
    /// the flat field first would miss every v3 card.
    func testTheWrapperWinsWhenBothShapesArePresent() throws {
        let json = #"""
        {"schemaVersion":3,"value":{"rows":[
          {"id":"f31","name":"Researcher","updatedAt":1787981015812,
           "lastEntry":{"kind":"text","sessionPreview":{"kind":"widget_options"}},
           "awaitingUserResponse":null,"isHiddenFromSidebar":false,"isGroup":false}
        ]}}
        """#
        let roster = try GrokBotRoster.parse(Data(json.utf8)).get()

        XCTAssertEqual(roster.bots.first?.lastEntryKind, GrokBotRoster.cardPendingKind)
    }

    /// The v4 payload as actually captured, whole. A bot mid-answer is working,
    /// not idle, and certainly not red.
    func testARealV4RowReadsAsWorkingWhileItEmits() throws {
        let json = #"""
        {"schemaVersion":4,"value":{"rows":[
          {"id":"57aa2c06","name":"Nami Star","updatedAt":1789863396319,
           "lastActivityAt":1789863396319,"harness":"temporal","origin":"user",
           "lastEntry":{"kind":"text","text":"On it — packing the profile"},
           "lastViewedAt":1789863396319,"unreadCount":0,"hasUnread":false,
           "awaitingUserResponse":null,"isHiddenFromSidebar":false,"isGroup":false}
        ]}}
        """#
        let bots = try GrokBotRoster.parse(Data(json.utf8)).get().bots
        let emittedJustNow = Date(timeIntervalSince1970: 1_789_863_396.319 + 5)
        let row = try XCTUnwrap(
            GrokBotWatcher.sessions(
                from: [.success(GrokBotRoster(bots: bots))],
                at: emittedJustNow
            ).first?.children.first
        )

        XCTAssertEqual(row.state, .working)
        XCTAssertFalse(row.needsAction)
    }

    // MARK: - The two certainties

    func testABotThatJustEmittedIsWorking() throws {
        let row = try XCTUnwrap(rows([bot("Nami", kind: "text", secondsIdle: 5)]).first)

        XCTAssertEqual(row.state, .working)
    }

    /// The measured case: the user sent something and `lastEntry` — which holds
    /// bot messages only — has not changed since. It owes an answer, however
    /// long it has been quiet, so the clock is not consulted.
    func testABotThatOwesTheUserAReplyIsWorkingHoweverLongItIsQuiet() throws {
        let stale = bot("Nami", kind: "text", secondsIdle: 4_000)
        let row = try XCTUnwrap(rows([stale], awaiting: ["nami"]).first)

        XCTAssertEqual(row.state, .working, "a bot that has not answered yet is still working")
    }

    /// Quiet means finished, waiting on you, *or* tasked by another bot and not
    /// yet started. Three states wearing one face, so the row claims none of
    /// them.
    func testAQuietBotClaimsNothing() throws {
        let row = try XCTUnwrap(rows([bot("Nami", kind: "text", secondsIdle: 4_000)]).first)

        XCTAssertEqual(row.state, .idle)
        XCTAssertFalse(row.needsAction)
    }

    /// A waiting card outranks a busy one: red is the whole point of the app.
    func testNeedingYouBeatsWorking() throws {
        let busy = bot("Nami", kind: GrokBotRoster.cardPendingKind, secondsIdle: 2)
        let row = try XCTUnwrap(rows([busy]).first)

        XCTAssertEqual(row.state, .needsInput)
        XCTAssertTrue(row.needsAction)
    }

    /// Collapsed, the group wears its busiest child — which is how a bot woken
    /// by another bot, with no user message anywhere, becomes visible.
    func testTheCollapsedGroupShowsWorkingWhenAnyBotIs() throws {
        let group = try XCTUnwrap(
            GrokBotWatcher.sessions(
                from: [.success(GrokBotRoster(bots: [
                    bot("Nami", kind: "text", secondsIdle: 9_000),
                    bot("Hitomi", kind: "text", secondsIdle: 3)
                ]))],
                at: now
            ).first
        )

        XCTAssertEqual(group.latest.state, .working)
        XCTAssertFalse(group.latest.needsAction)
    }
}
