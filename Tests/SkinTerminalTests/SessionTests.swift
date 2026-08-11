// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import SkinTerminal

/// Naming and dot rules — the two places where measured payload behaviour
/// (docs/HOOK-PAYLOADS.md) turns into what the user actually sees.
final class SessionTests: XCTestCase {
    private func event(name: String? = nil,
                       cwd: String? = "/Users/w/github/fluffy-carnival",
                       needsAction: Bool = false,
                       ts: Int = 100) throws -> SessionEvent {
        let nameField = name.map { "\"name\":\"\($0)\"," } ?? ""
        let cwdField = cwd.map { "\"cwd\":\"\($0)\"," } ?? ""
        let json = """
        {"session_id":"abc",\(nameField)\(cwdField)\
        "state":"working","message":"hi","needs_action":\(needsAction),"ts":\(ts)}
        """
        return try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
    }

    private func session(_ event: SessionEvent,
                         children: [AgentRow] = [],
                         acknowledgedAt: Date? = nil) -> Session {
        Session(id: "abc", latest: event, children: children, acknowledgedAt: acknowledgedAt)
    }

    func testRenameBeatsEverything() throws {
        let subject = session(try event(name: "spacyapps"))
        XCTAssertEqual(subject.displayName(renames: ["abc": "My Thing"]), "My Thing")
    }

    /// session_title differs from the folder in real sessions, and is the
    /// better label when it does.
    func testSessionTitleBeatsFolderName() throws {
        let subject = session(try event(name: "spacyapps"))
        XCTAssertEqual(subject.displayName(renames: [:]), "spacyapps")
    }

    func testFallsBackToFolderWhenTitleMissing() throws {
        let subject = session(try event(name: nil))
        XCTAssertEqual(subject.displayName(renames: [:]), "fluffy-carnival")
    }

    func testFallsBackToSessionIDWhenNothingElseIsKnown() throws {
        let subject = session(try event(name: nil, cwd: nil))
        XCTAssertEqual(subject.displayName(renames: [:]), "abc")
    }

    /// "Claude finished, your turn" is not an alarm. Treating it as one turned
    /// every completed session red and made red meaningless.
    func testIdlePromptNotificationDoesNotRaiseTheAlarm() throws {
        let json = #"{"session_id":"abc","state":"needsInput","message":"Claude is waiting","#
            + #""needs_action":true,"notification_type":"idle_prompt","ts":10}"#
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        XCTAssertFalse(event.isActionable)
        XCTAssertFalse(session(event).needsAction)
        XCTAssertEqual(session(event).state, .done, "a finished session should not wear a red face")
    }

    /// A notification that genuinely blocks still must.
    func testOtherNotificationsStillRaiseTheAlarm() throws {
        let json = #"{"session_id":"abc","state":"needsInput","message":"Allow npm install?","#
            + #""needs_action":true,"notification_type":"permission_request","ts":10}"#
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        XCTAssertTrue(event.isActionable)
        XCTAssertTrue(session(event).needsAction)
    }

    func testAcknowledgingClearsTheDotUntilSomethingNewerArrives() throws {
        let stamp = Date(timeIntervalSince1970: 100)
        let acknowledged = session(try event(needsAction: true, ts: 100), acknowledgedAt: stamp)
        XCTAssertFalse(acknowledged.needsAction)

        let newer = session(try event(needsAction: true, ts: 200), acknowledgedAt: stamp)
        XCTAssertTrue(newer.needsAction, "a newer event must light the dot again")
    }

    func testCollapsedGroupInheritsTheDotFromANeedyChild() throws {
        let childJSON = #"{"session_id":"abc","agent_id":"a1","state":"needsInput","#
            + #""message":"?","needs_action":true,"ts":5}"#
        let child = try JSONDecoder().decode(AgentEvent.self, from: Data(childJSON.utf8))
        let subject = session(
            try event(needsAction: false),
            children: [AgentRow(id: "a1", latest: child)]
        )
        XCTAssertTrue(subject.needsAction)
        XCTAssertTrue(subject.isGroup)
    }

    func testSortPinsNeedsActionAboveMoreRecentQuietSessions() throws {
        let quietRecent = Session(
            id: "quiet", latest: try event(needsAction: false, ts: 900), children: [], acknowledgedAt: nil
        )
        let needyOld = Session(
            id: "needy", latest: try event(needsAction: true, ts: 100), children: [], acknowledgedAt: nil
        )
        let sorted = SessionStore.sorted([quietRecent, needyOld])
        XCTAssertEqual(sorted.map(\.id), ["needy", "quiet"])
    }
}
