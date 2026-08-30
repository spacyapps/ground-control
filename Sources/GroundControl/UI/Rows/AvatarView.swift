// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import AVFoundation

/// The per-state face: a still, an animated GIF/APNG, or looping video.
///
/// Both backends are kept alive but only one is ever visible, so switching
/// state does not rebuild layers. Video is paused whenever the view is off
/// screen — an always-on panel playing video in the background is the GPU cost
/// docs/SPEC.md §10 warns about, and pausing is the cheap mitigation.
final class AvatarView: NSView {
    private let imageView = NSImageView()
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: NSObjectProtocol?

    private var asset: Theme.Avatar.Asset?
    private var drawnState: SessionState?
    /// Set while showing the split "we don't know which state" face, so the
    /// same pair does not recomposite on every row rebuild.
    private var splitPair: (SessionState, SessionState)?
    private var cornerRadius: CGFloat = 8
    private var theme: Theme = DefaultTheme.theme
    private var isHovering = false
    private var trackingArea: NSTrackingArea?
    private static let spinKey = "groundcontrol.spin"
    private var gears: CALayer?
    private var gearBox: NSSize?
    private var gearColour: NSColor?

    /// Decoded images are reused across rows and state flips — the same few
    /// files are asked for constantly.
    private static let imageCache = NSCache<NSURL, NSImage>()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.frame = bounds
        imageView.wantsLayer = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AvatarView is created in code only")
    }

    deinit {
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        player?.pause()
    }

    override func layout() {
        super.layout()
        // The split "we don't know" face is almost a circle — corners far
        // rounder than any theme's, so it reads as its own thing at a glance.
        layer?.cornerRadius = splitPair == nil
            ? cornerRadius
            : min(bounds.width, bounds.height) * 0.42
        playerLayer?.frame = bounds

        // Drawn symbols are line art and need room inside the plate or they
        // read as a heavy block. Theme artwork is composed to fill its tile,
        // so it gets the whole area.
        // The split face is composed to fill its tile, like theme artwork —
        // only a bare drawn symbol needs breathing room inside the plate.
        let padding: CGFloat = (asset == nil && splitPair == nil) ? bounds.width * 0.20 : 0
        let box = bounds.insetBy(dx: padding, dy: padding)
        imageView.frame = box
        layoutGears(in: box)
    }

    /// The avatar is the row's most obvious hit target, so it is dressed as a
    /// button: a plate, a hairline, and a lift on hover. Without this nothing
    /// in the panel looks pressable at all.
    private func applyButtonChrome() {
        layer?.backgroundColor = isHovering
            ? theme.colors.rowBackgroundHover.cgColor
            : theme.colors.rowBackgroundAlt.withAlphaComponent(0.65).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = isHovering
            ? theme.colors.color(for: drawnState ?? .idle).withAlphaComponent(0.9).cgColor
            : theme.colors.messageDim.withAlphaComponent(0.35).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.pointingHand.push()
        applyButtonChrome()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.pop()
        applyButtonChrome()
    }

    /// Pausing on removal matters: rows are rebuilt on every store change, so
    /// orphaned players would otherwise keep decoding forever.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            player?.pause()
        } else {
            player?.play()
            // The seam froze while the panel was hidden — catch it up.
            if splitPair != nil { renderSplitFace() }
        }
    }

    /// `asset` is the theme's artwork for this state, if it supplied any.
    /// When it did not, the built-in symbol for `state` is drawn tinted.
    func configure(asset: Theme.Avatar.Asset?, state: SessionState, theme: Theme) {
        self.theme = theme
        self.cornerRadius = theme.avatar.cornerRadius
        layer?.cornerRadius = cornerRadius
        imageView.contentTintColor = theme.colors.color(for: state)
        applyButtonChrome()

        guard asset != self.asset || state != drawnState || splitPair != nil else { return }
        self.asset = asset
        self.drawnState = state
        self.splitPair = nil
        needsLayout = true

        switch asset {
        case .none:
            showDrawnDefault(for: state)
        case .image(let url):
            show(imageAt: url)
        case .video(let url, let loop, let muted):
            show(videoAt: url, loop: loop, muted: muted)
        }
    }

    /// The "we don't know which" face: the `left` state's still on one half,
    /// the `right` state's on the other. A composite still, never animated —
    /// it is an admission, not a state (docs/GROK-BOT-GROUPING.md).
    func configureSplit(left: SessionState, right: SessionState, theme: Theme) {
        self.theme = theme
        self.cornerRadius = theme.avatar.cornerRadius
        layer?.cornerRadius = cornerRadius
        applyButtonChrome()

        let unchanged = splitPair.map { $0 == (left, right) } ?? false
        splitPair = (left, right)
        asset = nil
        drawnState = nil

        teardownPlayer()
        teardownGears()
        stopSpin()
        imageView.isHidden = false
        imageView.contentTintColor = nil
        renderSplitFace()
        // The pair did not change, so nothing about the layout did either —
        // only the seam angle, which `renderSplitFace` already refreshed.
        if !unchanged { needsLayout = true }
    }

    private func renderSplitFace() {
        guard let (left, right) = splitPair else { return }
        imageView.image = Self.splitFace(
            left: left, right: right, theme: theme, angle: Self.clockSeamAngle()
        )
    }

    /// Re-strikes the seam at the current clock angle. Cheap no-op unless this
    /// avatar is showing the split. Driven by the row's elapsed tick.
    func tickSplitSeam() {
        guard splitPair != nil, window != nil else { return }
        renderSplitFace()
    }

    /// Where the seam points: a clock's minute hand, one full turn an hour.
    /// It moves because "we don't know" is a live guess, not a resting state —
    /// docs/GROK-BOT-GROUPING.md.
    static func clockSeamAngle(_ date: Date = Date()) -> CGFloat {
        let seconds = date.timeIntervalSince(Calendar.current.startOfDay(for: date))
        let intoHour = seconds.truncatingRemainder(dividingBy: 3600)
        return CGFloat(intoHour / 3600) * 2 * .pi
    }

    static func splitFace(left: SessionState,
                          right: SessionState,
                          theme: Theme,
                          angle: CGFloat) -> NSImage {
        let side = max(1, theme.avatar.size)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let centre = NSPoint(x: rect.midX, y: rect.midY)
            let reach = rect.width * 4
            let along = NSPoint(x: cos(angle), y: sin(angle))       // the seam's direction
            let across = NSPoint(x: -sin(angle), y: cos(angle))     // its normal

            for (state, sign) in [(left, CGFloat(1)), (right, CGFloat(-1))] {
                NSGraphicsContext.current?.saveGraphicsState()
                // The half-plane on one side of the seam, as a big quad.
                let ends = (NSPoint(x: centre.x - along.x * reach, y: centre.y - along.y * reach),
                            NSPoint(x: centre.x + along.x * reach, y: centre.y + along.y * reach))
                let half = NSBezierPath()
                half.move(to: ends.0)
                half.line(to: ends.1)
                half.line(to: NSPoint(x: ends.1.x + across.x * reach * sign,
                                      y: ends.1.y + across.y * reach * sign))
                half.line(to: NSPoint(x: ends.0.x + across.x * reach * sign,
                                      y: ends.0.y + across.y * reach * sign))
                half.close()
                half.addClip()
                face(for: state, theme: theme)?.draw(in: rect)
                NSGraphicsContext.current?.restoreGraphicsState()
            }

            // The seam itself — a diameter at `angle`. `messageDim` is the
            // avatar's own border colour, so the line belongs to the plate
            // rather than sitting on the artwork like the old white one did.
            let seam = NSBezierPath()
            seam.lineWidth = max(2, rect.width * 0.05)
            seam.move(to: NSPoint(x: centre.x - along.x * reach, y: centre.y - along.y * reach))
            seam.line(to: NSPoint(x: centre.x + along.x * reach, y: centre.y + along.y * reach))
            theme.colors.messageDim.withAlphaComponent(0.75).setStroke()
            seam.stroke()
            return true
        }
    }

    /// One state's face as a plain image — the theme's still, or the built-in
    /// symbol tinted and inset the way `layout()` insets a drawn avatar.
    private static func face(for state: SessionState, theme: Theme) -> NSImage? {
        switch theme.avatar.asset(for: state) {
        case .image(let url):
            return imageCache.object(forKey: url as NSURL) ?? NSImage(contentsOf: url)
        case .video, .none:
            guard let symbol = DrawnAvatar.symbol(for: state) else { return nil }
            let colour = theme.colors.color(for: state)
            let tinted = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [colour])
            ) ?? symbol
            return NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
                tinted.draw(in: rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.2))
                return true
            }
        }
    }

    // MARK: - Backends

    private func showDrawnDefault(for state: SessionState) {
        teardownPlayer()
        stopSpin()
        // Motion is what separates "thinking" from "stopped" at a glance, and
        // layer rotation costs nothing next to decoding video.
        if DrawnAvatar.isAnimated(state) {
            imageView.isHidden = true
            imageView.image = nil
            needsLayout = true
            return
        }
        teardownGears()
        imageView.isHidden = false
        imageView.image = DrawnAvatar.symbol(for: state)
    }

    // MARK: - Gears

    /// Built for one size and rebuilt when that changes, because the wheels are
    /// positioned in points rather than scaled — a train stretched to fit would
    /// mesh at one size and slide at every other.
    private func layoutGears(in box: NSRect) {
        guard let state = drawnState, DrawnAvatar.isAnimated(state), asset == nil else {
            teardownGears()
            return
        }
        let colour = theme.colors.color(for: state)
        if gears != nil, gearBox == box.size, gearColour == colour { return }

        teardownGears()
        let train = GearTrain.layer(size: box.size, colour: colour)
        // bounds and position, never frame: frame is derived from the transform,
        // so writing it back to a rotating layer re-derives bounds from a
        // rotated bounding box. That is what made the old single gear collapse.
        train.position = CGPoint(x: box.midX, y: box.midY)
        layer?.addSublayer(train)
        gears = train
        gearBox = box.size
        gearColour = colour
    }

    private func teardownGears() {
        gears?.removeFromSuperlayer()
        gears = nil
        gearBox = nil
        gearColour = nil
    }

    private func show(imageAt url: URL) {
        teardownPlayer()
        teardownGears()
        stopSpin()
        imageView.isHidden = false

        if let cached = Self.imageCache.object(forKey: url as NSURL) {
            imageView.image = cached
            return
        }
        guard let image = NSImage(contentsOf: url) else {
            Log.theming.notice("Could not decode avatar \(url.lastPathComponent, privacy: .public)")
            imageView.isHidden = true
            return
        }
        Self.imageCache.setObject(image, forKey: url as NSURL)
        imageView.image = image
    }

    private func show(videoAt url: URL, loop: Bool, muted: Bool) {
        imageView.isHidden = true
        imageView.image = nil
        stopSpin()
        teardownPlayer()

        let player = AVPlayer(url: url)
        player.isMuted = muted
        player.actionAtItemEnd = loop ? .none : .pause

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = bounds
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)

        if loop {
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        self.player = player
        self.playerLayer = playerLayer
        if window != nil { player.play() }
    }

    // MARK: - Spin

    private func startSpin() {
        guard let layer = imageView.layer, layer.animation(forKey: Self.spinKey) == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -Double.pi * 2
        spin.duration = 3.2
        spin.repeatCount = .infinity
        // Survives the panel being hidden and re-shown.
        spin.isRemovedOnCompletion = false
        layer.add(spin, forKey: Self.spinKey)
    }

    private func stopSpin() {
        imageView.layer?.removeAnimation(forKey: Self.spinKey)
    }

    private func teardownPlayer() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }
}
