// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// UserDefaults wrapper — everything the app remembers between launches.
///
/// Session content never lives here; that is the temp folder's job. See
/// docs/SPEC.md §8.
final class Preferences {
    static let shared = Preferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let panelFrame = "panelFrame"
        static let alwaysOnTop = "alwaysOnTop"
        static let showOnAllSpaces = "showOnAllSpaces"
        static let themeName = "themeName"
        static let renames = "renames"
        static let showsInternalAgents = "showsInternalAgents"
        static let showsGrokBot = "showsGrokBot"
        static let showsGrokSubagentGrouping = "showsGrokSubagentGrouping"
        static let showsCodex = "showsCodex"
        static let dismissedSessions = "dismissedSessions"
        static let showsAnalyser = "showsAnalyser"
        static let analyserTint = "analyserTint"
    }

    /// The analyser's colour, as `#rrggbb`, or nil to use whatever the theme
    /// asked for. Stored as text because a colour is not a defaults value and
    /// archiving one would tie the file to an AppKit class.
    var analyserTint: String? {
        get { defaults.string(forKey: Key.analyserTint) }
        set { defaults.set(newValue, forKey: Key.analyserTint) }
    }

    /// The bars across the title strip. On by default — it is the first thing
    /// anyone notices — but it is decoration that never stops moving, and some
    /// people want a monitor that sits still.
    var showsAnalyser: Bool {
        get { defaults.object(forKey: Key.showsAnalyser) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showsAnalyser) }
    }

    /// Escape hatch for the internal-agent filter in `AgentGrouper`, which is a
    /// heuristic on an empty `agent_type`. No UI: `defaults write GroundControl
    /// showsInternalAgents -bool YES` if you want to see everything.
    var showsInternalAgents: Bool {
        get { defaults.bool(forKey: Key.showsInternalAgents) }
        set { defaults.set(newValue, forKey: Key.showsInternalAgents) }
    }

    /// The Grok Bot group (docs/GROK-BOT-GROUPING.md). On by default — it costs
    /// nothing when Grok Bot is not installed — but its status comes from an
    /// undocumented cache, so `defaults write GroundControl showsGrokBot -bool NO`
    /// turns it off.
    var showsGrokBot: Bool {
        get { defaults.object(forKey: Key.showsGrokBot) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showsGrokBot) }
    }

    /// Folds a Grok CLI session's `spawn_subagent` children under their
    /// parent, the same "N subagents" treatment Claude Code's real subagents
    /// already get (docs/HOOK-PAYLOADS.md, "Follow-up, same evening"). On by
    /// default — reading `subagents/<id>/meta.json` is cheap and only ever
    /// active for `source == "grok"` sessions — but the link comes from an
    /// undocumented, no-contract Grok-internal file, so `defaults write
    /// GroundControl showsGrokSubagentGrouping -bool NO` turns it off if that
    /// shape ever drifts.
    var showsGrokSubagentGrouping: Bool {
        get { defaults.object(forKey: Key.showsGrokSubagentGrouping) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showsGrokSubagentGrouping) }
    }

    /// OpenAI Codex rows (`docs/CODEX-INTEGRATION.md`). On by default — reading
    /// its own local session files costs nothing when Codex is not installed
    /// — but they are read-only history the same way Grok Bot's are, so a
    /// switch of its own: `defaults write GroundControl showsCodex -bool NO`.
    /// Codex rows never turn red; see the doc for why that is a real limit,
    /// not an oversight.
    var showsCodex: Bool {
        get { defaults.object(forKey: Key.showsCodex) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showsCodex) }
    }

    /// "Remove" for a row with no file to delete — Grok Bot's group, a Codex
    /// thread. Keyed by session id, storing the row's own `lastActivity` at
    /// the moment it was dismissed (epoch seconds): `SessionAggregator`
    /// hides it only while nothing newer has happened, the same "reappears
    /// on its next real event" rule `SessionStore.remove()` already gives a
    /// live hook session. Persisted, unlike `SessionStore`'s in-memory
    /// `acknowledged` — there is no file whose disappearance would otherwise
    /// mark this permanent, so it must survive a relaunch on its own.
    var dismissedSessions: [String: TimeInterval] {
        get { defaults.dictionary(forKey: Key.dismissedSessions) as? [String: TimeInterval] ?? [:] }
        set { defaults.set(newValue, forKey: Key.dismissedSessions) }
    }

    func dismiss(sessionID: String, lastActivity: Date) {
        var current = dismissedSessions
        current[sessionID] = lastActivity.timeIntervalSince1970
        dismissedSessions = current
    }

    var panelFrame: String? {
        get { defaults.string(forKey: Key.panelFrame) }
        set { defaults.set(newValue, forKey: Key.panelFrame) }
    }

    var alwaysOnTop: Bool {
        get { defaults.object(forKey: Key.alwaysOnTop) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.alwaysOnTop) }
    }

    var showOnAllSpaces: Bool {
        get { defaults.object(forKey: Key.showOnAllSpaces) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showOnAllSpaces) }
    }

    /// `nil` means the built-in default theme.
    var themeName: String? {
        get { defaults.string(forKey: Key.themeName) }
        set { defaults.set(newValue, forKey: Key.themeName) }
    }

    /// User overrides, keyed by session id. Takes priority over `session_title`
    /// and `basename(cwd)` — see docs/SPEC.md §8.
    var renames: [String: String] {
        get { defaults.dictionary(forKey: Key.renames) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.renames) }
    }

    func rename(sessionID: String, to nickname: String?) {
        var current = renames
        if let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty {
            current[sessionID] = nickname
        } else {
            current.removeValue(forKey: sessionID)
        }
        renames = current
    }
}
