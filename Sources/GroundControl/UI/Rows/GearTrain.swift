// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import QuartzCore

/// Two meshed gears, for the `working` avatar.
///
/// The old one was a single SF Symbol with a rotation on the image view's own
/// layer — and `layout()` writes that view's `frame` on every pass. `frame` is
/// *derived* from the transform, so writing it back re-derives bounds from a
/// rotated bounding box: a 40×40 gear became 56×9 on the first layout, which is
/// what people were describing as the gear falling off.
///
/// So each gear here gets its own layer whose `bounds` and `position` are set
/// directly and whose transform is never read back. Rotation cannot deform what
/// it is not asked to measure.
///
/// The ratios are real. Meshed gears share a tooth pitch, so a wheel's radius
/// is proportional to its tooth count, its speed is inversely proportional, and
/// neighbours turn opposite ways. Getting that wrong is the sort of thing you
/// cannot name but can see — it reads as slipping.
enum GearTrain {
    /// A wheel in the train. Teeth counts are coprime-ish so the pattern takes
    /// a long time to repeat, which is what stops it looking like a loop.
    private struct Wheel {
        let teeth: Int
        /// Direction from the previous wheel's centre, in radians.
        let bearing: CGFloat
    }

    /// Bearings are absolute, not relative to the wheel before. A chain of
    /// relative turns folded back on itself — a third wheel once landed almost
    /// on top of the first — and absolute angles make that visible in the
    /// numbers instead of only on screen.
    ///
    /// Two wheels, not three. An avatar is around forty points across, and
    /// three trains fitted into that left every wheel too small to see turning,
    /// which defeats the only thing the animation is for.
    private static let wheels = [
        Wheel(teeth: 12, bearing: 0),
        Wheel(teeth: 8, bearing: .pi * 0.28)
    ]

    /// Drawn larger than the box and clipped by the avatar's plate.
    ///
    /// Fitting the whole train inside meant shrinking it until the teeth were a
    /// pixel or two — visible as a blur rather than as rotation. Cropping costs
    /// nothing here: a gear is the same shape all the way round, so a wheel
    /// running off the edge still reads as a wheel, and the parts that remain
    /// are big enough to watch.
    private static let overfill: CGFloat = 2.05

    /// How long the largest wheel takes to come round once. The others follow
    /// from their tooth counts, so this is the only speed to choose.
    private static let period: TimeInterval = 4

    /// Where each wheel sits and how big it is, in points, for a given box.
    ///
    /// Separate from building layers because it is the part with all the
    /// decisions in it, and the part worth reading on its own.
    private struct Layout {
        let centres: [CGPoint]
        let radii: [CGFloat]
        let module: CGFloat
    }

    private static func layout(in size: CGSize) -> Layout {
        // Laid out in its own units and fitted afterwards, so the geometry
        // never has to know how big an avatar is.
        let module: CGFloat = 1
        var centres: [CGPoint] = []
        var radii: [CGFloat] = []

        for (index, wheel) in wheels.enumerated() {
            let radius = module * CGFloat(wheel.teeth) / 2
            if index == 0 {
                centres.append(.zero)
            } else {
                // A real train meshes tooth-into-valley. These wheels are not
                // phase-aligned, so they are spaced a hair further apart than
                // theory: tips clear each other instead of passing through,
                // which is the difference between meshing and colliding.
                let gap = radii[index - 1] + radius + module * 0.55
                let previous = centres[index - 1]
                centres.append(CGPoint(
                    x: previous.x + cos(wheel.bearing) * gap,
                    y: previous.y + sin(wheel.bearing) * gap
                ))
            }
            radii.append(radius)
        }

        var tips = CGRect.null
        var hubs = CGRect.null
        for (centre, radius) in zip(centres, radii) {
            let outer = radius + module      // tooth tips stand one module proud
            tips = tips.union(CGRect(
                x: centre.x - outer,
                y: centre.y - outer,
                width: outer * 2,
                height: outer * 2
            ))
            hubs = hubs.union(CGRect(origin: centre, size: .zero))
        }

        // Two limits, and the tighter one wins.
        //
        // Overfilling makes the teeth big enough to watch, but pushed far
        // enough it walks a wheel's *centre* off the edge — measured at 40.6 in
        // a 40pt box — and a gear cropped past its hub reads as a stray curve
        // rather than as a wheel. So the scale is also capped by keeping every
        // centre inside, with a margin.
        let margin = min(size.width, size.height) * 0.16
        let room = CGSize(
            width: max(1, size.width - margin * 2),
            height: max(1, size.height - margin * 2)
        )
        let byTips = min(size.width / tips.width, size.height / tips.height) * overfill
        let byHubs = min(
            hubs.width > 0 ? room.width / hubs.width : .greatestFiniteMagnitude,
            hubs.height > 0 ? room.height / hubs.height : .greatestFiniteMagnitude
        )
        let scale = min(byTips, byHubs)

        // Centred on the wheels themselves rather than on the toothed hull, so
        // cropping takes teeth off both sides evenly.
        return Layout(
            centres: centres.map {
                CGPoint(
                    x: ($0.x - hubs.midX) * scale + size.width / 2,
                    y: ($0.y - hubs.midY) * scale + size.height / 2
                )
            },
            radii: radii.map { $0 * scale },
            module: module * scale
        )
    }

