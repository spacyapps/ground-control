// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The panel's single source of rows, merging every producer.
///
/// Two producers: `SessionStore` (hook-driven `.jsonl` files, nearly all of
/// it) and `GrokBotWatcher` (Grok Bot's local cache). Each stays honest to its
/// own model and knows nothing about the other; this concatenates their output
/// and applies the one existing sort.
///
/// There was briefly a third. `CodexWatcher` read Codex's own session files
/// because Codex was believed unhookable; once its hooks were measured
/// (2026-09-11) it became a second producer for sessions the store already
/// had, and the two disagreed visibly — the watcher named a row from the
/// thread index, the hook path from the folder, and both re-sorted as they
/// updated. Deleted rather than deduplicated: a watcher is the answer for a
/// CLI that cannot be hooked, which is Grok Bot, and not for one that can.
/// See docs/CODEX-INTEGRATION.md.
///
/// `SessionStore` keeps its file ⇔ row invariant intact — Grok Bot rows never
/// enter it. See docs/GROK-BOT-GROUPING.md.
///
/// A third thing happens here too, not a new producer but a fold on top of
/// `SessionStore`'s own output: `GrokSubagentReader` finds any live Grok
/// session that is actually a `spawn_subagent` child (its id shows up under
/// another live session's own `subagents/` folder) and nests it under its
/// parent instead of leaving it as its own flat row. This still respects
/// `SessionStore`'s invariant — the store's own list is never touched, only
/// the aggregator's merged copy — the same way Grok Bot rows are added
/// alongside it rather than inside it.
final class SessionAggregator {
    let store: SessionStore
    private let grok: GrokBotWatcher
    private let preferences: Preferences

    private(set) var sessions: [Session] = []
    var onChange: (([Session]) -> Void)?

    init(
        store: SessionStore = SessionStore(),
        grok: GrokBotWatcher = GrokBotWatcher(),
        preferences: Preferences = .shared
    ) {
        self.store = store
        self.grok = grok
        self.preferences = preferences
    }

    func start() {
        store.onChange = { [weak self] _ in self?.recombine() }
        store.start()
        if preferences.showsGrokBot {
            grok.onChange = { [weak self] _ in self?.recombine() }
            grok.start()
        }
        recombine()
    }

    /// Forwarded to the store — Grok Bot ids never match anything there, which
    /// is harmless. A Grok "needs you" clears by answering the card in Grok Bot
    /// (docs/GROK-BOT-GROUPING.md), not by acknowledging here.
    func acknowledge(sessionID: String) { store.acknowledge(sessionID: sessionID) }

    /// A hook session has a real file — `SessionStore` deletes it, and the
    /// row is gone until a new event writes it again. Grok Bot's group has no
    /// file to delete; removing it instead dismisses it in `Preferences`,
    /// keyed to its `lastActivity` at the moment of removal, so it reappears
    /// the moment something genuinely new happens — the same rule a deleted
    /// hook session already gets for free.
    func remove(sessionID: String) {
        if store.sessions.contains(where: { $0.id == sessionID }) {
            store.remove(sessionID: sessionID)
            return
        }
        guard let session = grok.sessions.first(where: { $0.id == sessionID }) else { return }
        preferences.dismiss(sessionID: sessionID, lastActivity: session.lastActivity)
        recombine()
    }

    func reload() {
        store.reload()
        grok.reload()
    }

    private func recombine() {
        let base = store.sessions + grok.sessions
        var grokChildren: [String: [AgentRow]] = [:]
        if preferences.showsGrokSubagentGrouping {
            grokChildren = GrokSubagentReader.childrenBySession(liveSessions: store.sessions)
        }
        // Every child id across every parent, so its own flat row is never
        // shown alongside the nested one.
        let childIDs = Set(grokChildren.values.flatMap { $0.map(\.id) })

        let folded = base.compactMap { session -> Session? in
            if childIDs.contains(session.id) { return nil }
            guard let kids = grokChildren[session.id], !kids.isEmpty else { return session }
            return Session(
                id: session.id,
                latest: session.latest,
                children: session.children + kids,
                acknowledgedAt: session.acknowledgedAt
            )
        }

        let dismissed = preferences.dismissedSessions
        let visible = folded.filter { session in
            guard let dismissedAt = dismissed[session.id] else { return true }
            return session.lastActivity.timeIntervalSince1970 > dismissedAt
        }

        let merged = SessionStore.sorted(visible)
        guard merged != sessions else { return }
        sessions = merged
        onChange?(merged)
    }
}
