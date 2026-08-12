// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import ImageIO

/// What the selected theme actually looks like.
///
/// It used to draw the palette only, standing the avatars in as coloured
/// squares — which meant the one thing a theme author most needs to check, that
/// four generated images landed and read correctly, was the one thing the
/// preview would not show. Now it draws the real artwork: the window skin
/// behind the rows, and every state's own face.
final class ThemePreviewView: NSView {
    static let preferredSize = NSSize(width: 360, height: 232)

    /// The order a theme author thinks in: quiet, busy, blocked, finished.
    private static let states: [(SessionState, String)] = [
        (.idle, "IDLE"),
        (.working, "WORKING"),
        (.needsInput, "NEEDS YOU"),
        (.done, "DONE")
    ]

    private static let imageCache = NSCache<NSURL, NSImage>()

    private var theme: Theme = DefaultTheme.theme

    override var isFlipped: Bool { true }

    func apply(theme: Theme) {
        self.theme = theme
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let panelHeight: CGFloat = 162
        drawPanel(in: NSRect(x: 0, y: 0, width: bounds.width, height: panelHeight))
        drawStates(in: NSRect(
            x: 0,
            y: panelHeight + 10,
            width: bounds.width,
            height: max(0, bounds.height - panelHeight - 10)
        ))
    }

    // MARK: - The panel miniature

    private func drawPanel(in rect: NSRect) {
        let clip = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSGraphicsContext.current?.saveGraphicsState()
        clip.addClip()

        theme.colors.windowBackground.setFill()
        rect.fill()

        // The skin, filled to the box rather than nine-sliced. At preview size
        // the theme's cap insets — often 100pt a side — would exceed the box
        // and collapse the artwork into corners, showing something the panel
        // never looks like.
        var artScale: CGFloat = 1
        if let art = theme.window.shape ?? theme.backgrounds.window,
           let image = Self.still(art) {
            // Anchored to the top, not centred: a framed skin keeps its
            // recognisable edge — hull, antennae, title bezel — up there, and a
            // centre crop of a tall frame shows nothing but its side pillars.
            artScale = draw(image, fillingAspectOf: rect, anchor: .top)
        }

        let content = contentRect(in: rect, artScale: artScale)

        let titleHeight: CGFloat = 22
        theme.colors.titleBarBackground.setFill()
        NSRect(
            x: content.minX,
            y: content.minY,
            width: content.width,
            height: titleHeight
        ).fill()
        draw(
            theme.name,
            at: NSPoint(x: content.minX + 9, y: content.minY + 6),
            size: 9,
            weight: .semibold,
            color: theme.colors.titleBarText
        )

        // Rows are translucent in most themes, which is exactly how the skin is
        // meant to show through — so they go on top of the artwork, not instead.
        let samples = [
            (SessionState.working, "avaterm", "Bash: swift build"),
            (SessionState.needsInput, "spacyapps", "Allow npm install?")
        ]
        let rowsTop = content.minY + titleHeight
        let rowHeight = (content.maxY - rowsTop) / CGFloat(samples.count)

        for (index, sample) in samples.enumerated() {
            drawRow(
                state: sample.0,
                name: sample.1,
                message: sample.2,
                alternate: !index.isMultiple(of: 2),
                in: NSRect(
                    x: content.minX,
                    y: rowsTop + CGFloat(index) * rowHeight,
                    width: content.width,
                    height: rowHeight
                )
            )
        }

        NSGraphicsContext.current?.restoreGraphicsState()

        SettingsChrome.viewportEdge.setStroke()
        clip.lineWidth = 1
        clip.stroke()
    }

    /// Where the rows go once the skin's frame is accounted for.
    ///
    /// `contentInset` is what holds rows off the artwork in the real panel, and
    /// ignoring it here put them straight over the hull's pillars. The panel
    /// draws its frame 1:1 while the preview scales the whole image down, so
    /// the inset scales by the same factor to land in the same place.
    ///
    /// No inset at the bottom: the art is anchored to the top and cropped, so
    /// there is no bottom frame on screen to stay clear of.
    func contentRect(in rect: NSRect, artScale: CGFloat) -> NSRect {
        let ceiling = min(rect.width * 0.3, rect.height * 0.3)
        let inset = min(theme.layout.contentInset * artScale, ceiling)
        return NSRect(
            x: rect.minX + inset,
            y: rect.minY + inset,
            width: rect.width - inset * 2,
            height: rect.height - inset
        )
    }

