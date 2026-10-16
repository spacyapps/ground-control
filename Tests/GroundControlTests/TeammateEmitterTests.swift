// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Agent-team teammates, exercised by running the real `cc-notify`.
///
/// The payloads are verbatim from a live `claude` 2.1.301 team of two
/// (alpha, beta) captured 2026-10-15, ids shortened — see docs/HOOK-PAYLOADS.md.
final class TeammateEmitterTests: XCTestCase {
    private var home = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("teammate-emitter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var emitter: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/cc-notify")
            .path
    }

    private func run(_ payload: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [emitter]
        process.environment = ["TMPDIR": home.path + "/"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    private func childState() throws -> [String: Any] {
        let folder = home.appendingPathComponent("groundcontrol/agents")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .first { $0.hasSuffix(".jsonl") })
        let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        let last = try XCTUnwrap(text.split(separator: "\n").last)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any])
    }

    private func payload(_ event: String) -> String {
        #"{"session_id":"b33767d7","agent_id":"abeta-062bcdeacf7e9609","agent_type":"beta","#
            + #""hook_event_name":"\#(event)","teammate_name":"beta","team_name":"session-b33767d7"}"#
    }

    /// The stop comes first and says "done"; the idle that follows must win,
    /// because `done` is what the app lists for half an hour and then drops.
    func testTeammateIdleLeavesTheChildIdleNotDone() throws {
        try run(payload("SubagentStop"))
        XCTAssertEqual(try childState()["state"] as? String, "done")

        try run(payload("TeammateIdle"))
        let row = try childState()
        XCTAssertEqual(row["state"] as? String, "idle")
        XCTAssertEqual(row["agent_type"] as? String, "beta")
    }

    /// A teammate that is shut down gets a stop and no idle, so it stays
    /// `done` and ages out like any other finished child.
    func testShutDownTeammateStaysDone() throws {
        try run(payload("SubagentStart"))
        try run(payload("SubagentStop"))
        XCTAssertEqual(try childState()["state"] as? String, "done")
    }
}
