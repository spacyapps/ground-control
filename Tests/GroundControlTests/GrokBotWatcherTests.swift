// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

final class GrokBotWatcherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func bot(
        _ name: String,
        preview: String? = nil,
        awaiting: Bool = false,
        hidden: Bool = false,
        channel: Bool = false,
        at seconds: TimeInterval = 1_000_000
    ) -> GrokBotRoster.Bot {
        GrokBotRoster.Bot(
            id: name.lowercased(),
            name: name,
            updatedAt: Date(timeIntervalSince1970: seconds),
            sessionPreviewKind: preview,
            awaitingUser: awaiting,
            unreadCount: 0,
            isHidden: hidden,
            isChannel: channel
        )
    }

    private func map(_ bots: [GrokBotRoster.Bot]) -> [Session] {
        GrokBotWatcher.sessions(from: [.success(GrokBotRoster(bots: bots))], at: now)
    }

    // MARK: - Shape

    func testNoRosterFilesMeansNoRow() {
        XCTAssertTrue(GrokBotWatcher.sessions(from: [], at: now).isEmpty)
    }

    func testAnEmptyRosterMeansNoRow() {
        XCTAssertTrue(map([]).isEmpty)
    }

    func testBotsBecomeChildrenUnderOneGrokParent() throws {
        let sessions = map([bot("Researcher"), bot("Scout")])
        XCTAssertEqual(sessions.count, 1)
        let parent = try XCTUnwrap(sessions.first)
        XCTAssertEqual(parent.id, GrokBotWatcher.groupID)
        XCTAssertEqual(parent.source, "grokbot")
        XCTAssertEqual(parent.displayName(renames: [:]), "Grok Bot")
        XCTAssertEqual(parent.hostApp, GrokBotWatcher.appPath)
        XCTAssertEqual(Set(parent.children.map(\.displayName)), ["Researcher", "Scout"])
        XCTAssertTrue(parent.children.allSatisfy { $0.source == "grokbot" })
    }

    func testHiddenAndChannelBotsAreDropped() {
        let sessions = map([bot("Real"), bot("Hidden", hidden: true), bot("Room", channel: true)])
        XCTAssertEqual(sessions.first?.children.map(\.displayName), ["Real"])
    }

    func testChildrenSortNewestFirst() {
        let sessions = map([bot("Older", at: 10), bot("Newer", at: 99)])
        XCTAssertEqual(sessions.first?.children.map(\.displayName), ["Newer", "Older"])
    }

    // MARK: - Needs you

    func testAPendingCardMakesTheBotAndTheGroupNeedy() throws {
        let sessions = map([bot("Idle One"), bot("Waiting", preview: "widget_options")])
        let parent = try XCTUnwrap(sessions.first)
        XCTAssertTrue(parent.needsAction, "the collapsed group inherits the dot")
        XCTAssertEqual(parent.state, .needsInput, "the whole group takes the needsInput mood")

        let waiting = try XCTUnwrap(parent.children.first { $0.displayName == "Waiting" })
        XCTAssertEqual(waiting.state, .needsInput)
        XCTAssertTrue(waiting.needsAction)

        let quiet = try XCTUnwrap(parent.children.first { $0.displayName == "Idle One" })
        XCTAssertEqual(quiet.state, .idle)
        XCTAssertFalse(quiet.needsAction)
    }

    func testAnAnsweredCardIsNotNeedy() {
        let sessions = map([bot("Answered", preview: "widget_answered")])
        XCTAssertFalse(sessions.first?.needsAction ?? true)
        XCTAssertEqual(sessions.first?.state, .idle)
    }

    func testAHardBlockAlsoCounts() {
        let sessions = map([bot("Blocked", awaiting: true)])
        XCTAssertEqual(sessions.first?.children.first?.state, .needsInput)
    }

    // MARK: - The format moved

    func testAShapeBreakShowsAVisibleRowNotSilence() throws {
        let sessions = GrokBotWatcher.sessions(
            from: [.failure(.unexpectedShape("value.rows missing"))],
            at: now
        )
        let parent = try XCTUnwrap(sessions.first)
        XCTAssertEqual(parent.displayName(renames: [:]), "Grok Bot")
        XCTAssertTrue(parent.children.isEmpty)
        XCTAssertTrue(parent.message.contains("can't read status"))
    }

    func testNotJSONIsIgnoredRatherThanDegraded() {
        // A blob that is not JSON at all is a different slice, not our format
        // breaking — no row, no alarm.
        XCTAssertTrue(GrokBotWatcher.sessions(from: [.failure(.notJSON)], at: now).isEmpty)
    }

    func testMultipleAccountRostersMerge() {
        let sessions = GrokBotWatcher.sessions(from: [
            .success(GrokBotRoster(bots: [bot("Work Bot")])),
            .success(GrokBotRoster(bots: [bot("Home Bot")]))
        ], at: now)
        XCTAssertEqual(Set(sessions.first?.children.map(\.displayName) ?? []), ["Work Bot", "Home Bot"])
    }

    // MARK: - Reading the folder

    func testReadRostersPicksTheRosterBlobAndSkipsOthers() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokWatcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func write(sliceKey: String, json: String) throws {
            let name = Base32Test.encode(sliceKey)
            try json.write(to: dir.appendingPathComponent("\(name).blob"), atomically: true, encoding: .utf8)
        }

        try write(
            sliceKey: "sand.client.slice.account.x.roster.last-roster",
            json: #"""
            {"schemaVersion":3,"value":{"rows":[
              {"id":"a","name":"Bot","updatedAt":1,"isHiddenFromSidebar":false,"isGroup":false}
            ]}}
            """#
        )
        try write(
            sliceKey: "sand.client.slice.account.x.composer-drafts",
            json: #"{"schemaVersion":1,"value":{"agents":{}}}"#
        )

        let rosters = GrokBotWatcher.readRosters(in: dir)
        XCTAssertEqual(rosters.count, 1)
        XCTAssertEqual((try? rosters.first?.get())?.bots.first?.name, "Bot")
    }
}

/// Encode side of `Base32`, test-only — the app only ever decodes.
enum Base32Test {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")

    static func encode(_ string: String) -> String {
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in Array(string.utf8) {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buffer >> bits) & 0x1F])
            }
        }
        if bits > 0 {
            output.append(alphabet[(buffer << (5 - bits)) & 0x1F])
        }
        return output
    }
}
