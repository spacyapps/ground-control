// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import AppKit

extension NSColor {
    /// Parses `#rrggbb` or `#rrggbbaa` (the `#` is optional).
    /// Returns nil for anything else so callers can fall back to a default.
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8,
              let value = UInt64(text, radix: 16) else { return nil }

        let hasAlpha = text.count == 8
        let red = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1

        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
