// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Turns `agents/*.jsonl` into children, keyed by the session they belong to.
///
/// Filenames are `<session_id>__<agent_id>.jsonl`, so the mapping is a split on
/// the separator — no need to open a file to know its parent.
enum AgentGrouper {
    static let separator = "__"

    /// Claude Code fires `SubagentStop` for its own background agents, not only
    /// ones a session spawned. Their text is not part of the visible
    /// conversation — suggested prompts, summaries — so rendering them puts
    /// words on screen that look like the user's own. Every internal agent
    /// observed so far reports an empty `agent_type`, which is the only signal
    /// available to tell them apart (docs/SPEC.md §10).
    ///
    /// It is a heuristic: a real subagent reporting no type would be hidden
    /// too. `Preferences.showsInternalAgents` exists to flip it back without a
    /// rebuild, and the files are left on disk either way.
    static func isInternal(_ event: AgentEvent) -> Bool {
        event.agentType.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A finished subagent is interesting for a few minutes, then it is
    /// history. Sessions age into `idle` and stay; children have no equivalent
    /// resting state, so they simply stop being listed — otherwise a parent
    /// accumulates every helper it ever ran until the 24h purge.
    static let showFinishedFor: TimeInterval = 30 * 60

    static func childrenBySession(in directory: URL,
                                  includingInternal: Bool = false,
                                  now: Date = Date()) -> [String: [AgentRow]] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var grouped: [String: [AgentRow]] = [:]
        for file in files where file.pathExtension == "jsonl" {
            guard let event = SessionFileParser.latestAgentEvent(at: file) else { continue }
            guard includingInternal || !isInternal(event) else { continue }
            // Still running? Always show. Finished? Only while it is news.
            if event.state == .done,
               now.timeIntervalSince(event.timestamp) > showFinishedFor { continue }
            grouped[event.sessionID, default: []].append(
                AgentRow(id: event.agentID, latest: event)
            )
        }

        for key in grouped.keys {
            grouped[key]?.sort { $0.latest.timestamp > $1.latest.timestamp }
        }
        return grouped
    }
}
