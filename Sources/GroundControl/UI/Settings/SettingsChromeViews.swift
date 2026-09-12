// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The pieces every section is built from: the brand lockup, a section header,
/// the preview's frame, and the row of theme buttons.
///
/// Split from `SettingsView` for the same reason `SettingsSections` was — that
/// file is about what the window contains and what it does when clicked, and
/// the drawing of its furniture kept crowding both out.
extension SettingsView {
    /// The app's own mark and a way back to whoever made it. Settings is a
    /// system surface, so unlike the panel no theme ever replaces this.
    func brandRow() -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2

        let mark = NSImageView()
        mark.image = Brand.lockup
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 190),
            mark.heightAnchor.constraint(equalToConstant: 52)
        ])

        column.addArrangedSubview(mark)
        column.addArrangedSubview(websiteLink())
        column.addArrangedSubview(versionLabel())
        return column
    }

    /// Version and build number, under the wordmark. Selectable so it can be
    /// copied straight into a bug report.
    func versionLabel() -> NSTextField {
        let label = NSTextField(labelWithString: Brand.versionLine)
        label.font = .systemFont(ofSize: 10)
        label.textColor = SettingsChrome.dim
        label.isSelectable = true
        return label
    }

    func websiteLink() -> NSButton {
        let link = NSButton(title: "www.spacyapps.com", target: self, action: #selector(openWebsite))
        link.isBordered = false
        link.contentTintColor = .linkColor
        link.font = .systemFont(ofSize: 11)
        link.attributedTitle = NSAttributedString(
            string: "www.spacyapps.com",
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: 11),
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        return link
    }

    func buttonRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let more = getMoreThemesButton()
        let create = NSButton(title: "Create a Theme…", target: self, action: #selector(createTheme))
        create.bezelStyle = .rounded
        let open = NSButton(title: "Open Folder…", target: self, action: #selector(openFolder))
        open.bezelStyle = .rounded
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshThemes))
        refresh.bezelStyle = .rounded

        row.addArrangedSubview(more)
        row.addArrangedSubview(create)
        row.addArrangedSubview(open)
        row.addArrangedSubview(refresh)
        // A gap after the one button that leaves the app, so it reads as its own
        // thing rather than as the first of four utilities.
        row.setCustomSpacing(18, after: more)
        return row
    }

    /// The only route from the app to anywhere themes can be got.
    ///
    /// Deliberately the loudest control in Settings, and the only tinted one —
    /// everything else here is a plain rounded button, so a single filled pill
    /// carries the whole hierarchy without needing a second colour anywhere.
    /// `bezelColor` rather than `keyEquivalent: "\r"`: making it the default
    /// button would tint it the same way and also bind Return to leaving the
    /// app, which is not what Return should do in a settings window.
    func getMoreThemesButton() -> NSButton {
        let button = NSButton(title: "Get More Themes", target: self, action: #selector(openThemeStore))
        button.bezelStyle = .rounded
        button.bezelColor = SettingsChrome.heading
        button.contentTintColor = SettingsChrome.deepSpace
        // The tint alone is not enough on a busy star field; the weight is what
        // makes it read as a button rather than as a coloured label.
        button.attributedTitle = NSAttributedString(
            string: "Get More Themes",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: SettingsChrome.deepSpace
            ]
        )
        button.toolTip = Brand.themeStore?.absoluteString
        return button
    }

    /// Section headers double as the dividers, so the old separator boxes are
    /// gone: one line per section instead of a label and a rule competing.
    func header(_ title: String, width: CGFloat = SettingsView.contentWidth) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithAttributedString: NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: SettingsChrome.heading,
                .kern: 1.8
            ]
        ))
        label.translatesAutoresizingMaskIntoConstraints = false
        // Pinned to the width of the word itself. Nothing else fixed it, so the
        // label and the rule could satisfy the constraints at any split, and the
        // one that won gave the label everything and the rule nothing — a
        // heading with no line after it. Hugging priority did not settle it;
        // a measured width does.
        label.widthAnchor.constraint(
            equalToConstant: ceil(label.intrinsicContentSize.width)
        ).isActive = true

        let rule = NSView()
        rule.wantsLayer = true
        rule.layer?.backgroundColor = SettingsChrome.rule.cgColor
        rule.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(rule)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),
            container.heightAnchor.constraint(equalToConstant: 15),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1)
        ])
        return container
    }

    /// The preview sits behind a hairline frame so it reads as a screen showing
    /// the theme, rather than as part of the window's own styling.
    func viewport() -> NSView {
        let frame = NSView()
        frame.wantsLayer = true
        frame.layer?.cornerRadius = 10
        frame.layer?.borderWidth = 1
        frame.layer?.borderColor = SettingsChrome.viewportEdge.cgColor
        frame.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        frame.translatesAutoresizingMaskIntoConstraints = false

        preview.translatesAutoresizingMaskIntoConstraints = false
        frame.addSubview(preview)

        let size = ThemePreviewView.preferredSize
        NSLayoutConstraint.activate([
            frame.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            frame.heightAnchor.constraint(equalToConstant: size.height + 20),
            preview.centerXAnchor.constraint(equalTo: frame.centerXAnchor),
            preview.centerYAnchor.constraint(equalTo: frame.centerYAnchor),
            preview.widthAnchor.constraint(equalToConstant: size.width - 20),
            preview.heightAnchor.constraint(equalToConstant: size.height)
        ])
        return frame
    }

    func configure(_ box: NSButton, title: String, action: Selector) {
        box.setButtonType(.switch)
        box.title = title
        box.target = self
        box.action = action
    }
}
