import AppKit

/// The state indicator: a filled dot in the state's colour.
///
/// `needsAction` is the loud case — it fills solid in the theme's needsAction
/// colour. Quiet states draw dimmer so a panel of idle rows stays calm.
final class StatusDotView: NSView {
    var color: NSColor = DefaultTheme.colors.idle {
        didSet { needsDisplay = true }
    }

    var isProminent = false {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 10, height: 10) }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let rect = NSRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        color.withAlphaComponent(isProminent ? 1.0 : 0.55).setFill()
        path.fill()
    }
}
