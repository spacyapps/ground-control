import Foundation

/// Source of truth for what the panel shows.
///
/// The one invariant: **file ⇔ row**. The store mirrors the folder and never
/// decides to drop a row on its own (docs/SPEC.md §2). Every rescan rebuilds
/// the list from disk, so removal needs no special case — a vanished file is
/// simply absent next time.
final class SessionStore {
    private(set) var sessions: [Session] = []

    /// Called on the main queue whenever the list changes.
    var onChange: (([Session]) -> Void)?

    private let root: URL
    private let agentsRoot: URL
    private let preferences: Preferences
    private var sessionWatcher: FolderWatcher?
    private var agentWatcher: FolderWatcher?
    private var pollTimer: Timer?

    /// Set when the user clicks a row; the dot stays off until a newer event.
    private var acknowledged: [String: Date] = [:]

    init(root: URL = Paths.sessionsRoot,
         agentsRoot: URL = Paths.agentsRoot,
         preferences: Preferences = .shared) {
        self.root = root
        self.agentsRoot = agentsRoot
        self.preferences = preferences
    }

    deinit {
        pollTimer?.invalidate()
    }

    func start() {
        Paths.ensureFoldersExist()

        sessionWatcher = FolderWatcher(url: root) { [weak self] in self?.reload() }
        agentWatcher = FolderWatcher(url: agentsRoot) { [weak self] in self?.reload() }
        sessionWatcher?.start()
        agentWatcher?.start()

        // Backstop for in-place appends the directory source may not report.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    /// Clears the dot for a row until something newer arrives.
    func acknowledge(sessionID: String) {
        acknowledged[sessionID] = Date()
        reload()
    }

    func reload() {
        let children = AgentGrouper.childrenBySession(
            in: agentsRoot,
            includingInternal: preferences.showsInternalAgents
        )
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var built: [Session] = []
        for file in files where file.pathExtension == "jsonl" {
            guard let event = SessionFileParser.latestEvent(at: file) else { continue }
            built.append(Session(
                id: event.sessionID,
                latest: event,
                children: children[event.sessionID] ?? [],
                acknowledgedAt: acknowledged[event.sessionID]
            ))
        }

        // Forget acknowledgements for sessions that no longer exist.
        let live = Set(built.map(\.id))
        acknowledged = acknowledged.filter { live.contains($0.key) }

        let sorted = Self.sorted(built)
        guard sorted != sessions else { return }
        sessions = sorted
        onChange?(sorted)
    }

    /// Needs-action pinned top, then most recently active (docs/SPEC.md §5).
    static func sorted(_ sessions: [Session]) -> [Session] {
        sessions.sorted { lhs, rhs in
            if lhs.needsAction != rhs.needsAction { return lhs.needsAction }
            if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
            return lhs.id < rhs.id
        }
    }
}
