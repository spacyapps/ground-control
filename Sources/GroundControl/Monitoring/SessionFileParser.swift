// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Reads a `.jsonl` file and returns its current state.
///
/// Only the last decodable line matters (docs/SPEC.md §2). Lines are scanned
/// from the end so a half-written trailing line — a real possibility while a
/// hook is appending — falls back to the previous good one instead of
/// blanking the row.
///
/// Results are remembered per file, because the store re-reads every session
/// twice a second and most of them have not changed. Measured before adding
/// this: one reload read 1.1MB and took 12.6ms, and the profiler's heaviest
/// frame in our own code was splitting those strings. It is small now and grows
/// with sessions × age — a session left running all day is megabytes, re-read
/// and re-split every two seconds for nothing.
enum SessionFileParser {
    /// What a file looked like when it was last parsed.
    ///
    /// Size *and* modification date. Date alone is the usual trick and is not
    /// enough on its own — two appends inside one timestamp tick would be
    /// missed, and a row would sit stale until the next write. These files only
    /// ever grow, so size is the stronger of the two signals; both are cheap.
    private struct Stamp: Equatable {
        let size: Int
        let modified: Date
    }

    private final class Box {
        var stamp: Stamp
        var value: Any?
        init(stamp: Stamp, value: Any?) {
            self.stamp = stamp
            self.value = value
        }
    }

    private static let cache = NSCache<NSURL, Box>()

    static func latestEvent(at url: URL) -> SessionEvent? {
        latest(at: url, as: SessionEvent.self)
    }

    static func latestAgentEvent(at url: URL) -> AgentEvent? {
        latest(at: url, as: AgentEvent.self)
    }

    /// Forgets everything remembered. For tests, which write a file, read it,
    /// then rewrite it inside the same timestamp tick.
    static func clearCache() {
        cache.removeAllObjects()
    }

    /// Through FileManager rather than `url.resourceValues`, which **caches on
    /// the URL object**: the first read's size and date are returned for that
    /// URL forever after, so every file looked unchanged and every row froze.
    /// Caught by the tests below, which is what they are for.
    private static func stamp(of url: URL) -> Stamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Stamp(size: size, modified: modified)
    }

    private static func latest<T: Decodable>(at url: URL, as type: T.Type) -> T? {
        let current = stamp(of: url)
        if let current, let box = cache.object(forKey: url as NSURL), box.stamp == current {
            // A file of the same size and date has the same last line. The cast
            // is by type because one URL is only ever read as one kind.
            return box.value as? T
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let decoder = JSONDecoder()
        var decoded: T?
        for line in contents.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            if let value = try? decoder.decode(type, from: data) {
                decoded = value
                break
            }
        }

        // Cached even when nothing decoded: a file of junk should be read once,
        // not on every reload for as long as it sits there.
        if let current {
            cache.setObject(Box(stamp: current, value: decoded), forKey: url as NSURL)
        }
        return decoded
    }
}
