// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The built-in face, drawn rather than shipped.
///
/// Using SF Symbols means the default theme carries no image files at all: the
/// avatar scales to any size, tints itself from the active palette, and works
/// identically whether the app runs from `swift run` or a bundled `.app` —
/// no resource-bundle plumbing to get wrong.
///
/// A theme that sets its own image or video for a state overrides this
/// entirely (docs/THEMING.md).
enum DrawnAvatar {
    /// Symbols are template images, so the tint comes from
    /// `contentTintColor` at display time rather than being baked in here.
    static func symbol(for state: SessionState) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName(for: state), accessibilityDescription: label(for: state))
        image?.isTemplate = true
        return image
    }

    /// `working` is the one that spins; see `AvatarView`.
    static func isAnimated(_ state: SessionState) -> Bool { state == .working }

    private static func symbolName(for state: SessionState) -> String {
        switch state {
        case .idle: return "moon.zzz.fill"
        case .working: return "gearshape.fill"
        case .needsInput: return "exclamationmark.bubble.fill"
        case .done: return "checkmark.seal.fill"
        }
    }

    private static func label(for state: SessionState) -> String {
        switch state {
        case .idle: return "Idle"
        case .working: return "Working"
        case .needsInput: return "Needs your input"
        case .done: return "Done"
        }
    }
}
