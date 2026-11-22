// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The text a row shows, as opposed to how it is laid out.
extension SessionRowView {
    func summary(for session: Session) -> String {
        // Grok Bot's parent is not one conversation: a count, and how many bots
        // wait on you, in place of a last line (docs/GROK-BOT-GROUPING.md).
        if session.source == "grokbot", session.isGroup {
            let count = session.children.count
            let base = count == 1 ? "1 bot" : "\(count) bots"
            let waiting = session.children.filter(\.needsAction).count
            return waiting > 0 ? "\(base)  ·  \(waiting) waiting" : base
        }

        let parts = [session.message, session.childSummary]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.joined(separator: "  ·  ")
    }

    func triangle(expanded: Bool, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: expanded ? "▼" : "▶",
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 8)]
        )
    }
}
