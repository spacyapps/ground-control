// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit
import AVFoundation

/// Up to four independent pieces of art, one per panel corner, each at its
/// own natural size — never resized, never sliced, never clipped to
/// anything but the window's own bounds.
///
/// Sits in `PanelRootView` above `chrome` and below the close/resize marks —
/// see that file's doc comment for why it lives outside chrome's shape mask.
/// Animation (gif frames or video) plays only while `isWorking` is true, the
/// same "motion means work" rule the rest of the panel already follows; a
/// still panel freezes every corner on its resting frame.
final class CornerDecorationsView: NSView {
    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        var isRight: Bool { self == .topRight || self == .bottomRight }
        var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
    }

    /// A video's pixel size is not known until its asset loads, unlike an
    /// image's — so its layer starts at zero size and is repositioned once
    /// `naturalSize` arrives.
    private final class VideoState {
        let player: AVPlayer
        let layer: AVPlayerLayer
        var loopObserver: NSObjectProtocol?
        var naturalSize: NSSize?
        let offset: CGSize
        let scale: CGFloat

        init(player: AVPlayer, layer: AVPlayerLayer, offset: CGSize, scale: CGFloat) {
            self.player = player
            self.layer = layer
            self.offset = offset
            self.scale = scale
        }
    }

    private var decorations: Theme.CornerDecorations = .none
    private var videoStates: [Corner: VideoState] = [:]

    private var isWorking = false
    private var animationTimer: Timer?
    private var animationStart = Date()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CornerDecorationsView is created in code only")
    }

    deinit {
        for state in videoStates.values { teardown(state) }
    }

    /// Decoration is never a click target — the same rule `SkinOverlayView`
    /// follows, for the same reason: it can sit over anything, including a
    /// row, and must never steal a click meant for what is underneath it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(theme: Theme) {
        decorations = theme.cornerDecorations
        rebuildVideoStates()
        // Force updateAnimation() to restart the clock rather than treating
        // an already-running timer as still valid: without this, switching
        // corner-decoration themes mid-session (isWorking staying true the
        // whole time) left the new theme's clip picking up wherever the old
        // one's elapsed time had reached, instead of starting at its own
        // resting frame. Fixed 2026-08-26.
        animationTimer?.invalidate()
        animationTimer = nil
        updateAnimation()
        needsLayout = true
        needsDisplay = true
    }

    /// The one animation trigger for every corner: motion only while
    /// something is actually working, matching the rest of the panel.
    func update(isWorking: Bool) {
        guard isWorking != self.isWorking else { return }
        self.isWorking = isWorking
        updateAnimation()
        for state in videoStates.values {
            if isWorking {
                if window != nil { state.player.play() }
            } else {
                state.player.pause()
                state.player.seek(to: .zero)
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
        for state in videoStates.values {
            if window == nil {
                state.player.pause()
            } else if isWorking {
                state.player.play()
            }
        }
    }

    override func layout() {
        super.layout()
        for corner in Corner.allCases {
            guard let state = videoStates[corner] else { continue }
            let natural = state.naturalSize ?? .zero
            let size = NSSize(width: natural.width * state.scale, height: natural.height * state.scale)
            state.layer.frame = NSRect(origin: origin(for: corner, size: size, offset: state.offset), size: size)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let elapsed = currentElapsed
        for corner in Corner.allCases {
            guard let decoration = decoration(at: corner),
                  case .image(let background) = decoration.asset,
                  let natural = BackgroundRenderer.naturalSize(of: background) else { continue }
            let size = NSSize(width: natural.width * decoration.scale, height: natural.height * decoration.scale)
            let point = origin(for: corner, size: size, offset: decoration.offset)
            BackgroundRenderer.drawAnchored(background, at: point, size: size, elapsed: elapsed)
        }
    }

    // MARK: - Geometry

    private func decoration(at corner: Corner) -> Theme.CornerDecoration? {
        switch corner {
        case .topLeft: return decorations.topLeft
        case .topRight: return decorations.topRight
        case .bottomLeft: return decorations.bottomLeft
        case .bottomRight: return decorations.bottomRight
        }
    }

    /// Where the given size's own corner lands: the matching edge of the
    /// artwork sits at this view's corner, plus the theme's offset — screen
    /// direction, x right, y down, the same at every corner.
    private func origin(for corner: Corner, size: NSSize, offset: CGSize) -> NSPoint {
        let x = (corner.isRight ? bounds.width - size.width : 0) + offset.width
        let y = (corner.isBottom ? bounds.height - size.height : 0) + offset.height
        return NSPoint(x: x, y: y)
    }

    // MARK: - Gif/still animation

    private var hasAnimatedImageDecoration: Bool {
        Corner.allCases.contains { corner in
            guard case .image(let background)? = decoration(at: corner)?.asset else { return false }
            return BackgroundRenderer.isAnimated(background)
        }
    }

    private var currentElapsed: TimeInterval? {
        animationTimer == nil ? nil : Date().timeIntervalSince(animationStart)
    }

    private func updateAnimation() {
        guard isWorking, window != nil, hasAnimatedImageDecoration else {
            animationTimer?.invalidate()
            animationTimer = nil
            needsDisplay = true
            return
        }
        guard animationTimer == nil else { return }

        animationStart = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    // MARK: - Video

    private func rebuildVideoStates() {
        var next: [Corner: VideoState] = [:]
        for corner in Corner.allCases {
            guard let decoration = decoration(at: corner),
                  case .video(let url, let loop, let muted) = decoration.asset else { continue }

            // Reuse the existing player rather than restarting playback on
            // every theme re-apply — hot-reload must not make a video corner
            // stutter back to its first frame each time a colour is tweaked.
            if let existing = videoStates[corner],
               (existing.player.currentItem?.asset as? AVURLAsset)?.url == url,
               existing.scale == decoration.scale {
                next[corner] = existing
                continue
            }
            next[corner] = makeVideoState(
                url: url, loop: loop, muted: muted,
                offset: decoration.offset, scale: decoration.scale
            )
        }

        for (corner, state) in videoStates where next[corner] !== state {
            teardown(state)
        }
        videoStates = next
    }

    private func makeVideoState(url: URL, loop: Bool, muted: Bool, offset: CGSize, scale: CGFloat) -> VideoState {
        let player = AVPlayer(url: url)
        player.isMuted = muted
        player.actionAtItemEnd = loop ? .none : .pause

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resize
        self.layer?.addSublayer(layer)

        let state = VideoState(player: player, layer: layer, offset: offset, scale: scale)

        if loop {
            state.loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                if player?.rate != 0 { player?.play() }
            }
        }

        Task { @MainActor [weak self, weak state] in
            guard let asset = player.currentItem?.asset,
                  let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize) else { return }
            state?.naturalSize = size
            self?.needsLayout = true
        }

        return state
    }

    private func teardown(_ state: VideoState) {
        if let observer = state.loopObserver { NotificationCenter.default.removeObserver(observer) }
        state.player.pause()
        state.layer.removeFromSuperlayer()
    }
}
