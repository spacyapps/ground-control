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
