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
    private var cornerRadius: CGFloat = 8

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

    func configure(asset: Theme.Avatar.Asset?, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        layer?.cornerRadius = cornerRadius

        guard asset != self.asset else { return }
        self.asset = asset

        switch asset {
        case .none:
            showNothing()
        case .image(let url):
            show(imageAt: url)
        case .video(let url, let loop, let muted):
            show(videoAt: url, loop: loop, muted: muted)
        }
    }

    // MARK: - Backends

    private func showNothing() {
        imageView.isHidden = true
        imageView.image = nil
        teardownPlayer()
    }

    private func show(imageAt url: URL) {
        teardownPlayer()
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
