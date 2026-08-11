// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import AppKit

/// Settings content: theme picker with live preview, panel behaviour, and the
/// one advanced escape hatch.
///
/// Deliberately native-looking rather than skinned — the panel is the themed
/// surface; this is a system surface, and skinning it would make the preview
/// meaningless.
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

    private let themePicker = NSPopUpButton()
    private let themeDetail = NSTextField(labelWithString: "")
    private let preview = ThemePreviewView()
    private let onTopBox = NSButton()
    private let allSpacesBox = NSButton()
    private let internalAgentsBox = NSButton()

    /// Folder names in picker order; `nil` is the built-in default.
    private var themeNames: [String?] = [nil]

    init(preferences: Preferences = .shared, actions: Actions) {
        self.preferences = preferences
        self.actions = actions
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 470))
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
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        stack.addArrangedSubview(brandRow())
        stack.addArrangedSubview(header("Theme"))

        themePicker.target = self
        themePicker.action = #selector(themeChanged)
        stack.addArrangedSubview(themePicker)

        themeDetail.font = .systemFont(ofSize: 11)
        themeDetail.textColor = .secondaryLabelColor
        themeDetail.lineBreakMode = .byWordWrapping
        themeDetail.maximumNumberOfLines = 2
        stack.addArrangedSubview(themeDetail)

        preview.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(preview)
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 300),
            preview.heightAnchor.constraint(equalToConstant: 96)
        ])

        stack.addArrangedSubview(buttonRow())
        stack.addArrangedSubview(separator())
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

        stack.addArrangedSubview(separator())
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
        caveat.textColor = .tertiaryLabelColor
        caveat.lineBreakMode = .byWordWrapping
        caveat.maximumNumberOfLines = 2
        caveat.preferredMaxLayoutWidth = 320
        stack.addArrangedSubview(caveat)
    }

    /// The app's own mark. Settings is a system surface, so unlike the panel
    /// no theme ever replaces this one.
    private func brandRow() -> NSView {
        let mark = NSImageView()
        mark.image = Brand.lockup
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 190),
            mark.heightAnchor.constraint(equalToConstant: 52)
        ])
        return mark
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

    private func header(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 320).isActive = true
        return line
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

        var details: [String] = []
        if let folder = theme.folder {
            details.append(folder.lastPathComponent)
        } else {
            details.append("Drawn faces, no image files")
        }
        themeDetail.stringValue = details.joined(separator: " · ")
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
