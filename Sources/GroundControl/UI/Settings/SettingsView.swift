// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Settings content: theme picker with live preview, panel behaviour, and the
/// one advanced escape hatch.
///
/// The chrome is the app's own — a star field and a fixed palette — not the
/// selected theme's. Settings is where you judge a theme, and a window that
/// restyles itself to match whatever is selected leaves nothing to judge it
/// against. Only the preview wears the theme, framed as a viewport so it reads
/// as a sample rather than as decoration.
final class SettingsView: NSView {
    struct Actions {
        var selectTheme: (String?) -> Void
        var applyWindowBehaviour: () -> Void
        var reloadSessions: () -> Void
        var openThemesFolder: () -> Void
        var resetPanelPosition: () -> Void
        var createTheme: () -> Void
    }

    private let preferences: Preferences
    private let actions: Actions

    /// Everything lines up to one gutter; the rules run to the same edge.
    private static let contentWidth: CGFloat = 360

    private let themePicker = NSPopUpButton()
    private let themeDetail = NSTextField(labelWithString: "")
    private let themeWarning = NSTextField(labelWithString: "")
    private let preview = ThemePreviewView()
    private let onTopBox = NSButton()
    private let allSpacesBox = NSButton()
    private let internalAgentsBox = NSButton()

    /// Folder names in picker order; `nil` is the built-in default.
    private var themeNames: [String?] = [nil]

