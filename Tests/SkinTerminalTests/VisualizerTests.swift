import XCTest
@testable import SkinTerminal

/// The analyser is decoration, but its energy is derived from real state — so
/// the mapping is worth pinning down.
final class VisualizerTests: XCTestCase {
    private func session(state: SessionState, needsAction: Bool = false) throws -> Session {
        let json = """
        {"session_id":"\(UUID().uuidString)","name":"x","cwd":"/tmp/x",\
        "state":"\(state.rawValue)","message":"","needs_action":\(needsAction),"ts":1}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        return Session(id: event.sessionID, latest: event, children: [], acknowledgedAt: nil)
    }

    func testEmptyPanelIsSilent() {
        XCTAssertEqual(VisualizerView.energy(for: []), 0)
    }

    func testIdleSessionsBarelyMove() throws {
        let energy = VisualizerView.energy(for: [try session(state: .idle)])
        XCTAssertGreaterThan(energy, 0)
        XCTAssertLessThan(energy, 0.2)
    }

    func testWorkingRaisesEnergy() throws {
        let one = VisualizerView.energy(for: [try session(state: .working)])
        let two = VisualizerView.energy(for: [
            try session(state: .working),
            try session(state: .working)
        ])
        XCTAssertGreaterThan(one, 0.4)
        XCTAssertGreaterThan(two, one, "busier panel, livelier bars")
    }

    func testNeedsActionPinsItToTheCeiling() throws {
        let sessions = [try session(state: .idle), try session(state: .needsInput, needsAction: true)]
        XCTAssertEqual(VisualizerView.energy(for: sessions), 1.0)
    }

    func testEnergyNeverExceedsOne() throws {
        let many = try (0..<20).map { _ in try session(state: .working) }
        XCTAssertLessThanOrEqual(VisualizerView.energy(for: many), 1.0)
    }
}
