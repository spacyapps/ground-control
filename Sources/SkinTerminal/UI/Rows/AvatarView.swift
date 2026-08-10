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
    private static let spinKey = "skinterminal.spin"

    /// Decoded images are reused across rows and state flips — the same few
    /// files are asked for constantly.
    private static let imageCache = NSCache<NSURL, NSImage>()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.autoresizingMask = [.width, .height]
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
    }

    /// Pausing on removal matters: rows are rebuilt on every store change, so
    /// orphaned players would otherwise keep decoding forever.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { player?.pause() } else { player?.play() }
    }

    /// `asset` is the theme's artwork for this state, if it supplied any.
    /// When it did not, the built-in symbol for `state` is drawn in `tint`.
    func configure(asset: Theme.Avatar.Asset?,
                   state: SessionState,
                   tint: NSColor,
                   cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        layer?.cornerRadius = cornerRadius
        imageView.contentTintColor = tint

        guard asset != self.asset || (asset == nil && state != drawnState) else { return }
        self.asset = asset
        self.drawnState = asset == nil ? state : nil

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
        imageView.isHidden = false
        imageView.image = DrawnAvatar.symbol(for: state)
        // Motion is what separates "thinking" from "stopped" at a glance, and
        // a layer rotation costs nothing next to decoding video.
        if DrawnAvatar.isAnimated(state) { startSpin() } else { stopSpin() }
    }

    private func show(imageAt url: URL) {
        teardownPlayer()
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
