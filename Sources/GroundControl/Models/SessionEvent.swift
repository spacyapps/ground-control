// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

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
    /// Which CLI produced this row — "claude", "grok", … Session ids are only
    /// unique per tool, so this is what keeps two CLIs apart.
    let source: String
    let name: String?
    let cwd: String?
    let tty: String?
    /// The application hosting the terminal, as a path to its `.app`.
    ///
    /// A tty only identifies a tab inside iTerm or Terminal. Everything else
    /// that hosts a shell owns a pty nothing can match, so without this a click
    /// had nowhere to go but Finder. Resolved by `cc-notify`, which is the only
    /// place the process tree is visible.
    let hostApp: String?
    /// The same app's bundle id, inherited from `__CFBundleIdentifier`. A
    /// second opinion for when the process walk finds nothing.
    let hostID: String?
    let event: String?
    let state: SessionState
    let message: String
    let needsAction: Bool
    let notificationType: String?
    let transcriptPath: String?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case source
        case name
        case cwd
        case tty
        case hostApp = "host_app"
        case hostID = "host_id"
        case event
        case state
        case message
        case needsAction = "needs_action"
        case notificationType = "notification_type"
        case transcriptPath = "transcript_path"
        case timestamp = "ts"
    }

    /// Whether this event should actually raise the alarm.
    ///
    /// `idle_prompt` means Claude finished and is waiting for your next
    /// message, not that it is blocked on a decision. Older files on disk may
    /// still carry one as their last line — they live for 24h — so the rule is
    /// enforced here as well as in `cc-notify`.
    var isActionable: Bool {
        needsAction && notificationType != "idle_prompt"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "claude"
        name = try container.decodeIfPresent(String.self, forKey: .name)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        hostApp = try container.decodeIfPresent(String.self, forKey: .hostApp)
        hostID = try container.decodeIfPresent(String.self, forKey: .hostID)
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
