// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// A switch that is green when it is on.
///
/// `NSSwitch` follows the system accent colour and offers no way to tint it, so
/// on a Mac set to graphite or red these read as anything but "on". Green is the
/// one colour that means working without being read, which is the whole job of
/// this menu — and this app already draws its own gears, marks and meters, so
/// one more small control is no new kind of work.
final class HookSwitch: NSControl {
    var isOn: Bool { didSet { needsDisplay = true } }
    private let onToggle: (Bool) -> Void

    static let size = NSSize(width: 30, height: 17)

    init(isOn: Bool, isEnabled: Bool, onToggle: @escaping (Bool) -> Void) {
        self.isOn = isOn
        self.onToggle = onToggle
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        self.isEnabled = isEnabled
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size.width),
            heightAnchor.constraint(equalToConstant: Self.size.height)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HookSwitch is created in code only")
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = track.height / 2

        trackColour.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        // A hairline keeps the off state legible against a dark menu, where a
        // grey track on a grey background all but disappears.
        NSColor.white.withAlphaComponent(isOn ? 0.10 : 0.18).setStroke()
        let edge = NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius)
        edge.lineWidth = 1
        edge.stroke()

        let diameter = track.height - 4
        let knob = NSRect(
            x: isOn ? track.maxX - diameter - 2 : track.minX + 2,
            y: track.minY + 2,
            width: diameter,
            height: diameter
        )
        NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.55).setFill()
        NSBezierPath(ovalIn: knob).fill()
    }

    private var trackColour: NSColor {
        guard isEnabled else { return NSColor.white.withAlphaComponent(0.08) }
        return isOn
            ? NSColor.systemGreen.withAlphaComponent(0.9)
            : NSColor.white.withAlphaComponent(0.14)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isOn.toggle()
        onToggle(isOn)
    }

    override var acceptsFirstResponder: Bool { false }
}
