// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The app's own colours, used for the settings chrome.
///
/// Deliberately fixed rather than taken from the selected theme: Settings is
/// where you *judge* a theme, and a window that restyles itself to match
/// whatever is selected gives you nothing to judge it against. The preview is
/// the themed surface; everything around it belongs to the app.
enum SettingsChrome {
    static let space = NSColor(srgbRed: 0.043, green: 0.043, blue: 0.078, alpha: 1)
    static let deepSpace = NSColor(srgbRed: 0.020, green: 0.020, blue: 0.043, alpha: 1)
    static let heading = NSColor(srgbRed: 0.725, green: 0.640, blue: 0.890, alpha: 1)
    static let rule = NSColor(srgbRed: 0.725, green: 0.640, blue: 0.890, alpha: 0.22)
    static let body = NSColor(srgbRed: 0.878, green: 0.870, blue: 0.925, alpha: 1)
    static let dim = NSColor(srgbRed: 0.878, green: 0.870, blue: 0.925, alpha: 0.55)
    static let viewportEdge = NSColor(srgbRed: 0.725, green: 0.640, blue: 0.890, alpha: 0.30)
    static let caution = NSColor(srgbRed: 1.0, green: 0.72, blue: 0.35, alpha: 1)
}

/// A quiet star field behind the settings controls.
///
/// Drawn rather than shipped as an image: it costs nothing, scales to any
/// window size, and cannot fall out of sync with the palette above.
final class StarfieldView: NSView {
    private struct Star {
        /// Unit coordinates, so the field survives a resize without redrawing
        /// into different places each time.
        let unit: NSPoint
        let radius: CGFloat
        let alpha: CGFloat
    }

    /// Seeded so the sky is the same sky every launch. A field that reshuffles
    /// on every redraw reads as noise, not as a background.
    private struct Seeded: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private let stars: [Star]

    override var isFlipped: Bool { true }

    init(starCount: Int = 110) {
        var generator = Seeded(seed: 0x5350_4143_5941_5050)
        stars = (0..<starCount).map { _ in
            // Most stars faint, a few bright: an even spread looks like dust.
            let brightness = Double.random(in: 0...1, using: &generator)
            return Star(
                unit: NSPoint(
                    x: Double.random(in: 0...1, using: &generator),
                    y: Double.random(in: 0...1, using: &generator)
                ),
                radius: brightness > 0.93 ? 1.5 : (brightness > 0.7 ? 1.0 : 0.7),
                alpha: 0.16 + brightness * 0.62
            )
        }
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StarfieldView is created in code only")
    }

    override func draw(_ dirtyRect: NSRect) {
        let sky = NSGradient(
            colors: [SettingsChrome.space, SettingsChrome.deepSpace],
            atLocations: [0, 1],
            colorSpace: .sRGB
        )
        sky?.draw(in: bounds, angle: 270)

        drawNebula(
            at: NSPoint(x: bounds.width * 0.82, y: bounds.height * 0.12),
            radius: bounds.width * 0.6,
            color: NSColor(srgbRed: 0.35, green: 0.16, blue: 0.55, alpha: 0.30)
        )
        drawNebula(
            at: NSPoint(x: bounds.width * 0.08, y: bounds.height * 0.72),
            radius: bounds.width * 0.55,
            color: NSColor(srgbRed: 0.10, green: 0.32, blue: 0.48, alpha: 0.22)
        )

        for star in stars {
            let centre = NSPoint(x: star.unit.x * bounds.width, y: star.unit.y * bounds.height)
            NSColor.white.withAlphaComponent(star.alpha).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: centre.x - star.radius,
                y: centre.y - star.radius,
                width: star.radius * 2,
                height: star.radius * 2
            )).fill()
        }
    }

    private func drawNebula(at centre: NSPoint, radius: CGFloat, color: NSColor) {
        let gradient = NSGradient(
            colors: [color, color.withAlphaComponent(0)],
            atLocations: [0, 1],
            colorSpace: .sRGB
        )
        gradient?.draw(fromCenter: centre, radius: 0, toCenter: centre, radius: radius, options: [])
    }
}
