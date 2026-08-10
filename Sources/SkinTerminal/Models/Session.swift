import Foundation

/// A live session: the latest event from its file, plus any subagent children.
///
/// The renderer always draws "parent + children"; v1 simply ships with the
/// array empty (docs/SPEC.md §4), so enabling nested rows is data, not a
/// rewrite.
struct Session: Identifiable, Equatable {
    let id: String
    let latest: SessionEvent
    let children: [AgentRow]
    /// Suppresses the dot after the user has clicked the row, until something
    /// newer arrives.
    let acknowledgedAt: Date?

    /// Display name: user rename wins, then `session_title`, then the folder.
    /// See docs/SPEC.md §8.
    func displayName(renames: [String: String]) -> String {
        if let nickname = renames[id], !nickname.isEmpty { return nickname }
        if let name = latest.name, !name.isEmpty { return name }
        if let cwd = latest.cwd, !cwd.isEmpty {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return String(id.prefix(8))
    }

    var message: String { latest.message }
    var state: SessionState { latest.state }
    var tty: String? { latest.tty }
    var cwd: String? { latest.cwd }
    var lastActivity: Date { latest.timestamp }

    /// True when this row wants attention. A collapsed group inherits the dot
    /// from any needy child.
    var needsAction: Bool {
        let own = latest.needsAction && !isAcknowledged
        return own || children.contains { $0.needsAction }
    }

    private var isAcknowledged: Bool {
        guard let acknowledgedAt else { return false }
        return latest.timestamp <= acknowledgedAt
    }

    /// Whether to draw a disclosure triangle.
    var isGroup: Bool { !children.isEmpty }
}

/// One subagent child row.
struct AgentRow: Identifiable, Equatable {
    let id: String
    let latest: AgentEvent

    var message: String { latest.message }
    var state: SessionState { latest.state }
    var needsAction: Bool { latest.needsAction }

    /// `agent_type` is empty for Claude Code's internal agents, so it cannot
    /// yet be used as a label or a filter — see docs/SPEC.md §10.
    var displayName: String {
        latest.agentType.isEmpty ? "agent \(id.prefix(6))" : latest.agentType
    }
}
