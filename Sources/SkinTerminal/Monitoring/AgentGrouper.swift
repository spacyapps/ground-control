import Foundation

/// Turns `agents/*.jsonl` into children, keyed by the session they belong to.
///
/// Filenames are `<session_id>__<agent_id>.jsonl`, so the mapping is a split on
/// the separator — no need to open a file to know its parent.
enum AgentGrouper {
    static let separator = "__"

    static func childrenBySession(in directory: URL) -> [String: [AgentRow]] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var grouped: [String: [AgentRow]] = [:]
        for file in files where file.pathExtension == "jsonl" {
            guard let event = SessionFileParser.latestAgentEvent(at: file) else { continue }
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
