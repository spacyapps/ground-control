// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// A heading with a link under it, for the Hooks menu.
///
/// Built to sit in the same column as `HookMenuRow`: the heading starts where
/// their names start, and the link is indented beneath it the way their detail
/// lines are, so it reads as one more entry in the list instead of a stray line
/// at the menu's edge. There is no switch, because there is nothing to switch —
/// the app only points at where to read — so the switch's column carries an icon
/// instead.
final class MenuLinkRow: NSView {
    /// Exposed so a test can read what the row says and where it goes.
    let linkButton = LinkButton()
    private let heading = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let onOpen: () -> Void

    init(
        width: CGFloat,
        heading title: String,
        symbol: String,
        link: String,
        toolTip: String?,
        onOpen: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        super.init(frame: .zero)

        heading.font = .menuFont(ofSize: 13)
        heading.textColor = .labelColor
        heading.stringValue = title

        linkButton.isBordered = false
        linkButton.alignment = .left
        linkButton.focusRingType = .none
        linkButton.attributedTitle = NSAttributedString(string: link, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.linkColor
        ])
        linkButton.toolTip = toolTip
        linkButton.target = self
        linkButton.action = #selector(open)

        // Pale green, the meter's own outline colour. Palette-coloured because a
        // template symbol ignores a tint and comes out the menu's grey.
        let tint = NSColor(srgbRed: 0.56, green: 0.78, blue: 0.60, alpha: 1)
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(config)

        for view in [icon, heading, linkButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // The heading's left edge is where `HookMenuRow` puts its names: its
        // 20pt inset, the switch, and the 10pt gap after it.
        let textLeading = 20 + HookSwitch.size.width + 10
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 20 + HookSwitch.size.width / 2),
            icon.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading),
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            linkButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading),
            linkButton.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 2),
            linkButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            widthAnchor.constraint(equalToConstant: width)
        ])

        // A menu sizes an item from its view's frame and never lays one out
        // itself — see HookMenuRow for the afternoon that cost.
        layoutSubtreeIfNeeded()
        frame = NSRect(origin: .zero, size: NSSize(width: width, height: fittingSize.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MenuLinkRow is created in code only")
    }

    /// Open first, then close the menu: a view in a menu does not dismiss it
    /// the way a plain item does.
    @objc private func open() {
        onOpen()
        enclosingMenuItem?.menu?.cancelTracking()
    }

    /// A borderless button that shows the pointing hand, so it reads as a link.
    final class LinkButton: NSButton {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}
