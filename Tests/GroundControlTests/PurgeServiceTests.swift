// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// mtime is the entire session lifecycle (docs/SPEC.md §2) — so these tests are
/// really testing the app's only removal rule.
final class PurgeServiceTests: XCTestCase {
    private var root = FileManager.default.temporaryDirectory
    private var agents = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurgeServiceTests-\(UUID().uuidString)")
        agents = root.appendingPathComponent("agents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeFile(_ name: String, in directory: URL, ageInHours: Double) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try #"{"session_id":"x","ts":1}"#.write(to: url, atomically: true, encoding: .utf8)
        let modified = Date().addingTimeInterval(-ageInHours * 3600)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    private func service() -> PurgeService {
        PurgeService(window: 24 * 60 * 60, roots: [root, agents])
    }

    func testDeletesFilesOlderThanTheWindow() throws {
        let stale = try makeFile("stale.jsonl", in: root, ageInHours: 25)
        XCTAssertEqual(service().purge(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testKeepsFilesInsideTheWindow() throws {
        let fresh = try makeFile("fresh.jsonl", in: root, ageInHours: 23)
        XCTAssertEqual(service().purge(), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    func testPurgesAgentFilesToo() throws {
        try makeFile("stale.jsonl", in: root, ageInHours: 30)
        try makeFile("s__a.jsonl", in: agents, ageInHours: 30)
        try makeFile("fresh.jsonl", in: root, ageInHours: 1)
        XCTAssertEqual(service().purge(), 2)
    }

    func testLeavesNonSessionFilesAlone() throws {
        let note = root.appendingPathComponent("README.txt")
        try "hello".write(to: note, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-100 * 3600)],
            ofItemAtPath: note.path
        )
        XCTAssertEqual(service().purge(), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.path))
    }
}
