// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import AppKit

/// Code-side fallbacks for every key.
///
/// This is what makes themes easy to write: an author overrides one colour and
/// inherits the rest (docs/THEMING.md). Values mirror `Themes/default/theme.json`,
/// which ships as a copyable reference rather than as the app's actual default —
/// the app never needs a file on disk to render.
enum DefaultTheme {
    static let colors = Theme.Colors(
        windowBackground: color("#0e0e12"),
        titleBarBackground: color("#16161d"),
        titleBarText: color("#e6e6ec"),
        rowBackground: color("#14141c"),
        rowBackgroundAlt: color("#181820"),
        rowBackgroundHover: color("#1f1f2b"),
        sessionName: color("#e6e6ec"),
        message: color("#b9b9c6"),
        messageDim: color("#7a7a8a"),
        needsAction: color("#ff2d55"),
        working: color("#39c5ff"),
        idle: color("#5a5a6a"),
        footerBackground: color("#16161d"),
        footerText: color("#8a8a99"),
        accent: color("#39ff14"),
        divider: color("#26263200")
    )

    static let layout = Theme.Layout(
        rowMaxHeight: 100,
        rowPadding: 10,
        marqueeOnOverflow: true,
        marqueeSpeed: 40,
        isCompact: false
    )

    static let typography = Theme.Typography(
        fontFamily: nil,
        nameSize: 13,
        messageSize: 11,
        nameWeight: .semibold
    )

    /// No states: the built-in theme ships no artwork, so rows are dot + text
    /// until a theme supplies faces. That is the documented behaviour, not a
    /// gap — "omit a state, draw no avatar" (docs/THEMING.md).
    static let avatar = Theme.Avatar(
        size: 48,
        position: .right,
        cornerRadius: 8,
        states: [:]
    )

    static var theme: Theme {
        Theme(
            name: "Default",
            colors: colors,
            layout: layout,
            typography: typography,
            avatar: avatar,
            backgrounds: .none,
            folder: nil
        )
    }

    /// Defaults are authored as literals we control, so a bad string here is a
    /// programming error rather than user input — magenta makes it obvious.
    private static func color(_ hex: String) -> NSColor {
        NSColor(hex: hex) ?? .magenta
    }
}
