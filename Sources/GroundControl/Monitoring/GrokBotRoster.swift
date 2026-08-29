// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// One decoded `…roster.last-roster` blob from Grok Bot's local cache.
///
/// This is an **undocumented** cache Grok Bot writes for its own sidebar
/// (docs/GROK-BOT-INTEGRATION.md). It is plaintext JSON, but the shape is not a
/// contract: `schemaVersion` was already at 3 when it was first read, and the
/// one field the panel leans on (`sessionPreview.kind`) could be renamed in any
/// update. So all of the tolerance lives here — a blob that parses but does not
/// look right returns `.unexpectedShape`, and the caller shows a visible
/// "can't read status" row rather than a silent wrong one.
///
/// Hand-walked rather than `Codable`: `awaitingUserResponse` is `null` or an
/// object depending on state, and being generous with a format nobody promised
/// is the whole point.
struct GrokBotRoster: Equatable {
    var bots: [Bot]

    struct Bot: Equatable {
        let id: String
        let name: String
        /// Epoch of the bot's last activity — drives ordering.
        let updatedAt: Date
        /// `"widget_options"` while a decision card waits, `"widget_answered"`
        /// just after it is tapped, `"text"` / nil otherwise.
        let sessionPreviewKind: String?
        /// A genuine mid-turn block (login wall, CAPTCHA). Stayed `null` through
        /// every observed decision card — reserved for the hard case.
        let awaitingUser: Bool
        /// The sidebar badge. Focus-driven, so a soft signal at best.
        let unreadCount: Int
        let isHidden: Bool
        /// A channel (a room with several bots) rather than a 1:1 chat. Not
        /// shown in v1.
        let isChannel: Bool
    }

    enum ParseError: Error, Equatable {
        /// Not JSON at all, or not an object.
        case notJSON
        /// Parsed, but `value.rows` was absent or not an array, or a row was
        /// missing an id/name. The format has moved.
        case unexpectedShape(String)
    }

    /// The one field name the panel depends on. Kept here so a rename is a
    /// one-line fix with a test beside it.
    static let cardPendingKind = "widget_options"

    static func parse(_ data: Data) -> Result<GrokBotRoster, ParseError> {
        guard
            let root = try? JSONSerialization.jsonObject(with: data),
            let top = root as? [String: Any]
        else { return .failure(.notJSON) }

        guard let value = top["value"] as? [String: Any] else {
            return .failure(.unexpectedShape("no 'value' object"))
        }
        guard let rows = value["rows"] as? [[String: Any]] else {
            return .failure(.unexpectedShape("'value.rows' missing or not an array"))
        }

        var bots: [Bot] = []
        for row in rows {
            guard let id = row["id"] as? String, !id.isEmpty else {
                return .failure(.unexpectedShape("a row has no 'id'"))
            }
            guard let name = row["name"] as? String, !name.isEmpty else {
                return .failure(.unexpectedShape("row \(id) has no 'name'"))
            }

            let lastEntry = row["lastEntry"] as? [String: Any]
            let preview = lastEntry?["sessionPreview"] as? [String: Any]

            bots.append(Bot(
                id: id,
                name: name,
                updatedAt: Self.date(row["updatedAt"] ?? row["lastActivityAt"]),
                sessionPreviewKind: preview?["kind"] as? String,
                awaitingUser: !(row["awaitingUserResponse"] is NSNull)
                    && row["awaitingUserResponse"] != nil,
                unreadCount: row["unreadCount"] as? Int ?? 0,
                isHidden: row["isHiddenFromSidebar"] as? Bool ?? false,
                isChannel: row["isGroup"] as? Bool ?? false
            ))
        }
        return .success(GrokBotRoster(bots: bots))
    }

    /// Grok Bot writes epoch **milliseconds** as a number.
    private static func date(_ raw: Any?) -> Date {
        guard let ms = raw as? Double ?? (raw as? Int).map(Double.init) else {
            return .distantPast
        }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
