// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// How full a session's context window is, drawn as a small meter: a faint
/// track, filled left to right, outlined in 1px.
///
/// A value, not a view: the row owns where it sits (`SessionRowView.layout`)
/// and this owns only how it looks, so the look can be rendered offscreen and
/// checked without building a row. docs/CONTEXT-METER.md has the data's path.
///
/// The crudest reading on purpose — two colour states, one threshold, no
/// animation. Drawn in the row's own background pass, so a theme's frame art
/// or overlay sits over it.
struct ContextMeter: Equatable {
    /// 0-100.
    let percent: Int

    static let height: CGFloat = 4

    /// Where the meter turns red. Claude compacts on its own near the top of
    /// the window, so this is a "soon" and not a "now".
    static let warnPercent = 85

    var isNearlyFull: Bool { percent >= Self.warnPercent }

    /// `ink` is the row's text colour, which the muted state borrows so the
    /// meter sits in the theme's palette; red and green are fixed.
    func draw(in track: NSRect, ink: NSColor) {
        guard percent > 0, track.width > 0 else { return }
        let radius = track.height / 2

        ink.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        // Never narrower than the track is tall, or a low reading is a sliver
        // the rounded ends cannot draw.
        var filled = track
        filled.size.width = max(track.height, track.width * CGFloat(percent) / 100)
        (isNearlyFull ? NSColor.systemRed : ink.withAlphaComponent(0.5)).setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()

        // Inset half a pixel so the stroke stays inside the track.
        let outline = NSBezierPath(
            roundedRect: track.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        outline.lineWidth = 1
        (isNearlyFull ? NSColor.systemRed : NSColor.systemGreen.withAlphaComponent(0.35)).setStroke()
        outline.stroke()
    }
}
