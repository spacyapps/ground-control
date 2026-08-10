import Foundation

/// One decoded line from `<session_id>.jsonl`.
///
/// The last line of a file is that session's current state. Field names match
/// what `Scripts/cc-notify` writes — see docs/SPEC.md §3. Every field beyond
/// `session_id` is optional so a partially-written or older line still decodes.
/// Decodable only: `ts` is epoch seconds, and a synthesised encoder would not
/// round-trip it. The app reads these files, it never writes them.
struct SessionEvent: Decodable, Equatable {
    let sessionID: String
    let name: String?
    let cwd: String?
    let tty: String?
    let event: String?
    let state: SessionState
    let message: String
    let needsAction: Bool
    let notificationType: String?
    let transcriptPath: String?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case name
        case cwd
        case tty
        case event
        case state
        case message
        case needsAction = "needs_action"
        case notificationType = "notification_type"
        case transcriptPath = "transcript_path"
        case timestamp = "ts"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        event = try container.decodeIfPresent(String.self, forKey: .event)
        state = try container.decodeIfPresent(SessionState.self, forKey: .state) ?? .idle
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        needsAction = try container.decodeIfPresent(Bool.self, forKey: .needsAction) ?? false
        notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        let seconds = try container.decodeIfPresent(Double.self, forKey: .timestamp) ?? 0
        timestamp = Date(timeIntervalSince1970: seconds)
    }
}
