// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The panel itself.
///
/// `.nonactivating` is the whole point: clicking a row must never steal focus
/// from the terminal you are watching (docs/SPEC.md §5). It also accepts key
/// events despite being borderless, so ⌘W works.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        minSize = Self.smallest

        // The theme owns every pixel, so macOS chrome is switched off entirely
        // and TitleBarView takes over the title and the drag handle. The
        // window stays `.titled` purely to keep live resizing.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A shaped theme needs the system to stop drawing a window at all.
    ///
    /// `.titled` is what forces a rectangle with system corners, so a skin can
    /// never exceed it. Borderless gives a window with no shape of its own —
    /// whatever the content draws *is* the window. The cost is the resize
    /// control and the title bar, which is why a shaped theme has to supply its
    /// own way to move and close the panel.
    /// Two rows and a title strip: below this nothing is readable, whatever the
    /// theme thinks.
    static let smallest = NSSize(width: 260, height: 120)

    /// Raises the floor to whatever the current theme's corners need, and
    /// grows the panel if it is already below it.
    ///
    /// Both the resize drag and the height fit clamp to `minSize`, so this is
    /// the only place that has to know: a theme with 94pt caps cannot be shown
    /// in the 120pt-high panel the previous theme left behind.
    func enforce(minimum wanted: NSSize) {
        minSize = NSSize(
            width: max(Self.smallest.width, wanted.width),
            height: max(Self.smallest.height, wanted.height)
        )
        guard frame.width < minSize.width || frame.height < minSize.height else { return }

        // Pinned at the top, like every other resize here — AppKit measures
        // from the bottom, so the origin moves as the height changes.
        var grown = frame
        let top = grown.maxY
        grown.size = NSSize(width: max(frame.width, minSize.width),
                            height: max(frame.height, minSize.height))
        grown.origin.y = top - grown.height
        setFrame(grown, display: true, animate: false)
    }

    func apply(shaped: Bool) {
        let wanted: NSWindow.StyleMask = shaped
            ? [.nonactivatingPanel, .borderless]
            : [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView]
        guard styleMask != wanted else { return }

        styleMask = wanted
        isMovableByWindowBackground = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        // The shadow is derived from opaque content, so it has to be recomputed
        // whenever the silhouette changes or a rectangular ghost remains.
        invalidateShadow()
    }

    /// Applies the two user-facing window behaviours (docs/SPEC.md §5).
    func apply(alwaysOnTop: Bool, showOnAllSpaces: Bool) {
        level = alwaysOnTop ? .floating : .normal
        collectionBehavior = showOnAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
    }
}
