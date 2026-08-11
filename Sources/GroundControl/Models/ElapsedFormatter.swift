// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// How long a row has been in its current state.
///
/// "waiting" for four seconds and "waiting" for forty minutes read identically
/// without this, and the second is the one that matters. Kept deliberately
/// terse — this sits at the end of a row, not in a report.
enum ElapsedFormatter {
    static func short(since date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))

        // Clock skew, or a line written a moment in the future.
        guard seconds > 0 else { return "now" }

        switch seconds {
        case ..<10: return "now"
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }

    /// How long a row may keep claiming its last state before age overrides it
    /// and it reads as idle. See `Session.state`.
    static let staleAfter: TimeInterval = 30 * 60

    static func isStale(since date: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(date) > staleAfter
    }
}
