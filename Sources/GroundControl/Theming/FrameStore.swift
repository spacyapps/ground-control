// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import Compression

/// An animation's frames parked on disk: decoded once, read back one at a time.
///
/// Two ways of holding a long APNG both cost too much. Keeping every frame as a
/// bitmap is hundreds of MB. Keeping the file and asking ImageIO for frame N
/// makes it decode every frame before N again, on every redraw — measured at
/// 40-60 ms a frame late in a 361-frame loop. So each frame is decoded once,
/// in order (cheap: ~0.6 ms), and stored LZ4-compressed, one file per frame.
/// Reading one back is ~0.1 ms and holds a single frame in memory.
///
/// Folders belong to one process: no index is kept, nothing is reused after a
/// launch, and the store deletes its folder when it goes. Each process works in
/// `root/<pid>/`, so a second instance, or a test run, can never sweep the
/// frames a live app is reading. A crash leaves its folder behind; the next
/// process to build sweeps the folders whose process is gone.
final class FrameStore {
    /// Where every process's frames live. Caches, not Application Support — it
    /// is regenerable, and macOS may reclaim it. Tests point this at a temp folder.
    static var root: URL = Paths.frameCache

    /// This process's own folder under the root.
    static var home: URL { root.appendingPathComponent(String(getpid()), isDirectory: true) }

    let count: Int
    let width: Int
    let height: Int
    private let folder: URL
    private let colorSpace: CGColorSpace
    private var rawSize: Int { width * height * 4 }

    private static let lock = NSLock()
    private static var sweptRoot: URL?

    private init(folder: URL, count: Int, width: Int, height: Int, colorSpace: CGColorSpace) {
        self.folder = folder
        self.count = count
        self.width = width
        self.height = height
        self.colorSpace = colorSpace
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Deletes this process's frames. Called at quit; other processes' folders
    /// are theirs, and `build` sweeps the ones whose process has gone.
    static func removeAll() {
        try? FileManager.default.removeItem(at: home)
    }

    /// Stores every frame `frame(_:)` can produce, in order. Nil when any frame
    /// differs in size from the first or the disk refuses a write — the caller
    /// keeps the frames in memory instead.
    ///
    /// A frame the closure returns nil for is skipped, as the in-memory path
    /// always did, so the stored indices are consecutive.
    static func build(name: String, frameCount: Int, frame: (Int) -> CGImage?) -> FrameStore? {
        let base = preparedHome()
        let fileManager = FileManager.default
        let folder = base.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var writer: Writer?
        var stored = 0
        for index in 0..<frameCount {
            guard let image = frame(index) else { continue }
            if writer == nil { writer = Writer(first: image) }
            guard let writer, let bytes = writer.compressed(image) else {
                try? fileManager.removeItem(at: folder)
                return nil
            }
            do {
                try bytes.write(to: folder.appendingPathComponent("\(stored).lz4"))
            } catch {
                try? fileManager.removeItem(at: folder)
                return nil
            }
            stored += 1
        }
        guard let writer, stored > 0 else {
            try? fileManager.removeItem(at: folder)
            return nil
        }
        return FrameStore(
            folder: folder,
            count: stored,
            width: writer.width,
            height: writer.height,
            colorSpace: writer.colorSpace
        )
    }

    /// One frame, decoded. Nil when the index is out of range or the file has
    /// gone (a theme reload swept the folder under a late caller).
    func image(at index: Int) -> CGImage? {
        let file = folder.appendingPathComponent("\(index).lz4")
        guard index >= 0, index < count,
              let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        let raw = NSMutableData(length: rawSize)
        guard let raw else { return nil }
        // A file as large as the bitmap was stored as it came: LZ4 would not
        // have made it smaller.
        let destination = raw.mutableBytes.assumingMemoryBound(to: UInt8.self)
        if data.count == rawSize {
            data.copyBytes(to: destination, count: rawSize)
        } else {
            let decoded = data.withUnsafeBytes { source -> Int in
                guard let start = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destination,
                    rawSize,
                    start,
                    data.count,
                    nil,
                    COMPRESSION_LZ4
                )
            }
            guard decoded == rawSize else { return nil }
        }
        guard let provider = CGDataProvider(data: raw as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// This process's folder, created — and, the first time this process asks,
    /// the root swept of what dead processes left. A live process's folder is
    /// never touched.
    private static func preparedHome() -> URL {
        lock.lock()
        defer { lock.unlock() }
        let fileManager = FileManager.default
        if sweptRoot != root {
            let entries = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for entry in entries where !isLiveProcessFolder(entry) {
                try? fileManager.removeItem(at: entry)
            }
            sweptRoot = root
        }
        try? fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    /// A folder named for a process that still exists. Anything else in the
    /// root — a dead pid, or a layout an older build used — is stale.
    private static func isLiveProcessFolder(_ url: URL) -> Bool {
        guard let pid = pid_t(url.lastPathComponent), pid > 0 else { return false }
        // EPERM means it exists but is not ours to signal: still alive.
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// Draws frames into one reused bitmap and compresses it. Keeps the first
    /// frame's colour space, so the pixels come back tagged as they went in.
    private final class Writer {
        let width: Int
        let height: Int
        let colorSpace: CGColorSpace
        private let rawSize: Int
        private let pixels: UnsafeMutableRawPointer
        private let scratch: UnsafeMutablePointer<UInt8>
        private let context: CGContext

        init?(first: CGImage) {
            let width = first.width, height = first.height
            let rawSize = width * height * 4
            guard rawSize > 0 else { return nil }
            let pixels = UnsafeMutableRawPointer.allocate(byteCount: rawSize, alignment: 16)

            // Some tagged spaces will not back a bitmap; sRGB always will.
            let candidates = [first.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
            let made = candidates.lazy.compactMap { space in
                CGContext(
                    data: pixels,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ).map { (space, $0) }
            }.first
            guard let (space, context) = made else {
                pixels.deallocate()
                return nil
            }
            self.width = width
            self.height = height
            self.rawSize = rawSize
            self.pixels = pixels
            self.scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: rawSize)
            self.colorSpace = space
            self.context = context
        }

        deinit {
            pixels.deallocate()
            scratch.deallocate()
        }

        /// The frame's bytes ready to write, or nil if it is not the same size
        /// as the first.
        func compressed(_ image: CGImage) -> Data? {
            guard image.width == width, image.height == height else { return nil }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.clear(rect)
            context.draw(image, in: rect)
            // One byte short of the bitmap: if LZ4 cannot beat that it returns
            // 0, and the frame is written as it is.
            let size = compression_encode_buffer(
                scratch,
                rawSize - 1,
                pixels.assumingMemoryBound(to: UInt8.self),
                rawSize,
                nil,
                COMPRESSION_LZ4
            )
            if size > 0 { return Data(bytes: scratch, count: size) }
            return Data(bytes: pixels, count: rawSize)
        }
    }
}
