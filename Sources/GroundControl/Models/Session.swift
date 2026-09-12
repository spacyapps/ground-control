// SPDX-License-Identifier: AGPL-3.0-or-later
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

    /// Where this session is running, short enough for a row: "Terminal",
    /// "Claude", "iTerm", "VS Code".
    ///
    /// Two sessions in the same folder are the same row otherwise, which is
    /// exactly what Claude for Desktop produces — it groups its sessions by
    /// folder, so three conversations under `~/xcode` all arrive named
    /// "xcode". The host is the one thing that tells a desktop session from a
    /// terminal one, and it is already in every event.
    var hostName: String? {
        guard let path = hostApp, !path.isEmpty else { return nil }
        let bundle = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return Session.shortHostNames[bundle] ?? bundle
    }

    /// Bundle names long enough to crowd out the thing they are labelling.
    private static let shortHostNames = [
        "Visual Studio Code": "VS Code",
        "Claude": "Claude",
        "Electron": "VS Code"
    ]

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
    var hostApp: String? { latest.hostApp }
    var hostID: String? { latest.hostID }
    var source: String { latest.source }
    var cwd: String? { latest.cwd }
    var lastActivity: Date { latest.timestamp }

    /// True when this row wants attention. A collapsed group inherits the dot
    /// from any needy child.
    var needsAction: Bool {
        let own = latest.isActionable && !isAcknowledged
        return own || children.contains { $0.needsAction }
    }

    /// An alarm you have seen but which is still outstanding — the only case
    /// worth showing as "handled". Acknowledging a quiet row means nothing:
    /// jumping to a terminal is not dismissing anything.
    var isDismissedAlarm: Bool {
        latest.isActionable && isAcknowledged
    }

    var isAcknowledged: Bool {
        guard let acknowledgedAt else { return false }
        return latest.timestamp <= acknowledgedAt
    }

    /// Whether to draw a disclosure triangle.
    var isGroup: Bool { !children.isEmpty }
}

/// One child row under a group parent.
///
/// Stores its fields directly rather than wrapping an event: a subagent has an
/// `AgentEvent` behind it, but a Grok Bot child has only a line in an
/// undocumented JSON cache (docs/GROK-BOT-GROUPING.md). Both build the same row.
struct AgentRow: Identifiable, Equatable {
    let id: String
    let displayName: String
    let message: String
    let state: SessionState
    let needsAction: Bool
    /// Drives the status dot's mark — `"grokbot"` splits it, the rest stay
    /// round. See `StatusDotView.Mark`.
    let source: String
    /// Newest-first ordering within a group.
    let lastActivity: Date

    init(
        id: String,
        displayName: String,
        message: String,
        state: SessionState,
        needsAction: Bool,
        source: String,
        lastActivity: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.message = message
        self.state = state
        self.needsAction = needsAction
        self.source = source
        self.lastActivity = lastActivity
    }

    /// From a subagent's event.
    ///
    /// A real name wins where there is one — only Codex gives them, and there
    /// `agent_type` is the constant `"default"`, which would label every child
    /// of every parent identically. Failing that, `agent_type` is the label
    /// Claude's named subagents carry; it is empty for Claude Code's internal
    /// agents (docs/SPEC.md §10), which is why the id is the last resort.
    init(id: String, latest: AgentEvent) {
        self.init(
            id: id,
            displayName: [latest.agentName, latest.agentType]
                .first(where: { !$0.isEmpty }) ?? "agent \(id.prefix(6))",
            message: latest.message,
            state: latest.state,
            needsAction: latest.needsAction,
            source: "claude",
            lastActivity: latest.timestamp
        )
    }
}
