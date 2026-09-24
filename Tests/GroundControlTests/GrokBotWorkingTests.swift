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
            awaitingReason: nil,
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

    // MARK: - The expiry, against a real folder

    /// The pure mapping cannot show this: the rule that decides *when* a bot
    /// owes a reply lives in `reload()`, and the bug was there. Two bots
    /// finished at 18:12:28 on the first evening and the panel kept animating,
    /// because "the clock moved and the bot stayed silent" is the user
    /// speaking — and also every other write Grok Bot makes to that file.
    ///
    /// So this drives the watcher itself, through a folder on disk, with a
    /// clock it can wind forward.
    func testAnOwedReplyExpiresRatherThanPinningTheRowForever() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbot-expiry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // base32 of "sand.client.slice.account.test.roster.last-roster".
        let blob = folder.appendingPathComponent(
            "onqw4zbomnwgszlooqxhg3djmnss4yldmnxxk3tufz2gk43ufzzg643umvzc43dbon2c24tpon2gk4q.blob"
        )
        func write(updatedAt: Int, text: String) throws {
            try #"""
            {"schemaVersion":4,"value":{"rows":[
              {"id":"b1","name":"Nami","updatedAt":\#(updatedAt),
               "lastEntry":{"kind":"text","text":"\#(text)"},
               "awaitingUserResponse":null,"isHiddenFromSidebar":false,"isGroup":false}
            ]}}
            """#.write(to: blob, atomically: true, encoding: .utf8)
        }

        var clock = Date(timeIntervalSince1970: 1_000_000)
        let watcher = GrokBotWatcher(directory: folder, clock: { clock })

        // A bot that spoke long ago: quiet, claiming nothing.
        try write(updatedAt: 900_000_000, text: "done then")
        watcher.reload()
        XCTAssertEqual(watcher.sessions.first?.children.first?.state, .idle)

        // The clock moves and the text does not — the user has spoken, so the
        // bot owes a reply and is working even though its own last word is old.
        try write(updatedAt: 1_000_000_000, text: "done then")
        watcher.reload()
        XCTAssertEqual(
            watcher.sessions.first?.children.first?.state,
            .working,
            "a bot that has not answered yet is working"
        )

        // Still owed a minute later: this is the deferral case worth covering.
        clock = clock.addingTimeInterval(60)
        watcher.reload()
        XCTAssertEqual(watcher.sessions.first?.children.first?.state, .working)

        // Past the window it gives up rather than animating forever.
        clock = clock.addingTimeInterval(GrokBotWatcher.owedReplyWindow)
        watcher.reload()
        XCTAssertEqual(
            watcher.sessions.first?.children.first?.state,
            .idle,
            "an owed reply must expire — one stray write pinned a row to working all evening"
        )
    }

    /// The window has to clear the longest silence actually measured mid-task,
    /// or a deferred bot is called finished.
    func testTheOwedReplyWindowOutlastsTheMeasuredDeferral() {
        XCTAssertGreaterThan(
            GrokBotWatcher.owedReplyWindow,
            229,
            "a cloud agent went quiet for 3m49s mid-task; the window must clear it"
        )
    }

    /// The tail is a trade: too short and a thinking bot flickers to idle
    /// between messages, too long and a finished one keeps animating. Emits
    /// mid-turn were measured 2–30s apart, so the window must clear the widest
    /// of those with room, and stay well under a minute and a half of lag.
    func testTheWorkingTailClearsTheMeasuredEmitGapWithoutDragging() {
        XCTAssertGreaterThanOrEqual(
            GrokBotWatcher.stillMovingWindow,
            60,
            "mid-turn gaps of 30s were measured; a shorter tail flickers"
        )
        XCTAssertLessThanOrEqual(
            GrokBotWatcher.stillMovingWindow,
            75,
            "watched live, a longer tail reads as the panel being stuck"
        )
    }

    // MARK: - The alarm, back from the dead

    /// `awaitingUserResponse` was null through every test from August onward,
    /// and the entry in LIMITATIONS said what it wrote was unconfirmed. Grok
    /// Bot 0.58.0 fills it — measured live on 2026-09-23, captured whole:
    /// a local-command approval, with the command written out as prose.
    func testARealApprovalPromptTurnsTheRowRedAndSaysWhy() throws {
        let json = #"""
        {"schemaVersion":4,"value":{"rows":[
          {"id":"2dac","name":"GC Pricing & Marketing","updatedAt":1790228744313,
           "lastEntry":{"kind":"text","text":"Permission required: ls -la ~/xcode"},
           "awaitingUserResponse":{"tabId":"auto-review",
             "reason":"Permission needed on your computer: ls -la ~/xcode",
             "since":1790228744387},
           "isHiddenFromSidebar":false,"isGroup":false}
        ]}}
        """#
        let bots = try GrokBotRoster.parse(Data(json.utf8)).get().bots
        let row = try XCTUnwrap(
            GrokBotWatcher.sessions(from: [.success(GrokBotRoster(bots: bots))], at: now)
                .first?.children.first
        )

        XCTAssertEqual(row.state, .needsInput)
        XCTAssertTrue(row.needsAction)
        XCTAssertEqual(row.message, "Permission needed on your computer: ls -la ~/xcode")
    }

    /// Answering it sets the field back to null, so the row must go quiet.
    /// Without this a row could sit red for the rest of the day.
    func testAnsweringClearsTheAlarm() throws {
        let json = #"""
        {"schemaVersion":4,"value":{"rows":[
          {"id":"2dac","name":"GC Pricing & Marketing","updatedAt":1790228851871,
           "lastEntry":{"kind":"text","text":"I'm in ~/xcode on your MacBook Air."},
           "awaitingUserResponse":null,
           "isHiddenFromSidebar":false,"isGroup":false}
        ]}}
        """#
        let bots = try GrokBotRoster.parse(Data(json.utf8)).get().bots
        let row = try XCTUnwrap(
            GrokBotWatcher.sessions(from: [.success(GrokBotRoster(bots: bots))], at: now)
                .first?.children.first
        )

        XCTAssertFalse(row.needsAction)
        XCTAssertEqual(row.message, "", "a quiet row says nothing")
    }
}
