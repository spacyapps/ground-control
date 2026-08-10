import Foundation

/// Deletes session files untouched for longer than the window.
///
/// This is the *only* removal rule (docs/SPEC.md §2): mtime is the entire
/// session lifecycle. There is no "session ended" event. Deleting a file flows
/// through the same "file gone → row gone" path as anything else, and a
/// re-interacted session simply recreates its file.
final class PurgeService {
    private let window: TimeInterval
    private let roots: [URL]
    private var timer: Timer?

    init(window: TimeInterval = 24 * 60 * 60,
         roots: [URL] = [Paths.sessionsRoot, Paths.agentsRoot]) {
        self.window = window
        self.roots = roots
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        purge()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.purge()
        }
    }

    @discardableResult
    func purge(now: Date = Date()) -> Int {
        var removed = 0
        for root in roots {
            removed += purge(root: root, now: now)
        }
        if removed > 0 {
            Log.monitoring.info("Purged \(removed, privacy: .public) stale session file(s)")
        }
        return removed
    }

    private func purge(root: URL, now: Date) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var removed = 0
        for file in files where file.pathExtension == "jsonl" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, now.timeIntervalSince(modified) > window else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }
}
