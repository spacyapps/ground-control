// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// One child recorded in a Grok CLI session's own `subagents/<child_id>/meta.json`.
///
/// `spawn_subagent` fires no hook at all — `SubagentStart`/`SubagentStop` were
/// believed to cover it, but a live test (2026-09-10) showed neither ever
/// fires; each subagent is its own fully independent top-level Grok session,
/// hook-visible and flat, with no parent link `cc-notify` ever sees
/// (docs/HOOK-PAYLOADS.md, "Follow-up, same evening"). The real link lives one
/// layer outside any hook, in a small file Grok already writes for itself:
/// `~/.grok/sessions/<url-encoded-cwd>/<parent_session_id>/subagents/
/// <child_session_id>/meta.json`. Unlike the parent's own transcript (500KB+
/// after one turn), this is a fixed, ~1KB file per child, and it survives
/// after the child's own hook-driven row self-deletes on completion — so a
/// finished subagent is still discoverable here even once its flat row is
/// long gone.
///
/// This is Grok-specific and read-only, same shape as `GrokBotRoster` reading
/// Grok Bot's own cache — hand-walked and tolerant, because the shape is not
/// a contract. Claude Code's own subagents already have a real hook
/// (`SubagentStop`, `AgentGrouper`); nothing here touches that path.
struct GrokSubagentMeta: Codable, Equatable {
    let subagentID: String
    let parentSessionID: String
    let childSessionID: String
    let subagentType: String?
    let description: String?
    /// Only ever observed as `"completed"` so far. Anything else is treated
    /// as still running — the safe direction, since a genuinely finished but
    /// unrecognised status just shows as busy a little longer, never flips a
    /// running subagent to looking done.
    let status: String
    private let startedAtRaw: String?
    private let completedAtRaw: String?

    enum CodingKeys: String, CodingKey {
        case subagentID = "subagent_id"
        case parentSessionID = "parent_session_id"
        case childSessionID = "child_session_id"
        case subagentType = "subagent_type"
        case description
        case status
        case startedAtRaw = "started_at"
        case completedAtRaw = "completed_at"
    }

    init(
        subagentID: String,
        parentSessionID: String,
        childSessionID: String,
        subagentType: String?,
        description: String?,
        status: String,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.subagentID = subagentID
        self.parentSessionID = parentSessionID
        self.childSessionID = childSessionID
        self.subagentType = subagentType
        self.description = description
        self.status = status
        self.startedAtRaw = startedAt.map(Self.isoFormatter.string(from:))
        self.completedAtRaw = completedAt.map(Self.isoFormatter.string(from:))
    }

    /// Grok writes ISO 8601 with fractional seconds
    /// (`2026-09-11T05:33:30.178233Z`) — the default `ISO8601DateFormatter`
    /// rejects the fraction, so it must be requested explicitly.
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var startedAt: Date? { startedAtRaw.flatMap(Self.isoFormatter.date(from:)) }
    var completedAt: Date? { completedAtRaw.flatMap(Self.isoFormatter.date(from:)) }

    var state: SessionState { status == "completed" ? .done : .working }
    var lastActivity: Date { completedAt ?? startedAt ?? .distantPast }

    /// The row to show for this child. While its own hook-driven row still
    /// exists, that row — not this file — is the source of live state and
    /// `needsAction`: `meta.json` carries no alarm signal at all, and this is
    /// the one CLI in this app that alarms independent of `permission_mode:
    /// auto`, so trusting this file alone while a child is still running
    /// would silently drop a real alarm. This file always supplies the
    /// label, though — a live row just reads "my-project" like any other
    /// session; only `description` says what the task actually is.
    func agentRow(overriding live: Session? = nil) -> AgentRow {
        let described = description.flatMap { $0.isEmpty ? nil : $0 }
        let label = described ?? subagentType ?? "subagent"
        if let live {
            return AgentRow(
                id: childSessionID,
                displayName: label,
                message: live.message,
                state: live.state,
                needsAction: live.needsAction,
                source: "grok",
                lastActivity: live.lastActivity
            )
        }
        return AgentRow(
            id: childSessionID,
            displayName: label,
            message: status == "completed" ? "Finished" : "Working…",
            state: state,
            needsAction: false,
            source: "grok",
            lastActivity: lastActivity
        )
    }
}

/// Reads every live Grok session's own `subagents/` folder and turns it into
/// `AgentRow` children, keyed by parent session id.
///
/// Deliberately scoped, not a recursive scan of `~/.grok/sessions/` — this
/// only ever looks inside folders for sessions GC already knows are live, so
/// there is no unbounded directory tree to watch, unlike tailing every
/// session's transcript would have needed.
enum GrokSubagentReader {
    /// Mirrors `AgentGrouper.showFinishedFor` — a completed subagent is only
    /// interesting for a while after its own row is gone; past that it is
    /// history, not a status. Only applies once the child's own live row has
    /// vanished — a still-running child is always shown regardless of age.
    static let showFinishedFor: TimeInterval = 30 * 60

    static func childrenBySession(
        liveSessions: [Session],
        now: Date = Date(),
        sessionsRoot: URL = GrokSubagentReader.defaultSessionsRoot
    ) -> [String: [AgentRow]] {
        let liveByID = Dictionary(uniqueKeysWithValues: liveSessions.map { ($0.id, $0) })
        var result: [String: [AgentRow]] = [:]

        for parent in liveSessions where parent.source == "grok" {
            guard let cwd = parent.cwd, !cwd.isEmpty else { continue }
            let dir = subagentsDir(sessionID: parent.id, cwd: cwd, sessionsRoot: sessionsRoot)
            let subfolders = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []

            let rows: [AgentRow] = subfolders.compactMap { folder -> AgentRow? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")),
                      let meta = try? JSONDecoder().decode(GrokSubagentMeta.self, from: data)
                else { return nil }

                if let live = liveByID[meta.childSessionID] {
                    return meta.agentRow(overriding: live)
                }
                guard now.timeIntervalSince(meta.lastActivity) <= showFinishedFor else { return nil }
                return meta.agentRow()
            }

            if !rows.isEmpty {
                result[parent.id] = rows.sorted { $0.lastActivity > $1.lastActivity }
            }
        }
        return result
    }

    static func subagentsDir(sessionID: String, cwd: String, sessionsRoot: URL) -> URL {
        sessionsRoot
            .appendingPathComponent(percentEncode(cwd), isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
    }

    static var defaultSessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    /// Grok escapes the cwd by percent-encoding everything outside the RFC
    /// 3986 unreserved set — on a normal macOS path that is just every `/`
    /// (`/Users/you/repo` → `%2FUsers%2Fyou%2Frepo`), but any character
    /// outside that set is handled the same way, not just the slash.
    static func percentEncode(_ cwd: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return cwd.addingPercentEncoding(withAllowedCharacters: allowed) ?? cwd
    }
}
