// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// One decoded line from `agents/<session_id>__<agent_id>.jsonl`.
///
/// Subagents share the orchestrator's `session_id`, so `agent_id` is what
/// separates them — see docs/SPEC.md §4.
struct AgentEvent: Decodable, Equatable {
    let sessionID: String
    let agentID: String
    let agentType: String
    /// A name the CLI gave this child, when it gives one at all.
    ///
    /// Only Codex does. `agent_type` there is the constant `"default"`, so it
    /// separates nothing; the real names live in the child's own transcript
    /// and `cc-notify` lifts them out (`/root/hello_one` -> `hello_one`).
    /// Empty for every other CLI, which is why it is preferred rather than
    /// replacing `agentType`.
    let agentName: String
    let state: SessionState
    let message: String
    let needsAction: Bool
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agentID = "agent_id"
        case agentType = "agent_type"
        case agentName = "agent_name"
        case state
        case message
        case needsAction = "needs_action"
        case timestamp = "ts"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        agentID = try container.decode(String.self, forKey: .agentID)
        // Both ids reach a filename or a prefix match — same rule as SessionEvent.
        guard SessionEvent.isPlainID(sessionID), SessionEvent.isPlainID(agentID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .sessionID,
                in: container,
                debugDescription: "session/agent id is used as a filename; must be [A-Za-z0-9_-], 1–128 chars"
            )
        }
        agentType = try container.decodeIfPresent(String.self, forKey: .agentType) ?? ""
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName) ?? ""
        state = try container.decodeIfPresent(SessionState.self, forKey: .state) ?? .done
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        needsAction = try container.decodeIfPresent(Bool.self, forKey: .needsAction) ?? false
        let seconds = try container.decodeIfPresent(Double.self, forKey: .timestamp) ?? 0
        timestamp = Date(timeIntervalSince1970: seconds)
    }
}
