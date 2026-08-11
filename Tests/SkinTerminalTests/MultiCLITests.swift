import XCTest
@testable import SkinTerminal

/// Rows can come from more than one CLI. Session ids are only unique per tool,
/// so `source` is what keeps them apart — see docs/HOOK-PAYLOADS.md.
final class MultiCLITests: XCTestCase {
    private func event(_ json: String) throws -> SessionEvent {
        try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
    }

    private func session(_ event: SessionEvent) -> Session {
        Session(id: event.sessionID, latest: event, children: [], acknowledgedAt: nil)
    }

    func testSourceDecodes() throws {
        let grok = try event(#"{"session_id":"a","source":"grok","name":"lunararray","ts":1}"#)
        XCTAssertEqual(grok.source, "grok")
        XCTAssertEqual(session(grok).source, "grok")
    }

    /// Lines written before `source` existed are still on disk for 24h.
    func testOlderLinesWithoutSourceReadAsClaude() throws {
        XCTAssertEqual(try event(#"{"session_id":"a","ts":1}"#).source, "claude")
    }

    /// Two CLIs can hand out the same id; the pair is what identifies a row.
    func testDifferentToolsCanShareASessionID() throws {
        let claude = try event(#"{"session_id":"same","source":"claude","name":"one","ts":1}"#)
        let grok = try event(#"{"session_id":"same","source":"grok","name":"two","ts":1}"#)
        XCTAssertEqual(claude.sessionID, grok.sessionID)
        XCTAssertNotEqual(claude.source, grok.source)
    }

    func testSortingIsUnaffectedBySource() throws {
        let older = session(try event(#"{"session_id":"a","source":"grok","ts":10}"#))
        let newer = session(try event(#"{"session_id":"b","source":"claude","ts":90}"#))
        XCTAssertEqual(SessionStore.sorted([older, newer]).map(\.id), ["b", "a"])
    }

    /// Grok sends no session title, so the folder name has to carry the row —
    /// and a trailing slash on `workspaceRoot` must not produce an empty name.
    func testNameFallsBackToFolderForToolsWithoutTitles() throws {
        let grok = try event(#"{"session_id":"a","source":"grok","cwd":"/Users/w/github/lunararray","ts":1}"#)
        XCTAssertEqual(session(grok).displayName(renames: [:]), "lunararray")
    }
}