    init(preferences: Preferences = .shared, actions: Actions) {
        self.preferences = preferences
        self.actions = actions
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 626))
        build()
        reloadThemes()
        syncFromPreferences()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsView is created in code only")
    }

    // MARK: - Construction

    private func build() {
        let sky = StarfieldView()
        sky.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sky)
        NSLayoutConstraint.activate([
            sky.leadingAnchor.constraint(equalTo: leadingAnchor),
            sky.trailingAnchor.constraint(equalTo: trailingAnchor),
            sky.topAnchor.constraint(equalTo: topAnchor),
            sky.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 30, bottom: 22, right: 30)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        stack.addArrangedSubview(brandRow())
        themeSection(in: stack)
        panelSection(in: stack)
        advancedSection(in: stack)
    }

    private func themeSection(in stack: NSStackView) {
        stack.addArrangedSubview(header("Theme"))

        themePicker.target = self
        themePicker.action = #selector(themeChanged)
        stack.addArrangedSubview(themePicker)

        themeDetail.font = .systemFont(ofSize: 11)
        themeDetail.textColor = SettingsChrome.dim
        themeDetail.lineBreakMode = .byWordWrapping
        themeDetail.maximumNumberOfLines = 2
        themeDetail.preferredMaxLayoutWidth = Self.contentWidth
        stack.addArrangedSubview(themeDetail)

        themeWarning.font = .systemFont(ofSize: 11)
        themeWarning.textColor = SettingsChrome.caution
        themeWarning.lineBreakMode = .byWordWrapping
        themeWarning.maximumNumberOfLines = 3
        themeWarning.preferredMaxLayoutWidth = Self.contentWidth
        themeWarning.isHidden = true
        stack.addArrangedSubview(themeWarning)

        stack.addArrangedSubview(viewport())

        let buttons = buttonRow()
        stack.addArrangedSubview(buttons)
        stack.setCustomSpacing(20, after: buttons)
    }

    private func panelSection(in stack: NSStackView) {
        stack.addArrangedSubview(header("Panel"))

        configure(onTopBox, title: "Always on top", action: #selector(togglesChanged))
        configure(allSpacesBox, title: "Show on all Spaces", action: #selector(togglesChanged))
        stack.addArrangedSubview(onTopBox)
        stack.addArrangedSubview(allSpacesBox)

        let reset = NSButton(
            title: "Reset Panel Position",
            target: self,
            action: #selector(resetPosition)
        )
        reset.bezelStyle = .rounded
        stack.addArrangedSubview(reset)
        stack.setCustomSpacing(20, after: reset)
    }

    private func advancedSection(in stack: NSStackView) {
        stack.addArrangedSubview(header("Advanced"))

        configure(
            internalAgentsBox,
            title: "Show Claude Code's internal agents",
            action: #selector(internalAgentsChanged)
        )
        stack.addArrangedSubview(internalAgentsBox)

        let caveat = NSTextField(labelWithString:
            "Internal agents are hidden because their messages read like your own prompts.")
        caveat.font = .systemFont(ofSize: 10)
        caveat.textColor = SettingsChrome.dim
        caveat.lineBreakMode = .byWordWrapping
        caveat.maximumNumberOfLines = 2
        caveat.preferredMaxLayoutWidth = Self.contentWidth
        stack.addArrangedSubview(caveat)
    }

    /// The app's own mark and a way back to whoever made it. Settings is a
    /// system surface, so unlike the panel no theme ever replaces this.
    private func brandRow() -> NSView {
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
        return column
    }

    private func websiteLink() -> NSButton {
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

    private func buttonRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let create = NSButton(title: "Create a Theme…", target: self, action: #selector(createTheme))
        create.bezelStyle = .rounded
        let open = NSButton(title: "Open Folder…", target: self, action: #selector(openFolder))
        open.bezelStyle = .rounded
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshThemes))
        refresh.bezelStyle = .rounded

        row.addArrangedSubview(create)
        row.addArrangedSubview(open)
        row.addArrangedSubview(refresh)
        return row
    }

    /// Section headers double as the dividers, so the old separator boxes are
    /// gone: one line per section instead of a label and a rule competing.
    private func header(_ title: String) -> NSView {
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

        let rule = NSView()
        rule.wantsLayer = true
        rule.layer?.backgroundColor = SettingsChrome.rule.cgColor
        rule.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(rule)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.contentWidth),
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
    private func viewport() -> NSView {
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

    private func configure(_ box: NSButton, title: String, action: Selector) {
        box.setButtonType(.switch)
        box.title = title
        box.target = self
        box.action = action
    }

    // MARK: - State

    private func reloadThemes() {
        let folders = ThemeLoader.availableThemes()
        themeNames = [nil] + folders.map { $0.lastPathComponent }

        themePicker.removeAllItems()
        themePicker.addItem(withTitle: "Default (built-in)")
        for folder in folders {
            themePicker.addItem(withTitle: folder.lastPathComponent)
        }

        let index = themeNames.firstIndex { $0 == preferences.themeName } ?? 0
        themePicker.selectItem(at: index)
        updatePreview()
    }

    private func syncFromPreferences() {
        onTopBox.state = preferences.alwaysOnTop ? .on : .off
        allSpacesBox.state = preferences.showOnAllSpaces ? .on : .off
        internalAgentsBox.state = preferences.showsInternalAgents ? .on : .off
    }

    private func updatePreview() {
        let theme = ThemeLoader.loadTheme(named: preferences.themeName)
        preview.apply(theme: theme)

        // The picker already shows the folder name, so repeating it told you
        // nothing. The manifest's own metadata does.
        var details: [String] = [theme.name]
        if let author = theme.author, !author.isEmpty {
            details.append("by \(author)")
        }
        if theme.folder == nil {
            details.append("drawn faces, no image files")
        }
        var line = details.joined(separator: " · ")
        if let summary = theme.summary, !summary.isEmpty {
            line += "\n" + summary
        }
        themeDetail.stringValue = line

        // A theme that quietly does something other than what it asked for is
        // the hardest kind of bug to find, so it says so here.
        let warnings = theme.warnings.map { $0.replacingOccurrences(of: "\n", with: " ") }
        themeWarning.stringValue = warnings.joined(separator: " ")
        themeWarning.isHidden = warnings.isEmpty
    }

    /// Called when the theme hot-reloads underneath us.
    func themeDidChange() {
        updatePreview()
    }

    // MARK: - Actions

    @objc private func themeChanged() {
        let index = themePicker.indexOfSelectedItem
        guard themeNames.indices.contains(index) else { return }
        actions.selectTheme(themeNames[index])
        updatePreview()
    }

    @objc private func togglesChanged() {
        preferences.alwaysOnTop = onTopBox.state == .on
        preferences.showOnAllSpaces = allSpacesBox.state == .on
        actions.applyWindowBehaviour()
    }

    @objc private func internalAgentsChanged() {
        preferences.showsInternalAgents = internalAgentsBox.state == .on
        actions.reloadSessions()
    }

    @objc private func openFolder() {
        actions.openThemesFolder()
    }

    @objc private func refreshThemes() {
        reloadThemes()
    }

    @objc private func openWebsite() {
        Brand.openWebsite()
    }

    @objc private func createTheme() {
        actions.createTheme()
    }

    /// The builder may have just written a new folder.
    func themesDidChangeOnDisk() {
        reloadThemes()
    }

    @objc private func resetPosition() {
        actions.resetPanelPosition()
    }
}