    /// Builds the train into `size`, tinted, already turning.
    static func layer(size: CGSize, colour: NSColor) -> CALayer {
        let root = CALayer()
        root.bounds = CGRect(origin: .zero, size: size)
        root.position = CGPoint(x: size.width / 2, y: size.height / 2)
        let plan = layout(in: size)

        for (index, wheel) in wheels.enumerated() {
            let gear = CALayer()
            let side = (plan.radii[index] + plan.module) * 2
            gear.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            gear.position = plan.centres[index]
            gear.contents = image(teeth: wheel.teeth, side: side, colour: colour)
            gear.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

            // Speed is inverse to teeth, and every second wheel turns back the
            // other way. Offset each start so they do not begin aligned.
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            let direction: Double = index.isMultiple(of: 2) ? -1 : 1
            turn.fromValue = 0
            turn.toValue = direction * .pi * 2
            turn.duration = period * Double(wheel.teeth) / Double(wheels[0].teeth)
            turn.repeatCount = .infinity
            turn.isRemovedOnCompletion = false
            turn.timeOffset = Double(index) * 0.7
            gear.add(turn, forKey: "spin")

            root.addSublayer(gear)
        }
        return root
    }

    /// One wheel, drawn once and handed to a layer as its contents.
    ///
    /// Trapezoidal teeth rather than true involutes: at twenty points across,
    /// the curve of a real tooth flank is a fraction of a pixel, and the shape
    /// that reads as a gear is the alternation.
    private static func image(teeth: Int, side: CGFloat, colour: NSColor) -> CGImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = CGSize(width: side * scale, height: side * scale)
        guard pixels.width >= 1, pixels.height >= 1 else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixels.width.rounded()),
            pixelsHigh: Int(pixels.height.rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let centre = CGPoint(x: pixels.width / 2, y: pixels.height / 2)
        let outer = min(pixels.width, pixels.height) / 2
        let module = outer / (CGFloat(teeth) / 2 + 1)   // matches the layout above
        let pitch = module * CGFloat(teeth) / 2
        let root = pitch - module * 0.9
        let path = NSBezierPath()

        // Alternate between the tooth tip and the valley, half a tooth at a
        // time, so the outline closes on itself.
        let step = CGFloat.pi / CGFloat(teeth)
        for index in 0..<(teeth * 2) {
            let angle = step * CGFloat(index)
            let onTooth = index.isMultiple(of: 2)
            let radius = onTooth ? outer : root
            // Teeth are narrower at the tip, which is what a gear looks like.
            let width = onTooth ? step * 0.34 : step * 0.46
            let start = CGPoint(
                x: centre.x + cos(angle - width) * radius,
                y: centre.y + sin(angle - width) * radius
            )
            let end = CGPoint(
                x: centre.x + cos(angle + width) * radius,
                y: centre.y + sin(angle + width) * radius
            )
            if index == 0 { path.move(to: start) } else { path.line(to: start) }
            path.line(to: end)
        }
        path.close()

        colour.setFill()
        path.fill()

        // The hub is cut out rather than composed into the outline. Appending a
        // reversed oval and filling even-odd joined the hole to the rim with a
        // wedge — visible as a bite out of every wheel.
        let hub = NSBezierPath(ovalIn: CGRect(
            x: centre.x - root * 0.34,
            y: centre.y - root * 0.34,
            width: root * 0.68,
            height: root * 0.68
        ))
        NSGraphicsContext.current?.compositingOperation = .clear
        NSColor.black.setFill()
        hub.fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
