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

    /// Bots whose last roster write was the user speaking, not the bot.
    ///
    /// `lastEntry` tracks the bot's messages only (measured three times,
    /// docs/GROK-BOT-INTEGRATION.md), so a write that moves `updatedAt` while
    /// leaving `lastEntryText` alone is the user sending something. Until that
    /// text changes the bot owes an answer, which is the one moment "working"
    /// is certain rather than inferred from a clock.
    private var awaitingReply: Set<String> = []
    private var lastSeen: [String: GrokBotRoster.Bot] = [:]

    func reload() {
        let rosters = Self.readRosters(in: directory)
        trackWhoSpokeLast(in: rosters)
        let next = Self.sessions(from: rosters, at: clock(), awaitingReply: awaitingReply)
        guard next != sessions else { return }
        sessions = next
        onChange?(next)
    }

    private func trackWhoSpokeLast(in rosters: [Result<GrokBotRoster, GrokBotRoster.ParseError>]) {
        for bot in rosters.compactMap({ try? $0.get() }).flatMap(\.bots) {
            defer { lastSeen[bot.id] = bot }
            guard let was = lastSeen[bot.id] else { continue }
            if bot.lastEntryText != was.lastEntryText {
                awaitingReply.remove(bot.id)          // the bot spoke — it is answering
            } else if bot.updatedAt > was.updatedAt {
                awaitingReply.insert(bot.id)          // clock moved, bot silent — the user spoke
            }
        }
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
            .compactMap { url in
                BoundedRead.data(at: url, limit: BoundedRead.manifestLimit).map(GrokBotRoster.parse)
            }
    }

    // MARK: - Mapping

    /// The pure part: rosters in, at most one `Session` out. Tested in
    /// isolation.
    /// How long after a bot's own last word it still counts as working.
    ///
    /// Emits during a live turn came 2–30s apart when measured, so this covers
    /// an ordinary cadence with room. It is deliberately **not** stretched to
    /// cover the 3m49s mid-task silence that was also measured: a window long
    /// enough for that would keep a finished bot animating for four minutes,
    /// and the deferred case is caught by `awaitingReply` instead, which is a
    /// fact rather than a guess. Past the window a quiet row claims nothing.
    static let stillMovingWindow: TimeInterval = 75

    static func sessions(
        from rosters: [Result<GrokBotRoster, GrokBotRoster.ParseError>],
        at now: Date,
        awaitingReply: Set<String> = []
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
                let needy = bot.lastEntryKind == GrokBotRoster.cardPendingKind || bot.awaitingUser
                // Two ways to know a bot is working, and neither is a guess:
                // it owes the user a reply, or it emitted something just now.
                // Quiet still means done *or* deferred *or* tasked-but-silent,
                // so a quiet row goes back to idle and claims nothing.
                let working = awaitingReply.contains(bot.id)
                    || now.timeIntervalSince(bot.updatedAt) < stillMovingWindow
                // No message line: the dot and the avatar carry the state, and
                // the name gets the whole row.
                return AgentRow(
                    id: bot.id,
                    displayName: bot.name,
                    message: "",
                    state: needy ? .needsInput : (working ? .working : .idle),
                    needsAction: needy,
                    source: source,
                    lastActivity: bot.updatedAt
                )
            }

        // Any waiting bot puts the whole group in the needsInput mood — red
        // dot, alarm face, and it drives the title-bar alarm like any other
        // needy row (docs/GROK-BOT-GROUPING.md, decision 1).
        let anyWaiting = children.contains { $0.needsAction }
        // Collapsed, the group inherits its busiest child: red if one is
        // waiting on you, otherwise working while any bot is. A bot woken by
        // another bot lights up its own row with no message from the user at
        // all, so the group is how that shows when it is collapsed.
        let anyWorking = children.contains { $0.state == .working }
        let latest = bots.map(\.updatedAt).max() ?? now
        let parent = SessionEvent(
            sessionID: groupID,
            source: source,
            name: "Grok Bot",
            hostApp: appPath,
            hostID: bundleID,
            state: anyWaiting ? .needsInput : (anyWorking ? .working : .idle),
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
