// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The panel's single source of rows, merging every producer.
///
/// Three full producers: `SessionStore` (hook-driven `.jsonl` files, the bulk
/// of it), `GrokBotWatcher` (Grok Bot's local cache), and `CodexWatcher`
/// (OpenAI Codex's own local session files — no hook, same shape as Grok Bot).
/// Each stays honest to its own model and knows nothing about the others;
/// this concatenates their output and applies the one existing sort.
///
/// `SessionStore` keeps its file ⇔ row invariant intact — neither Grok Bot
/// nor Codex rows ever enter it. See docs/GROK-BOT-GROUPING.md,
/// docs/CODEX-INTEGRATION.md.
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
    private let codex: CodexWatcher
    private let preferences: Preferences

    private(set) var sessions: [Session] = []
    var onChange: (([Session]) -> Void)?

    init(
        store: SessionStore = SessionStore(),
        grok: GrokBotWatcher = GrokBotWatcher(),
        codex: CodexWatcher = CodexWatcher(),
        preferences: Preferences = .shared
    ) {
        self.store = store
        self.grok = grok
        self.codex = codex
        self.preferences = preferences
    }

    func start() {
        store.onChange = { [weak self] _ in self?.recombine() }
        store.start()
        if preferences.showsGrokBot {
            grok.onChange = { [weak self] _ in self?.recombine() }
            grok.start()
        }
        if preferences.showsCodex {
            codex.onChange = { [weak self] _ in self?.recombine() }
            codex.start()
        }
        recombine()
    }

    /// Forwarded to the store — Grok and Codex ids never match anything
    /// there, which is harmless. Neither can be acknowledged or removed from
    /// here: a Grok "needs you" clears by answering the card in Grok Bot
    /// (docs/GROK-BOT-GROUPING.md), and a Codex row has no alarm to clear at
    /// all (docs/CODEX-INTEGRATION.md).
    func acknowledge(sessionID: String) { store.acknowledge(sessionID: sessionID) }
    func remove(sessionID: String) { store.remove(sessionID: sessionID) }
    func reload() {
        store.reload()
        grok.reload()
        codex.reload()
    }

    private func recombine() {
        let base = store.sessions + grok.sessions + codex.sessions
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
