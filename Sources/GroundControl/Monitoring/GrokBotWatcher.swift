// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Turns Grok Bot's local sidebar cache into one collapsible panel group.
///
/// Grok Bot (xAI's desktop agent app, bundle `com.anysphere.sand`) runs its
/// agents in the cloud and fires **no local hooks** — the full investigation is
/// in docs/GROK-BOT-INTEGRATION.md. The one thing readable on this machine is a
/// folder of plaintext JSON blobs it writes for its own sidebar. This watches
/// the `…roster.last-roster` blob(s) and emits a synthetic parent `Session`
/// whose children are the bots.
///
/// It sits **beside** `SessionStore`, not inside it: that store holds a
/// file ⇔ row invariant and never invents a row. `SessionAggregator` merges the
/// two. See docs/GROK-BOT-GROUPING.md.
final class GrokBotWatcher {
    /// The synthetic parent's id. Real Grok bot ids are UUIDs, so this cannot
    /// collide.
    static let groupID = "grokbot"
    static let source = "grokbot"
    static let appPath = "/Applications/Grok Bot.app"
    static let bundleID = "com.anysphere.sand"

    private(set) var sessions: [Session] = []
    var onChange: (([Session]) -> Void)?

    private let directory: URL
    private let clock: () -> Date
    private var watcher: FolderWatcher?
    private var pollTimer: Timer?

    /// `~/Library/Application Support/Grok Bot/sand-client-persistence`.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base
            .appendingPathComponent("Grok Bot", isDirectory: true)
            .appendingPathComponent("sand-client-persistence", isDirectory: true)
    }

    init(directory: URL = GrokBotWatcher.defaultDirectory, clock: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.clock = clock
    }

    deinit { pollTimer?.invalidate() }

    func start() {
        reload()
        // Only watch once the folder exists — Grok Bot may not be installed,
        // in which case there is simply never a row.
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        watcher = FolderWatcher(url: directory, debounce: 0.4) { [weak self] in self?.reload() }
        watcher?.start()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        let next = Self.sessions(from: Self.readRosters(in: directory), at: clock())
        guard next != sessions else { return }
        sessions = next
        onChange?(next)
    }

    // MARK: - Reading

    /// Every `…roster.last-roster` blob in the folder, parsed. There is one per
    /// signed-in account; usually exactly one.
    static func readRosters(in directory: URL) -> [Result<GrokBotRoster, GrokBotRoster.ParseError>] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        return files
            .filter { $0.pathExtension == "blob" }
            .filter { Base32.decode($0.deletingPathExtension().lastPathComponent)?
                .hasSuffix("roster.last-roster") == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in (try? Data(contentsOf: url)).map(GrokBotRoster.parse) }
    }

    // MARK: - Mapping

    /// The pure part: rosters in, at most one `Session` out. Tested in
    /// isolation.
    static func sessions(
        from rosters: [Result<GrokBotRoster, GrokBotRoster.ParseError>],
        at now: Date
    ) -> [Session] {
        guard !rosters.isEmpty else { return [] }

        // Any blob that parsed but had the wrong shape means the format moved.
        // Say so out loud rather than showing a confidently wrong row.
        let shapeBroken = rosters.contains {
            if case .failure(.unexpectedShape) = $0 { return true }
            return false
        }
        if shapeBroken {
            return [degradedSession(at: now)]
        }

        let bots = rosters
            .compactMap { try? $0.get() }
            .flatMap(\.bots)
            .filter { !$0.isHidden && !$0.isChannel }
        guard !bots.isEmpty else { return [] }

        let children = bots
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { bot -> AgentRow in
                let needy = bot.sessionPreviewKind == GrokBotRoster.cardPendingKind || bot.awaitingUser
                // No message line: the red dot says "waiting", and the name
                // gets the whole row. Everything else about a bot's state is
                // unknowable from the cache anyway.
                return AgentRow(
                    id: bot.id,
                    displayName: bot.name,
                    message: "",
                    state: needy ? .needsInput : .idle,
                    needsAction: needy,
                    source: source,
                    lastActivity: bot.updatedAt
                )
            }

        // Any waiting bot puts the whole group in the needsInput mood — red
        // dot, alarm face, and it drives the title-bar alarm like any other
        // needy row (docs/GROK-BOT-GROUPING.md, decision 1).
        let anyWaiting = children.contains { $0.needsAction }
        let latest = bots.map(\.updatedAt).max() ?? now
        let parent = SessionEvent(
            sessionID: groupID,
            source: source,
            name: "Grok Bot",
            hostApp: appPath,
            hostID: bundleID,
            state: anyWaiting ? .needsInput : .idle,
            message: "",
            needsAction: anyWaiting,
            timestamp: latest
        )
        return [Session(id: groupID, latest: parent, children: children, acknowledgedAt: nil)]
    }

    private static func degradedSession(at now: Date) -> Session {
        let event = SessionEvent(
            sessionID: groupID,
            source: source,
            name: "Grok Bot",
            hostApp: appPath,
            hostID: bundleID,
            state: .idle,
            message: "can't read status — update Ground Control?",
            needsAction: false,
            timestamp: now
        )
        return Session(id: groupID, latest: event, children: [], acknowledgedAt: nil)
    }
}
