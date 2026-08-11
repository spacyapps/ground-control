// SPDX-License-Identifier: GPL-3.0-or-later
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
    let state: SessionState
    let message: String
    let needsAction: Bool
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agentID = "agent_id"
        case agentType = "agent_type"
        case state
        case message
        case needsAction = "needs_action"
        case timestamp = "ts"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        agentID = try container.decode(String.self, forKey: .agentID)
        agentType = try container.decodeIfPresent(String.self, forKey: .agentType) ?? ""
        state = try container.decodeIfPresent(SessionState.self, forKey: .state) ?? .done
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        needsAction = try container.decodeIfPresent(Bool.self, forKey: .needsAction) ?? false
        let seconds = try container.decodeIfPresent(Double.self, forKey: .timestamp) ?? 0
        timestamp = Date(timeIntervalSince1970: seconds)
    }
}
