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
        layer?.cornerRadius = cornerRadius
        playerLayer?.frame = bounds

        // Drawn symbols are line art and need room inside the plate or they
        // read as a heavy block. Theme artwork is composed to fill its tile,
        // so it gets the whole area.
        let padding: CGFloat = asset == nil ? bounds.width * 0.20 : 0
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
        if window == nil { player?.pause() } else { player?.play() }
    }

    /// `asset` is the theme's artwork for this state, if it supplied any.
    /// When it did not, the built-in symbol for `state` is drawn tinted.
    func configure(asset: Theme.Avatar.Asset?, state: SessionState, theme: Theme) {
        self.theme = theme
        self.cornerRadius = theme.avatar.cornerRadius
        layer?.cornerRadius = cornerRadius
        imageView.contentTintColor = theme.colors.color(for: state)
        applyButtonChrome()

        guard asset != self.asset || state != drawnState else { return }
        self.asset = asset
        self.drawnState = state
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
