// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The panel's single source of rows, merging every producer.
///
/// Two full producers: `SessionStore` (hook-driven `.jsonl` files, the bulk of
/// it) and `GrokBotWatcher` (Grok Bot's local cache). Each stays honest to its
/// own model and knows nothing about the other; this concatenates their output
/// and applies the one existing sort.
///
/// `SessionStore` keeps its file ⇔ row invariant intact — Grok rows never enter
/// it. See docs/GROK-BOT-GROUPING.md.
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

    /// Forwarded to the store — Grok ids never match anything there, which is
    /// harmless. A Grok "needs you" is cleared by answering the card in Grok
    /// Bot, not by clicking here (docs/GROK-BOT-GROUPING.md).
    func acknowledge(sessionID: String) { store.acknowledge(sessionID: sessionID) }
    func remove(sessionID: String) { store.remove(sessionID: sessionID) }
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

        let merged = SessionStore.sorted(folded)
        guard merged != sessions else { return }
        sessions = merged
        onChange?(merged)
    }
}
