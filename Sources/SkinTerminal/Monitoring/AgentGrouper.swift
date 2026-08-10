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

    static func childrenBySession(in directory: URL,
                                  includingInternal: Bool = false) -> [String: [AgentRow]] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var grouped: [String: [AgentRow]] = [:]
        for file in files where file.pathExtension == "jsonl" {
            guard let event = SessionFileParser.latestAgentEvent(at: file) else { continue }
            guard includingInternal || !isInternal(event) else { continue }
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
