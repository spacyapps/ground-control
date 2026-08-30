// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Reads a file only after checking it is a sane size.
///
/// The app reads files other processes write — `.jsonl` lines into a temp
/// folder any local process can touch, `theme.json` from a folder someone may
/// have handed you. A file far larger than its kind should ever be is either a
/// mistake or an attempt to make the app hold gigabytes in memory, so it is not
/// read at all.
enum BoundedRead {
    /// A session left running all day is a few megabytes of `.jsonl`. This
    /// ceiling sits well past any real one.
    static let sessionFileLimit = 64 * 1024 * 1024

    /// A manifest is kilobytes. Generous enough for one that inlines a data-URI
    /// or two, small enough to stop a hostile multi-megabyte file.
    static let manifestLimit = 16 * 1024 * 1024

    static func data(at url: URL, limit: Int) -> Data? {
        guard let size = fileSize(of: url), size <= limit else { return nil }
        return try? Data(contentsOf: url)
    }

    static func string(at url: URL, limit: Int) -> String? {
        data(at: url, limit: limit).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func fileSize(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }
}
