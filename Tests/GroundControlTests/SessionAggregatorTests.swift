// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The merge layer: hook sessions plus the Grok Bot group, one sorted list.
final class SessionAggregatorTests: XCTestCase {
    private var root = FileManager.default.temporaryDirectory
    private var grokDir = FileManager.default.temporaryDirectory
    private var preferences = Preferences(defaults: .standard)

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aggregator-\(UUID().uuidString)")
        root = base.appendingPathComponent("sessions")
        grokDir = base.appendingPathComponent("grok")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("agents"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: grokDir, withIntermediateDirectories: true)
        // A real scratch suite, not .standard — remove() now writes
        // dismissedSessions through Preferences, and .standard would be this
        // machine's real, persisted app settings.
        preferences = Preferences(defaults: try XCTUnwrap(UserDefaults(suiteName: "Aggregator-\(UUID().uuidString)")))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func makeAggregator() -> SessionAggregator {
        SessionAggregator(
            store: SessionStore(
                root: root,
                agentsRoot: root.appendingPathComponent("agents"),
                preferences: preferences
            ),
            grok: GrokBotWatcher(directory: grokDir),
            preferences: preferences
        )
    }

    private func writeSession(_ id: String, needsAction: Bool, ts: Int) throws {
        let json = #"{"session_id":"\#(id)","name":"\#(id)","state":"working","#
            + #""message":"m","needs_action":\#(needsAction),"ts":\#(ts)}"#
        try json.write(to: root.appendingPathComponent("\(id).jsonl"), atomically: true, encoding: .utf8)
    }

    private func writeRoster(pendingCard: Bool, updatedAt: Int = 1787981000000) throws {
        let key = "sand.client.slice.account.x.roster.last-roster"
        let preview = pendingCard ? #"{"kind":"widget_options"}"# : "null"
        let json = #"""
        {"schemaVersion":3,"value":{"rows":[
          {"id":"bot1","name":"Researcher","updatedAt":\#(updatedAt),
           "lastEntry":{"kind":"text","sessionPreview":\#(preview)},
           "awaitingUserResponse":null,"isHiddenFromSidebar":false,"isGroup":false}
        ]}}
        """#
        let file = grokDir.appendingPathComponent("\(Base32Test.encode(key)).blob")
        try json.write(to: file, atomically: true, encoding: .utf8)
    }

    func testGrokGroupAppearsBesideHookSessions() throws {
        try writeSession("alpha", needsAction: false, ts: 100)
        try writeRoster(pendingCard: false)

        let aggregator = makeAggregator()
        aggregator.start()

        XCTAssertEqual(Set(aggregator.sessions.map(\.id)), ["alpha", GrokBotWatcher.groupID])
    }

    func testANeedyGrokGroupSortsAboveAQuietHookSession() throws {
        try writeSession("alpha", needsAction: false, ts: 9_999_999_999)
        try writeRoster(pendingCard: true)

        let aggregator = makeAggregator()
        aggregator.start()

        XCTAssertEqual(
            aggregator.sessions.first?.id,
            GrokBotWatcher.groupID,
            "needs-action pins to the top even against a more recent quiet row"
        )
    }

    func testNoGrokFilesLeavesJustTheHookSessions() throws {
        try writeSession("alpha", needsAction: false, ts: 100)

        let aggregator = makeAggregator()
        aggregator.start()

        XCTAssertEqual(aggregator.sessions.map(\.id), ["alpha"])
    }

    func testGrokGroupCanBeTurnedOff() throws {
        try writeRoster(pendingCard: false)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AggregatorOff-\(UUID().uuidString)"))
        defaults.set(false, forKey: "showsGrokBot")

        let aggregator = SessionAggregator(
            store: SessionStore(root: root, agentsRoot: root.appendingPathComponent("agents")),
            grok: GrokBotWatcher(directory: grokDir),
            preferences: Preferences(defaults: defaults)
        )
        aggregator.start()

        XCTAssertTrue(aggregator.sessions.isEmpty)
    }

    // MARK: - Removing a row with no file behind it

    func testRemovingAHookSessionDeletesItsFile() throws {
        try writeSession("alpha", needsAction: false, ts: 100)
        let aggregator = makeAggregator()
        aggregator.start()
        XCTAssertEqual(aggregator.sessions.map(\.id), ["alpha"])

        aggregator.remove(sessionID: "alpha")
        aggregator.reload()

        XCTAssertTrue(aggregator.sessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("alpha.jsonl").path))
    }

    func testRemovingTheGrokBotGroupDismissesItRatherThanNoOping() throws {
        try writeRoster(pendingCard: false)
        let aggregator = makeAggregator()
        aggregator.start()
        XCTAssertEqual(aggregator.sessions.map(\.id), [GrokBotWatcher.groupID])

        aggregator.remove(sessionID: GrokBotWatcher.groupID)

        XCTAssertTrue(aggregator.sessions.isEmpty, "the group has no file to delete, but remove() must still hide it")
    }

    /// The rule this covers is not Grok Bot's — it is the one every fileless
    /// row gets: dismissing hides it until something genuinely new happens,
    /// rather than for good. It was previously proved against a Codex thread,
    /// which no longer exists as a producer.
    func testADismissedGrokGroupReappearsOnceSomethingGenuinelyNewHappens() throws {
        try writeRoster(pendingCard: false)
        let aggregator = makeAggregator()
        aggregator.start()
        aggregator.remove(sessionID: GrokBotWatcher.groupID)
        XCTAssertTrue(aggregator.sessions.isEmpty)

        try writeRoster(pendingCard: false, updatedAt: 1787984600000)
        aggregator.reload()
        XCTAssertEqual(aggregator.sessions.map(\.id), [GrokBotWatcher.groupID])
    }
}
