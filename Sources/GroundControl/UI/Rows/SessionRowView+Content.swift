// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The text a row shows, as opposed to how it is laid out.
extension SessionRowView {
    func summary(for session: Session) -> String {
        guard session.isGroup else { return session.message }
        let count = session.children.count

        // Grok Bot's parent is not one conversation: a count, and how many bots
        // wait on you, in place of a last line (docs/GROK-BOT-GROUPING.md).
        if session.source == "grokbot" {
            let base = count == 1 ? "1 bot" : "\(count) bots"
            let waiting = session.children.filter(\.needsAction).count
            return waiting > 0 ? "\(base)  ·  \(waiting) waiting" : base
        }

        let suffix = count == 1 ? "1 subagent" : "\(count) subagents"
        return session.message.isEmpty ? suffix : "\(session.message)  ·  \(suffix)"
    }

    func triangle(expanded: Bool, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: expanded ? "▼" : "▶",
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 8)]
        )
    }
}
