// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The panel's themed content: title bar and session list.
///
/// Owns the whole surface so the theme reaches the window's edges — macOS
/// chrome is switched off in `FloatingPanel`, and this is what replaces it.
final class PanelBackgroundView: NSView {
    let titleBar = TitleBarView()
    let list = SessionListView()
    let resizeGrip = ResizeGripView()
    let skinOverlay = SkinOverlayView()
    let closeMark = CloseMarkView()
    let hint = HintView()

    private var theme: Theme = DefaultTheme.theme

    /// The silhouette rendered at the current size.
    ///
    /// Kept as a bitmap rather than sampled from the source image because the
    /// shape is nine-sliced: a point on screen does not map linearly back to a
    /// pixel in the file once the edges have stretched. Rendering once per
    /// resize and sampling that is both simpler and exact.
    /// Readable by tests: it is what decides both what shows and what takes a
    /// click, and it has been wrong twice.
    private(set) var shapeMask: NSBitmapImageRep?

    /// The panel's body for an overlay skin: the area the frame encloses,
    /// painted so the rows have something to sit on. Clipped to that area
    /// rather than filling the layer, because an animated frame leaves gaps
    /// around itself where a full fill would show as a dark fringe.
    private(set) var interiorBody: NSImage?

    /// Animated backgrounds play only while something is working.
    ///
    /// A full-panel redraw is a different order of cost from a 44pt avatar, and
    /// an always-on window animating forever is a battery drain you did not ask
    /// for. Freezing at rest also keeps the panel honest: motion means work,
    /// the same rule the analyser follows.
    private var animationTimer: Timer?
    private var animationStart = Date()
    private var isWorking = false

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        addSubview(titleBar)
        addSubview(list)
        // A skin covers the panel it decorates...
        addSubview(skinOverlay)
        // ...but never the two controls: marks, then frame, then panel.
        addSubview(resizeGrip)
        addSubview(closeMark)
        // Above even the marks: it describes them.
        addSubview(hint)
        list.onHint = { [weak self] text, rect in
            guard let self else { return }
            self.hint.show(text, near: self.list.convert(rect, to: self), in: self)
        }
        // The panel's own two controls answer to the same mechanism: they are
        // buttons in the same window, and AppKit's tooltips fail them equally.
        let showHint: (String?, NSRect) -> Void = { [weak self] text, rect in
            guard let self else { return }
            self.hint.show(text, near: rect, in: self)
        }
        closeMark.onHint = showHint
        resizeGrip.onHint = showHint
        skinOverlay.elapsed = { [weak self] in self?.currentElapsed }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PanelBackgroundView is created in code only")
    }

    func apply(theme: Theme) {
        self.theme = theme
        shapeMask = nil
        interiorBody = nil
        updateAnimation()
        layer?.cornerRadius = theme.window.isShaped ? 0 : 10
        needsLayout = true
        // A shaped panel has no rectangle to fill — `draw` already refuses to
        // paint one — and an opaque layer underneath contradicted that: where
        // an animated skin moved and left a frame's pixels transparent, the
        // background showed through as a black patch instead of nothing.
        layer?.backgroundColor = theme.window.isShaped
            ? NSColor.clear.cgColor
            : theme.colors.windowBackground.cgColor
        titleBar.apply(theme: theme)
        list.apply(theme: theme)
        resizeGrip.apply(theme: theme)
        closeMark.apply(theme: theme)
        hint.apply(theme: theme)
        skinOverlay.apply(theme: theme)
        needsDisplay = true
    }

    /// Height at which nothing is clipped: title strip, every row, and the
    /// frame the theme asked to keep clear.
    var desiredHeight: CGFloat {
        let insets = effectiveInsets
        return TitleBarView.height + list.contentHeight + insets.top + insets.bottom
    }

    /// `contentInset` measures where the frame ends in the artwork, so it is
    /// scaled wherever the artwork is.
    ///
    /// A locked skin is scaled bodily to the panel: its painted frame is 12% of
    /// the image whatever the panel's width, so a fixed number of points is
    /// correct at exactly one size and wrong everywhere else. Nine-slice draws
    /// its corners at natural size, so there the number needs no scaling.
    ///
    /// Capped either way: the intent ("hold the rows inside the frame") is
    /// right even when the number is not, so it is honoured as far as it fits
    /// rather than leaving the rows no room at all.
    private var artworkScale: CGFloat {
        theme.window.artworkScale(atPanelWidth: bounds.width)
    }

    private var effectiveInsets: NSEdgeInsets {
        let scale = artworkScale
        let declared = theme.layout.contentInset
        let room = min(bounds.width, bounds.height)
        let ceiling = room > 0 ? room * 0.32 : .greatestFiniteMagnitude
        func clamp(_ value: CGFloat) -> CGFloat { min(value * scale, ceiling) }
        return NSEdgeInsets(
            top: clamp(declared.top),
            left: clamp(declared.left),
            bottom: clamp(declared.bottom),
            right: clamp(declared.right)
        )
    }

    func refreshElapsed() {
        list.refreshElapsed()
    }

    func update(sessions: [Session], renames: [String: String]) {
        titleBar.update(sessions: sessions)
        list.apply(sessions: sessions, renames: renames)

        isWorking = sessions.contains { $0.state == .working }
        updateAnimation()
    }

    override func layout() {
        super.layout()
        updateShapeMask()
        // Everything sits inside the inset, so a framed background shows all
        // the way round rather than only above the first row.
        let insets = effectiveInsets
        let width = max(0, bounds.width - insets.left - insets.right)

        titleBar.frame = NSRect(
            x: insets.left,
            y: insets.top,
            width: width,
            height: TitleBarView.height
        )
        list.frame = NSRect(
            x: insets.left,
            y: titleBar.frame.maxY,
            width: width,
            height: max(0, bounds.height - titleBar.frame.maxY - insets.bottom)
        )

        // Top-right of the title strip, mirroring the close mark at its left
        // end. Both corner marks then sit on the same line, inside the inset,
        // on the artwork rather than out on the invisible window edge.
        // The title strip caps the block and the list closes it, so each rounds
        // only its own outer pair — rounding both fully would put a notch in
        // the seam where they meet.
        let radius = theme.layout.contentCornerRadius * artworkScale
        titleBar.wantsLayer = true
        list.wantsLayer = true
        titleBar.layer?.cornerRadius = radius
        list.layer?.cornerRadius = radius
        titleBar.layer?.masksToBounds = radius > 0
        list.layer?.masksToBounds = radius > 0
        // These views are flipped, so their layers are geometry-flipped with
        // them and minY is the visual top. Not verifiable offscreen: AppKit's
        // view capture draws through drawRect and omits layer-level rounding
        // entirely, so this one was checked on screen.
        titleBar.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        list.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        skinOverlay.frame = bounds

        closeMark.frame = NSRect(
            x: titleBar.frame.minX + TitleBarView.markInset,
            y: titleBar.frame.minY + TitleBarView.markTop,
            width: CloseMarkView.size.width,
            height: CloseMarkView.size.height
        )

        let grip = ResizeGripView.size
        resizeGrip.frame = NSRect(
            x: max(insets.left, titleBar.frame.maxX - TitleBarView.markInset - grip.width),
            y: titleBar.frame.minY + TitleBarView.markTop,
            width: grip.width,
            height: grip.height
        )
    }

    /// Nil unless something is working — animation is the signal for that, so
    /// a still panel draws frame one and stops.
    private var currentElapsed: TimeInterval? {
        animationTimer == nil ? nil : Date().timeIntervalSince(animationStart)
    }

    override func draw(_ dirtyRect: NSRect) {
        // A shaped panel has no rectangle to fill: the silhouette is the whole
        // window, and painting a background colour first would square it off
        // again.
        let elapsed = currentElapsed

        if let shape = theme.window.shape {
            // An overlay skin is drawn by SkinOverlayView after the rows; here
            // only its body goes down, so the rows have something to sit on.
            if theme.window.drawsOverContent {
                interiorBody?.draw(
                    in: bounds,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
            } else {
                BackgroundRenderer.draw(shape, in: bounds, elapsed: elapsed)
            }
            return
        }

        // Otherwise the colour goes down first, so a background image carrying
        // transparency composites onto it rather than onto nothing.
        theme.colors.windowBackground.setFill()
        bounds.fill()

        if let background = theme.backgrounds.window {
            BackgroundRenderer.draw(background, in: bounds, elapsed: elapsed)
        }
    }

    // MARK: - Animation

    private var animatedBackground: BackgroundImage? {
        let candidate = theme.window.shape ?? theme.backgrounds.window
        guard let candidate, BackgroundRenderer.isAnimated(candidate) else { return nil }
        return candidate
    }

    private func updateAnimation() {
        guard isWorking, window != nil, let background = animatedBackground else {
            animationTimer?.invalidate()
            animationTimer = nil
            needsDisplay = true
            skinOverlay.needsDisplay = true
            return
        }
        guard animationTimer == nil else { return }

        // Follow the file's own frame rate rather than a fixed tick: a slow
        // ambient loop should not be redrawn sixty times a second.
        let interval = AnimatedImage.load(background)?.duration ?? 1.0 / 12
        animationStart = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: max(0.05, interval), repeats: true) { [weak self] _ in
            self?.needsDisplay = true
            self?.skinOverlay.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    // MARK: - Shape

    /// Renders the silhouette at the current size and masks the content to it,
    /// so rows are cut to the outline instead of spilling past a curve.
    private func updateShapeMask() {
        guard let shape = theme.window.shape, bounds.width > 1, bounds.height > 1 else {
            layer?.mask = nil
            shapeMask = nil
            return
        }

        let size = NSSize(width: bounds.width, height: bounds.height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // Every frame, drawn over itself. A mask only removes, so a silhouette
        // taken from frame one clips whatever a later frame moves into — and
        // swallows clicks where the art has since moved away. Compositing the
        // frames unions their coverage, which is the shape the skin occupies
        // over its whole loop.
        if let animated = AnimatedImage.load(shape), animated.isAnimated {
            for index in 0..<animated.frames.count {
                BackgroundRenderer.draw(
                    shape,
                    in: NSRect(origin: .zero, size: size),
                    elapsed: Double(index) * animated.duration
                )
            }
        } else {
            BackgroundRenderer.draw(shape, in: NSRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()

        // An overlay skin's middle is transparent by design, which would
        // otherwise mask away the very rows it is meant to frame.
        if theme.window.drawsOverContent {
            let enclosed = SkinInterior.fillEnclosed(in: rep)
            interiorBody = SkinInterior.body(
                from: enclosed,
                width: rep.pixelsWide,
                height: rep.pixelsHigh,
                colour: theme.colors.windowBackground
            )
        } else {
            interiorBody = nil
        }

        shapeMask = rep

        let mask = CALayer()
        mask.frame = bounds
        mask.contents = rep.cgImage
        layer?.mask = mask
        window?.invalidateShadow()
    }

    /// Lets clicks fall through transparent parts of a skin.
    ///
    /// Without this a shaped panel is still an invisible rectangle as far as
    /// the mouse is concerned, swallowing clicks meant for whatever is behind
    /// it — the most irritating way a skinned window can misbehave.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard theme.window.isShaped, let mask = shapeMask else {
            return super.hitTest(point)
        }

        let local = convert(point, from: superview)
        let column = Int(local.x)
        let row = Int(isFlipped ? local.y : bounds.height - local.y)
        guard column >= 0, row >= 0,
              column < mask.pixelsWide, row < mask.pixelsHigh else { return nil }

        let alpha = mask.colorAt(x: column, y: row)?.alphaComponent ?? 0
        return alpha > 0.08 ? super.hitTest(point) : nil
    }
}
