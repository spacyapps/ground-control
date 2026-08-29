// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Just enough RFC 4648 base32 to read the slice name out of a Grok Bot cache
/// filename (docs/GROK-BOT-INTEGRATION.md). Decode only, lowercase input,
/// padding optional — which is exactly how Grok Bot writes them.
enum Base32 {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")

    static func decode(_ input: String) -> String? {
        let lookup = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
        var buffer = 0
        var bitsLeft = 0
        var bytes: [UInt8] = []

        for character in input.lowercased() where character != "=" {
            guard let value = lookup[character] else { return nil }
            buffer = (buffer << 5) | value
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                bytes.append(UInt8((buffer >> bitsLeft) & 0xFF))
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
