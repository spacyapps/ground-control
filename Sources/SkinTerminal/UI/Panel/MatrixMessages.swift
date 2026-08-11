// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import Foundation

/// What the matrix spells while the panel is asleep.
///
/// Every string is limited to the glyphs `MatrixFont` actually has — A–Z, 0–9
/// and `. - !` — so no message can render as gaps. Keep them short: the whole
/// thing has to scroll past before the next session event interrupts it.
enum MatrixMessages {
    /// The brand shows more often than any single joke, without being the only
    /// thing you ever see.
    static let brand = "SPACYAPPS"
    private static let brandEveryNth = 3

    static let jokes = [
        "HELLO WORLD",
        "ALL QUIET",
        "NO BUGS HERE",
        "SHIP IT",
        "IT COMPILES",
        "LGTM",
        "WORKS FOR ME",
        "OFF BY ONE",
        "RUBBER DUCK",
        "YAK SHAVING",
        "CACHE MISS",
        "HEISENBUG",
        "TABS OR SPACES",
        "MERGE CONFLICT",
        "REBASE AND PRAY",
        "TODO FIX THIS",
        "NULL POINTER",
        "IM A TEAPOT",
        "RTFM",
        "STACK TRACE",
        "99 BUGS LEFT",
        "AWAITING HUMAN",
        "IDLE HANDS",
        "COMMIT EARLY"
    ]

    /// Long enough to read, short enough that the spectrum stays visible on
    /// both sides — a word that fills the grid reads as a sign, not as a word
    /// passing through a meter.
    static let maxLength = 13

    /// Total canned phrases, brand included. Harvested words are unbounded.
    static var count: Int { jokes.count + 1 }

    /// Words too ordinary to be worth spelling out. Everything here would make
    /// the display look like it was reading a dictionary rather than watching
    /// your sessions.
    private static let ordinary: Set<String> = [
        "ABOUT", "AFTER", "AGAIN", "ALREADY", "ALWAYS", "ANOTHER", "BECAUSE",
        "BEFORE", "BEING", "BETTER", "COULD", "DOING", "EVERY", "FIRST", "FROM",
        "GOING", "HAVE", "HERE", "INSTEAD", "INTO", "JUST", "LIKE", "MAKE",
        "MORE", "MOST", "NEED", "NEVER", "ONLY", "OTHER", "OVER", "PLEASE",
        "REALLY", "SHOULD", "SOME", "STILL", "THAN", "THAT", "THEIR", "THEM",
        "THEN", "THERE", "THESE", "THEY", "THING", "THIS", "THOSE", "THROUGH",
        "UNDER", "UNTIL", "USING", "WHAT", "WHEN", "WHERE", "WHICH", "WHILE",
        "WITH", "WOULD", "YOUR", "YOURS", "SHOULD", "MIGHT", "ABOVE", "BELOW"
    ]

    /// Pulls something worth reading out of what the sessions are actually
    /// saying. Ordinary words and anything the font cannot draw are dropped;
    /// what survives tends to be the interesting nouns — file names, tools,
    /// project words.
    static func harvest(from messages: [String]) -> [String] {
        var seen = Set<String>()
        var found: [String] = []

        for message in messages {
            let words = message.split { !$0.isLetter && !$0.isNumber }
            for raw in words {
                let word = String(raw).uppercased()
                guard word.count >= 5, word.count <= maxLength,
                      !ordinary.contains(word),
                      word.contains(where: \.isLetter),
                      word.allSatisfy(MatrixFont.supports),
                      seen.insert(word).inserted else { continue }
                found.append(word)
            }
        }
        return found
    }

    /// Picks the next message: the brand on every third turn, then — when the
    /// sessions have given us something — a word lifted from their own output,
    /// otherwise a canned line. Never repeats the previous message.
    static func next(turn: Int, avoiding previous: String?, harvested: [String] = []) -> String {
        guard turn % brandEveryNth != 0 else { return brand }

        let fresh = harvested.filter { $0 != previous }
        if !fresh.isEmpty, Bool.random(), let word = fresh.randomElement() {
            return word
        }
        return jokes.filter { $0 != previous }.randomElement() ?? brand
    }

    /// Seconds of quiet before the next message. Randomised so it never feels
    /// metronomic — a sign that blinks on a fixed beat reads as a status light.
    static func nextDelay() -> TimeInterval {
        .random(in: 18...32)
    }
}
