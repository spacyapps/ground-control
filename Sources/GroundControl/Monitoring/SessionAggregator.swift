// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The panel's single source of rows, merging every producer.
///
/// Today there are two: `SessionStore` (hook-driven `.jsonl` files, the bulk of
/// it) and `GrokBotWatcher` (Grok Bot's local cache). Each stays honest to its
/// own model and knows nothing about the other; this concatenates their output
/// and applies the one existing sort. A future third source plugs in here.
///
/// `SessionStore` keeps its file ⇔ row invariant intact — Grok rows never enter
/// it. See docs/GROK-BOT-GROUPING.md.
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
        let merged = SessionStore.sorted(store.sessions + grok.sessions)
        guard merged != sessions else { return }
        sessions = merged
        onChange?(merged)
    }
}
