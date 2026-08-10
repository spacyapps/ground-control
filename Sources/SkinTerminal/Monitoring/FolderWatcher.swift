import Foundation

/// Fires when a watched directory's contents change.
///
/// A `DispatchSource` on a directory descriptor reports adds, removes and
/// renames. Writes *inside* an existing file do not always surface, so the
/// store also polls on a slow timer — the watcher makes it feel instant, the
/// timer makes it correct.
///
/// Rapid hook writes are coalesced: several events inside `debounce` produce
/// one callback.
final class FolderWatcher {
    private let url: URL
    private let debounce: TimeInterval
    private let onChange: () -> Void

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "app.skinterminal.folderwatcher")

    init(url: URL, debounce: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.monitoring.error("Cannot watch \(self.url.path, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleCallback() }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        source.resume()
        self.source = source
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    private func scheduleCallback() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async(execute: self.onChange)
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
