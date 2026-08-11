// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

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

    /// The state as it should read *now*, which is not always the state that
    /// was written.
    ///
    /// Nothing ever emits `idle`: hooks fire on activity, and silence has no
    /// event. So a finished session would sit on `done` for the full 24h purge
    /// window, and a session that died mid-turn would claim to be `working`
    /// forever. Both are lies after a while, and the second is the worse one —
    /// a spinning face implies something is running.
    ///
    /// Age settles it. An alarm never decays, though: a session blocked on you
    /// stays blocked until you deal with it.
    var state: SessionState {
        // A non-actionable needsInput came from an `idle_prompt` line written
        // before those were filtered out; Claude had finished.
        let written = latest.state == .needsInput && !latest.isActionable ? .done : latest.state

        if written != .needsInput, ElapsedFormatter.isStale(since: latest.timestamp) {
            return .idle
        }
        return written
    }

    var tty: String? { latest.tty }
    var source: String { latest.source }
    var cwd: String? { latest.cwd }
    var lastActivity: Date { latest.timestamp }

    /// True when this row wants attention. A collapsed group inherits the dot
    /// from any needy child.
    var needsAction: Bool {
        let own = latest.isActionable && !isAcknowledged
        return own || children.contains { $0.needsAction }
    }

    /// You have seen this alarm, but the session is still blocked. Worth
    /// showing differently from both an unattended alarm and a quiet row.
    var isAcknowledged: Bool {
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
