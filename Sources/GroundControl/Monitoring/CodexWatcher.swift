// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// One entry from Codex's own `~/.codex/session_index.jsonl` — a roster of
/// every thread it has ever run, tiny (one line, a few fields) compared to the
/// per-thread transcript it points at.
struct CodexIndexEntry: Decodable, Equatable {
    let id: String
    let threadName: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }
}

/// Reads Codex's own local files and turns them into `Session`s — a full
/// producer beside `SessionStore` and `GrokBotWatcher`, not a hook adapter.
///
/// **Why files, not hooks.** Codex's `hooks` feature is `stable` and on by
/// default, but the config syntax to actually register one was never found
/// (not in its public docs as of 2026-09-10) and nothing here relies on
/// guessing it — see `docs/HOOK-PAYLOADS.md`, "OpenAI Codex". Its own local
/// storage already carries everything a row needs: `session_index.jsonl` (an
/// id, a real thread name, a last-updated time — the roster) and one
/// `sessions/<yyyy>/<mm>/<dd>/rollout-<ts>-<id>.jsonl` per thread (the full
/// transcript; `session_meta`, always the first line, carries `cwd`).
///
/// **What this cannot show, and why.** Codex's real "needs you" moment — a
/// command needing escalated permission — writes **nothing** to the rollout
/// file while it waits. Confirmed live: the file's size and mtime sat frozen
/// the entire time a real approval prompt was on screen, and grepping the
/// whole transcript for every event type it had ever written turned up no
/// `approval`/`permission_request` of any kind. A file watcher genuinely
/// cannot see this — the signal only exists live, over Codex's app-server
/// socket, a materially different (and bigger) integration than this one.
/// So a Codex row here can show **working** and **done**, never **red** —
/// the same honest limit already shipped for Cursor's own Composer.
final class CodexWatcher {
    static let source = "codex"

    /// A thread updated longer ago than this is history, not a live row —
    /// matches `AgentGrouper.showFinishedFor`'s spirit, generous because
    /// Codex threads (unlike a hook session) carry no purge of their own.
    static let relevanceWindow: TimeInterval = 24 * 60 * 60

    private(set) var sessions: [Session] = []
    var onChange: (([Session]) -> Void)?

    private let root: URL
    private let clock: () -> Date
    private var pollTimer: Timer?

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    init(root: URL = CodexWatcher.defaultRoot, clock: @escaping () -> Date = Date.init) {
        self.root = root
        self.clock = clock
    }

    deinit { pollTimer?.invalidate() }

    func start() {
        reload()
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        // No FolderWatcher: session_index.jsonl is rewritten on every turn, but
        // the transcript that actually changes state lives in a nested,
        // per-thread file the index does not name a path to — a directory
        // watch on the index alone would miss every mid-turn update. Same
        // 3s poll GrokBotWatcher already uses for the same reason.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        let next = Self.sessions(
            fromIndexAt: root.appendingPathComponent("session_index.jsonl"),
            sessionsRoot: root.appendingPathComponent("sessions", isDirectory: true),
            now: clock()
        )
        guard next != sessions else { return }
        sessions = next
        onChange?(next)
    }

    // MARK: - Pure mapping, tested in isolation

    static func sessions(fromIndexAt indexURL: URL, sessionsRoot: URL, now: Date) -> [Session] {
        guard let text = BoundedRead.string(at: indexURL, limit: BoundedRead.sessionFileLimit) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds

        var built: [Session] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let entry = try? decoder.decode(CodexIndexEntry.self, from: data)
            else { continue }
            guard now.timeIntervalSince(entry.updatedAt) <= relevanceWindow else { continue }
            guard let transcript = findRollout(id: entry.id, under: sessionsRoot) else { continue }
            guard let session = session(for: entry, transcript: transcript) else { continue }
            built.append(session)
        }
        return built
    }

    /// A thread's own id is a suffix of its rollout filename
    /// (`rollout-<timestamp>-<id>.jsonl`), but the index gives no folder — so
    /// this walks `sessions/` looking for it. Bounded by real usage, not by
    /// anything enforced here: revisit if a very long Codex history ever
    /// makes this walk show up in a profile.
    private static func findRollout(id: String, under sessionsRoot: URL) -> URL? {
        guard let walker = FileManager.default.enumerator(
            at: sessionsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in walker {
            if url.pathExtension == "jsonl", url.deletingPathExtension().lastPathComponent.hasSuffix("-\(id)") {
                return url
            }
        }
        return nil
    }

    /// `cwd` comes from the transcript's first line (`session_meta`); current
    /// state from its last decodable `event_msg` — `task_complete` means
    /// done, anything else means working. Whole-file, same technique
    /// `SessionFileParser` already uses for GC's own `.jsonl` files.
    private static func session(for entry: CodexIndexEntry, transcript: URL) -> Session? {
        guard let text = BoundedRead.string(at: transcript, limit: BoundedRead.sessionFileLimit) else { return nil }
        let lines = text.split(separator: "\n")
        guard let first = lines.first else { return nil }
        guard let meta = decodeSessionMeta(String(first)) else { return nil }

        var state: SessionState = .working
        var message = "Working…"
        for line in lines.reversed() {
            guard let completed = decodeTaskComplete(String(line)) else { continue }
            state = .done
            message = completed.lastAgentMessage ?? "Finished"
            break
        }

        let event = SessionEvent(
            sessionID: entry.id,
            source: source,
            name: entry.threadName,
            cwd: meta.cwd,
            state: state,
            message: message,
            timestamp: entry.updatedAt
        )
        return Session(id: entry.id, latest: event, children: [], acknowledgedAt: nil)
    }

    private struct SessionMeta: Decodable {
        let type: String
        let payload: Payload
        struct Payload: Decodable { let cwd: String? }
    }

    private static func decodeSessionMeta(_ line: String) -> SessionMeta.Payload? {
        guard let data = line.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SessionMeta.self, from: data),
              decoded.type == "session_meta"
        else { return nil }
        return decoded.payload
    }

    private struct TaskComplete: Decodable {
        let payload: Payload
        struct Payload: Decodable {
            let type: String
            let lastAgentMessage: String?
            enum CodingKeys: String, CodingKey { case type; case lastAgentMessage = "last_agent_message" }
        }
    }

    private static func decodeTaskComplete(_ line: String) -> TaskComplete.Payload? {
        guard let data = line.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TaskComplete.self, from: data),
              decoded.payload.type == "task_complete"
        else { return nil }
        return decoded.payload
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    /// Codex writes `2026-09-11T21:32:15.535563Z` — fractional seconds, which
    /// `.iso8601` alone rejects.
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "not ISO 8601: \(raw)"
            )
        }
    }
}
