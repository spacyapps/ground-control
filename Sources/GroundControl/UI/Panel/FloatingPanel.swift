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
        minSize = NSSize(width: 260, height: 120)

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

    /// Applies the two user-facing window behaviours (docs/SPEC.md §5).
    func apply(alwaysOnTop: Bool, showOnAllSpaces: Bool) {
        level = alwaysOnTop ? .floating : .normal
        collectionBehavior = showOnAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
    }
}
