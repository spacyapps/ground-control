// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// A miniature of one row, drawn in the selected theme.
///
/// Picking a theme from a list of folder names is a guess; showing what it
/// actually looks like is not. Small enough to sit under the picker and update
/// live as the selection changes.
final class ThemePreviewView: NSView {
    private var theme: Theme = DefaultTheme.theme

    override var isFlipped: Bool { true }

    func apply(theme: Theme) {
        self.theme = theme
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let corner: CGFloat = 6
        let panel = NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner)
        theme.colors.windowBackground.setFill()
        panel.fill()

        NSGraphicsContext.current?.saveGraphicsState()
        panel.addClip()

        let titleHeight: CGFloat = 18
        theme.colors.titleBarBackground.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: titleHeight).fill()
        draw(
            "SkinTerminal",
            at: NSPoint(x: 8, y: 4),
            size: 9,
            weight: .semibold,
            color: theme.colors.titleBarText
        )

        // Two sample rows, one quiet and one wanting attention.
        let rowHeight = (bounds.height - titleHeight) / 2
        let samples = [
            Sample(state: .working, name: "avaterm", message: "Bash: swift build"),
            Sample(state: .needsInput, name: "spacyapps", message: "Allow npm install?")
        ]
        for (index, sample) in samples.enumerated() {
            sampleRow(
                sample,
                index: index,
                top: titleHeight + CGFloat(index) * rowHeight,
                height: rowHeight
            )
        }

        NSGraphicsContext.current?.restoreGraphicsState()

        theme.colors.divider.setStroke()
        panel.stroke()
    }

    private struct Sample {
        let state: SessionState
        let name: String
        let message: String
    }

    private func sampleRow(_ sample: Sample, index: Int, top: CGFloat, height: CGFloat) {
        let rect = NSRect(x: 0, y: top, width: bounds.width, height: height)
        (index.isMultiple(of: 2) ? theme.colors.rowBackground : theme.colors.rowBackgroundAlt).setFill()
        rect.fill()

        let accent = theme.colors.color(for: sample.state)
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 10, y: top + height / 2 - 3, width: 6, height: 6)).fill()

        let textX: CGFloat = 24
        draw(
            sample.name,
            at: NSPoint(x: textX, y: top + height / 2 - 12),
            size: 9,
            weight: .semibold,
            color: theme.colors.sessionName
        )
        draw(
            sample.message,
            at: NSPoint(x: textX, y: top + height / 2 + 1),
            size: 8,
            weight: .regular,
            color: theme.colors.message
        )

        // Stand-in for the avatar: themes may replace it, but the geometry is
        // what the preview is showing.
        let side = min(height - 10, theme.avatar.isHidden ? 0 : 20)
        guard side > 0 else { return }
        let box = NSRect(x: bounds.width - side - 8, y: top + (height - side) / 2, width: side, height: side)
        accent.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
    }

    private func draw(_ text: String,
                      at point: NSPoint,
                      size: CGFloat,
                      weight: NSFont.Weight,
                      color: NSColor) {
        (text as NSString).draw(
            at: point,
            withAttributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color
            ]
        )
    }
}