    private func drawRow(state: SessionState,
                         name: String,
                         message: String,
                         alternate: Bool,
                         in rect: NSRect) {
        (alternate ? theme.colors.rowBackgroundAlt : theme.colors.rowBackground).setFill()
        rect.fill()

        let accent = theme.colors.color(for: state)
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: rect.minX + 9,
            y: rect.midY - 3,
            width: 6,
            height: 6
        )).fill()

        draw(
            name,
            at: NSPoint(x: rect.minX + 23, y: rect.midY - 13),
            size: 9,
            weight: .semibold,
            color: theme.colors.sessionName
        )
        draw(
            message,
            at: NSPoint(x: rect.minX + 23, y: rect.midY),
            size: 8,
            weight: .regular,
            color: theme.colors.message
        )

        guard !theme.avatar.isHidden else { return }
        let side = min(rect.height - 8, 30)
        drawAvatar(
            for: state,
            in: NSRect(
                x: rect.maxX - side - 8,
                y: rect.midY - side / 2,
                width: side,
                height: side
            )
        )
    }

    // MARK: - Every state at once

    /// The four faces side by side, which is how you check a generated set:
    /// four files, four states, and whether any of them came back wrong.
    private func drawStates(in rect: NSRect) {
        guard rect.height > 20 else { return }

        let cellWidth = rect.width / CGFloat(Self.states.count)
        let side = min(rect.height - 16, 34)

        for (index, entry) in Self.states.enumerated() {
            let cell = NSRect(
                x: rect.minX + CGFloat(index) * cellWidth,
                y: rect.minY,
                width: cellWidth,
                height: rect.height
            )

            if theme.avatar.isHidden {
                draw(
                    "off",
                    at: NSPoint(x: cell.midX - 8, y: cell.minY + 4),
                    size: 9,
                    weight: .regular,
                    color: SettingsChrome.dim
                )
            } else {
                drawAvatar(
                    for: entry.0,
                    in: NSRect(
                        x: cell.midX - side / 2,
                        y: cell.minY,
                        width: side,
                        height: side
                    )
                )
            }

            let label = NSAttributedString(
                string: entry.1,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .medium),
                    .foregroundColor: SettingsChrome.dim,
                    .kern: 0.6
                ]
            )
            label.draw(at: NSPoint(
                x: cell.midX - label.size().width / 2,
                y: cell.minY + side + 4
            ))
        }
    }

    // MARK: - Artwork

    /// The theme's own image for a state, or the built-in face tinted to match —
    /// the same fallback the panel makes, so the preview cannot promise a face
    /// the rows will not draw.
    private func drawAvatar(for state: SessionState, in rect: NSRect) {
        let radius = min(theme.avatar.cornerRadius, rect.width / 2)
        let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        switch theme.avatar.asset(for: state) {
        case .image(let url):
            guard let image = Self.image(at: url) else { break }
            NSGraphicsContext.current?.saveGraphicsState()
            clip.addClip()
            draw(image, fillingAspectOf: rect)
            NSGraphicsContext.current?.restoreGraphicsState()
            return
        case .video:
            // A frame grab means spinning up AVFoundation for a thumbnail; the
            // drawn face says "this state is covered" without the machinery.
            break
        case .none:
            break
        }

        let tint = theme.colors.color(for: state)
        if let symbol = DrawnAvatar.symbol(for: state) {
            let inset = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
            Self.tinted(symbol, tint).draw(
                in: inset,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        } else {
            tint.withAlphaComponent(0.85).setFill()
            clip.fill()
        }
    }

    private enum Anchor {
        case centre
        case top
    }

    /// Scales to cover — the artwork keeps its proportions and the box is
    /// filled, which is what a thumbnail of a skin should do.
    ///
    /// `respectFlipped` is the whole ballgame here: this view is flipped so text
    /// reads downward, and an image drawn into a flipped context arrives upside
    /// down unless it is told to honour the flip.
    /// Returns the scale the artwork was drawn at, which is what the frame
    /// inset has to be measured against.
    @discardableResult
    private func draw(_ image: NSImage,
                      fillingAspectOf rect: NSRect,
                      anchor: Anchor = .centre) -> CGFloat {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return 1 }

        let scale = max(rect.width / size.width, rect.height / size.height)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        image.draw(
            in: NSRect(
                x: rect.midX - drawn.width / 2,
                y: anchor == .top ? rect.minY : rect.midY - drawn.height / 2,
                width: drawn.width,
                height: drawn.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        return scale
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

    // MARK: - Loading

    private static func image(at url: URL) -> NSImage? {
        if let cached = imageCache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// First frame of a background, keyed if the theme asked for it.
    ///
    /// Loaded through `AnimatedImage` so the preview gets the same keyed pixels
    /// the panel does — a skin whose green screen is removed at runtime must not
    /// show up green here. The cap insets those frames carry would nine-slice on
    /// draw, so the frame is re-wrapped as a plain image first.
    private static func still(_ background: BackgroundImage) -> NSImage? {
        guard let frame = AnimatedImage.load(background)?.frames.first else { return nil }
        var rect = NSRect(origin: .zero, size: frame.size)
        guard let cgImage = frame.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: frame.size)
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let output = NSImage(size: image.size)
        output.lockFocus()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        output.unlockFocus()
        return output
    }

    static func clearCache() {
        imageCache.removeAllObjects()
    }
}
