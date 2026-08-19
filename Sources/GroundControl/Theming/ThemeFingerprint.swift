// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import CryptoKit
import Foundation

/// Whether a theme folder is still exactly as it was installed.
///
/// This is the whole question behind updating a shipped theme: a copy nobody
/// has touched can be replaced with a newer one safely, and a copy somebody has
/// edited must never be. Getting that backwards costs an evening of somebody
/// else's work.
///
/// Content is hashed rather than compared by size and date. Recolouring a
/// manifest — `#111111` to `#222222` — changes neither, and recolouring is the
/// single most likely edit anyone makes.
enum ThemeFingerprint {
    /// A hash of every file in the folder, name and bytes, in a stable order.
    /// Nil when the folder cannot be read at all.
    static func of(_ folder: URL) -> String? {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: folder.path) else { return nil }

        var hasher = SHA256()
        for name in names.sorted() where !name.hasPrefix(".") {
            guard let bytes = try? Data(contentsOf: folder.appendingPathComponent(name)) else {
                continue
            }
            hasher.update(data: Data(name.utf8))
            hasher.update(data: bytes)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
