// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The panel's own tooltip.
///
/// AppKit's tooltips never appear here. They are shown only for the active
/// application, and this one is an accessory whose panel is deliberately
/// non-activating — clicking a row must not steal focus from the terminal you
/// are watching, which is the whole point of the window. So `toolTip` is set,
/// and silently does nothing.
///
/// Drawn inside our own window instead, where no such rule applies.
final class HintView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var theme: Theme = DefaultTheme.theme
    private var pending: DispatchWorkItem?

    override var isFlipped: Bool { true }

    /// Never takes a click: it appears under the pointer, and swallowing the
    /// click of the very control it describes would be a cruel joke.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        isHidden = true

        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HintView is created in code only")
    }

    func apply(theme: Theme) {
        self.theme = theme
        layer?.backgroundColor = theme.colors.titleBarBackground.withAlphaComponent(0.97).cgColor
        layer?.borderColor = theme.colors.messageDim.withAlphaComponent(0.45).cgColor
        label.textColor = theme.colors.titleBarText
        needsLayout = true
    }

    /// Shows `text` beside `anchor`, or hides after a short grace period when
    /// text is nil.
    ///
    /// The delay on appearing is what keeps a list from flickering hints as the
    /// pointer crosses it; the delay on hiding is what stops one blinking when
    /// the pointer moves a pixel inside the same control.
    func show(_ text: String?, near anchor: NSRect, in container: NSView) {
        pending?.cancel()

        guard let text, !text.isEmpty else {
            let hide = DispatchWorkItem { [weak self] in self?.isHidden = true }
            pending = hide
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: hide)
            return
        }

        let show = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.label.stringValue = text
            self.position(near: anchor, in: container)
            self.isHidden = false
        }
        pending = show
        // Immediate if one is already up: moving between two controls should
        // read as the hint following the pointer, not as two separate waits.
        DispatchQueue.main.asyncAfter(deadline: .now() + (isHidden ? 0.35 : 0), execute: show)
    }

    private func position(near anchor: NSRect, in container: NSView) {
        let padding = NSSize(width: 8, height: 4)
        let text = label.intrinsicContentSize
        let size = NSSize(
            width: min(text.width + padding.width * 2, container.bounds.width - 16),
            height: text.height + padding.height * 2
        )

        // Below the control by preference, above it when there is no room —
        // a hint that runs off the panel tells you nothing.
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 6)
        if origin.y + size.height > container.bounds.maxY - 4 {
            origin.y = anchor.minY - size.height - 6
        }
        origin.x = min(max(8, origin.x), max(8, container.bounds.maxX - size.width - 8))

        frame = NSRect(origin: origin, size: size)
        label.frame = NSRect(
            x: padding.width,
            y: padding.height,
            width: size.width - padding.width * 2,
            height: text.height
        )
    }
}
