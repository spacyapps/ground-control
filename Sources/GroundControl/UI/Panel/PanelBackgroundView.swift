// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The panel's themed content: title bar and session list.
///
/// Owns the whole surface so the theme reaches the window's edges — macOS
/// chrome is switched off in `FloatingPanel`, and this is what replaces it.
final class PanelBackgroundView: NSView {
    let titleBar = TitleBarView()
    let list = SessionListView()
    let skinOverlay = SkinOverlayView()

    var theme: Theme = DefaultTheme.theme

    /// The silhouette rendered at the current size.
    ///
    /// Kept as a bitmap rather than sampled from the source image because the
    /// shape is nine-sliced: a point on screen does not map linearly back to a
    /// pixel in the file once the edges have stretched. Rendering once per
    /// resize and sampling that is both simpler and exact.
    /// Readable by tests: it is what decides both what shows and what takes a
    /// click, and it has been wrong twice.
    var shapeMask: NSBitmapImageRep?

    /// The panel's body for an overlay skin: the area the frame encloses,
    /// painted so the rows have something to sit on. Clipped to that area
    /// rather than filling the layer, because an animated frame leaves gaps
    /// around itself where a full fill would show as a dark fringe.
    var interiorBody: NSImage?

    /// The silhouette rebuild is the 44-frame composite; the body is a cheap
    /// re-clip of it. So the silhouette is kept and only redone when the panel
    /// resizes, while the body follows the rows on every session change.
    var maskedSize: NSSize = .zero
    var enclosedArea: [Bool] = []

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
        // A skin covers the panel it decorates. The two controls and the hint
        // that labels them are no longer subviews here at all — see
        // `PanelRootView`, which owns them outside this view's shape mask.
        addSubview(skinOverlay)
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
        maskedSize = .zero
        enclosedArea = []
        // Force a restart rather than letting an already-running timer look
        // valid: without this, switching between two animated themes mid-
        // session kept the *previous* theme's frame-rate interval and elapsed
        // clock, since updateAnimation() only creates a new timer when one
        // isn't already running. Fixed 2026-08-26.
        animationTimer?.invalidate()
        animationTimer = nil
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
        skinOverlay.apply(theme: theme)
        needsDisplay = true
    }

    /// Height at which nothing is clipped: title strip, every row, and the
    /// frame the theme asked to keep clear.
    var desiredHeight: CGFloat {
        let insets = effectiveInsets
        return titleBar.preferredHeight + list.contentHeight + insets.top + insets.bottom
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
    var artworkScale: CGFloat {
        theme.window.artworkScale(atPanelWidth: bounds.width)
    }

    var effectiveInsets: NSEdgeInsets {
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
        // Everything sits inside the inset, so a framed background shows all
        // the way round rather than only above the first row.
        let insets = effectiveInsets
        let width = max(0, bounds.width - insets.left - insets.right)

        titleBar.frame = NSRect(
            x: insets.left,
            y: insets.top,
            width: width,
            height: titleBar.preferredHeight
        )
        list.frame = NSRect(
            x: insets.left,
            y: titleBar.frame.maxY,
            width: width,
            height: max(0, bounds.height - titleBar.frame.maxY - insets.bottom)
        )

        // After the list has its frame — the body is cut to where the rows
        // actually sit.
        updateShapeMask()

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
    }

    /// Where the close mark belongs, in this view's own coordinate space —
    /// read by `PanelRootView`, which owns the mark itself now that it needs
    /// to sit outside this view's shape mask.
    var closeMarkFrame: NSRect {
        NSRect(
            x: titleBar.frame.minX + TitleBarView.markInset,
            y: titleBar.frame.minY + TitleBarView.markTop,
            width: CloseMarkView.size.width,
            height: CloseMarkView.size.height
        )
    }

    /// The resize grip's counterpart to `closeMarkFrame`.
    var resizeGripFrame: NSRect {
        let grip = ResizeGripView.size
        return NSRect(
            x: max(effectiveInsets.left, titleBar.frame.maxX - TitleBarView.markInset - grip.width),
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

    /// Which of the two surfaces draws the animation, and therefore the only
    /// one worth invalidating on a frame.
    ///
    /// With `window.overlay`, `SkinOverlayView` draws the moving skin and this
    /// view draws `interiorBody` — a cached still that does not take `elapsed`
    /// at all. Without it, the reverse: this view animates and the overlay is
    /// hidden. Either way exactly one of them changes, and both were being
    /// marked dirty.
    var overlayOwnsAnimation: Bool {
        theme.window.drawsOverContent && theme.window.shape != nil
    }

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
            guard let self else { return }
            // Only the surface that actually draws the moving picture. Marking
            // both meant a full-bounds image blit twenty times a second for
            // something that never changed — see `overlayOwnsAnimation`.
            if self.overlayOwnsAnimation {
                self.skinOverlay.needsDisplay = true
            } else {
                self.needsDisplay = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }
}
