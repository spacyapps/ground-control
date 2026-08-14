// SPDX-License-Identifier: GPL-3.0-or-later
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
