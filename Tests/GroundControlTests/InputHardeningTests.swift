// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The app reads `.jsonl` files another process writes into a world-touchable
/// temp folder. The two values that reach past display — the id that becomes a
/// filename, and the file's own size — are checked before use.
final class InputHardeningTests: XCTestCase {
    // MARK: - Ids as filenames

    func testAPlainIDPasses() {
        XCTAssertTrue(SessionEvent.isPlainID("a1b2c3d4-e5f6-7890-abcd-ef0123456789"))
        XCTAssertTrue(SessionEvent.isPlainID("session_42"))
    }

    func testATraversalIDIsRejected() {
        for bad in ["../../etc/passwd", "a/b", "..", ".", "a.b", "", String(repeating: "x", count: 200), "a b"] {
            XCTAssertFalse(SessionEvent.isPlainID(bad), "\(bad) must not become a filename")
        }
    }

    /// A line whose `session_id` would climb out of the folder does not decode,
    /// so the file it is in is silently ignored — no row, nothing to remove.
    func testAnEventWithATraversalIDDoesNotDecode() {
        let json = #"{"session_id":"../../../../tmp/x","state":"idle","message":"","ts":1}"#
        XCTAssertNil(try? JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8)))

        let ok = #"{"session_id":"abc123","state":"idle","message":"","ts":1}"#
        XCTAssertNotNil(try? JSONDecoder().decode(SessionEvent.self, from: Data(ok.utf8)))
    }

    func testAnAgentEventWithATraversalIDDoesNotDecode() {
        let json = #"{"session_id":"abc","agent_id":"../../x","state":"done","message":"","ts":1}"#
        XCTAssertNil(try? JSONDecoder().decode(AgentEvent.self, from: Data(json.utf8)))
    }

    // MARK: - File size

    private func write(_ bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bounded-\(UUID().uuidString).bin")
        try Data(count: bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAFileWithinTheLimitIsRead() throws {
        let url = try write(1_024)
        XCTAssertEqual(BoundedRead.data(at: url, limit: 4_096)?.count, 1_024)
    }

    func testAFileOverTheLimitIsNotRead() throws {
        let url = try write(8_192)
        XCTAssertNil(BoundedRead.data(at: url, limit: 4_096))
        XCTAssertNil(BoundedRead.string(at: url, limit: 4_096))
    }

    func testAMissingFileIsNil() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID()).bin")
        XCTAssertNil(BoundedRead.data(at: url, limit: 4_096))
    }
}
