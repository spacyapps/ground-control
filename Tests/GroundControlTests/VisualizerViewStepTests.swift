// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// The seam between the resolver, the formulas and the actual bars — pumped by
/// hand so no run loop is needed.
final class VisualizerViewStepTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VisualizerStep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func view(matrix: String) throws -> VisualizerView {
        let folder = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"{ "matrix": \#(matrix) }"#.write(
            to: folder.appendingPathComponent("theme.json"), atomically: true, encoding: .utf8
        )
        let view = VisualizerView(frame: NSRect(x: 0, y: 0, width: 120, height: 20))
        view.apply(theme: ThemeLoader.loadTheme(from: folder))
        return view
    }

    private func session(_ state: SessionState, needs: Bool = false) throws -> Session {
        let json = """
        {"session_id":"\(UUID().uuidString)","name":"x","cwd":"/tmp/x",\
        "state":"\(state.rawValue)","message":"","needs_action":\(needs),\
        "ts":\(Int(Date().timeIntervalSince1970))}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        return Session(id: event.sessionID, latest: event, children: [], acknowledgedAt: nil)
    }

    private func pump(_ view: VisualizerView, _ ticks: Int = 60) {
        for _ in 0..<ticks { view.step() }
    }

    /// The bug this exists to catch: an alarm with no strobe formula must not
    /// borrow the working pattern. It stays flat — the lit floor comes from the
    /// draw side, not from the levels.
    func testAlarmWithoutAFormulaStaysFlat() throws {
        let view = try view(matrix: "{}")
        view.update(sessions: [try session(.needsInput, needs: true)])
        pump(view)
        XCTAssertTrue(view.levels.allSatisfy { $0 < 0.05 })
    }

    /// …but a working session with no formula still animates off the rotation.
    func testWorkingWithoutAFormulaStillMoves() throws {
        let view = try view(matrix: "{}")
        view.update(sessions: [try session(.working), try session(.working)])
        pump(view)
        XCTAssertGreaterThan(view.levels.max() ?? 0, 0.2)
    }

    /// A needsInput formula seizes the bars at full height during the strobe
    /// window.
    func testAlarmStrobeFormulaSeizesTheBars() throws {
        let view = try view(matrix: #"{ "shape": { "needsInput": "1" }, "feel": { "jitter": "none" } }"#)
        view.update(sessions: [try session(.needsInput, needs: true)])
        pump(view)
        XCTAssertGreaterThan(view.levels.min() ?? 0, 0.8)
    }
}
