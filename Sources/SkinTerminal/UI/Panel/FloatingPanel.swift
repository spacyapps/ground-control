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

        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
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
