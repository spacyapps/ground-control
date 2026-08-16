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
        /// Re-lays the panel: the analyser's absence changes the strip's height.
        var refreshPanelChrome: () -> Void
        /// Re-reads the theme so a changed analyser colour is applied to it.
        var reloadTheme: () -> Void
        var openLegal: () -> Void
        var openThemesFolder: () -> Void
        var resetPanelPosition: () -> Void
        var createTheme: () -> Void
    }

    private let preferences: Preferences
    let actions: Actions

    /// The left column: wide enough for the preview, which is the one thing
    /// here with a size of its own.
    static let contentWidth: CGFloat = 360

    /// The right column, holding the switches. Narrower because a checkbox and
    /// its caption need far less room than a picture of the panel — and a
    /// caption measured much wider than this reads as a paragraph.
    static let sideWidth: CGFloat = 250

    /// Between the columns. Wide enough that the right column's rule does not
    /// look like a continuation of the left one's.
    static let gutter: CGFloat = 24

    private let themePicker = NSPopUpButton()
    private let themeDetail = NSTextField(labelWithString: "")
    private let themeWarning = NSTextField(labelWithString: "")
    let preview = ThemePreviewView()
    let onTopBox = NSButton()
    let allSpacesBox = NSButton()
    let internalAgentsBox = NSButton()
    let analyserBox = NSButton()
    let analyserWell = NSColorWell()

    /// Folder names in picker order; `nil` is the built-in default.
    private var themeNames: [String?] = [nil]

    init(preferences: Preferences = .shared, actions: Actions) {
        self.preferences = preferences
        self.actions = actions
        super.init(frame: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 560))
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
        // Clear of the window title. The title bar is transparent so the star
        // field runs under it, which also means the content would start beneath
        // the title text unless it is pushed down.
        stack.edgeInsets = NSEdgeInsets(top: 42, left: 30, bottom: 22, right: 30)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        stack.addArrangedSubview(brandRow())
        stack.addArrangedSubview(columns())
    }

    /// The theme on the left, the switches on the right.
    ///
    /// One column meant the window was mostly empty to the right of every
    /// checkbox while the whole thing scrolled — the preview is tall, and the
    /// settings beside it are short. Side by side, both fit on screen at once
    /// and nothing has to be scrolled to be found.
    private func columns() -> NSView {
        let left = column(width: Self.contentWidth)
        let right = column(width: Self.sideWidth)

        themeSection(in: left)
        panelSection(in: right)
        advancedSection(in: right)

        let row = NSStackView(views: [left, right])
        row.orientation = .horizontal
        // Top, not centre: the columns are different heights, and a short right
        // column floating in the middle of a tall left one reads as unfinished.
        row.alignment = .top
        row.spacing = Self.gutter
        return row
    }

    private func column(width: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        return stack
    }

    /// Both columns, both gutters, and the inset the outer stack applies.
    static var windowWidth: CGFloat { contentWidth + gutter + sideWidth + 60 }

    private func themeSection(in stack: NSStackView) {
        stack.addArrangedSubview(header("Theme"))

        themePicker.target = self
        themePicker.action = #selector(themeChanged)
        // Left to itself a pop-up is exactly as wide as its longest entry, so
        // the control jumped about as themes were added and left a ragged edge.
        themePicker.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        stack.addArrangedSubview(themePicker)

        themeDetail.font = .systemFont(ofSize: 11)
        themeDetail.textColor = SettingsChrome.dim
        themeDetail.lineBreakMode = .byWordWrapping
        // Three, and truncating at the end when even that is not enough: two
        // clipped a theme's own description mid-word with nothing to say it
        // had been cut.
        themeDetail.maximumNumberOfLines = 3
        // Wrapping and an ellipsis together: the line break mode alone turns
        // the field single-line, and a cut description then loses two thirds of
        // itself rather than its tail.
        themeDetail.lineBreakMode = .byTruncatingTail
        themeDetail.cell?.wraps = true
        themeDetail.cell?.isScrollable = false
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
        analyserBox.state = preferences.showsAnalyser ? .on : .off
        // No stored colour means "whatever the theme picked", and the well
        // should show that rather than a colour nobody chose.
        analyserWell.color = preferences.analyserTint.flatMap { NSColor(hex: $0) }
            ?? ThemeLoader.loadTheme(named: preferences.themeName).matrix.high
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

    @objc func togglesChanged() {
        preferences.alwaysOnTop = onTopBox.state == .on
        preferences.showOnAllSpaces = allSpacesBox.state == .on
        actions.applyWindowBehaviour()
    }

    @objc func analyserChanged() {
        preferences.showsAnalyser = analyserBox.state == .on
        actions.refreshPanelChrome()
    }

    @objc func analyserColourChanged() {
        preferences.analyserTint = analyserWell.color.hexString
        actions.reloadTheme()
    }

    @objc func openLegal() {
        actions.openLegal()
    }

    /// Hands the analyser back to the theme, which is otherwise unreachable
    /// once a colour has been picked — a colour well has no "none".
    @objc func analyserColourReset() {
        preferences.analyserTint = nil
        actions.reloadTheme()
        syncFromPreferences()
    }

    @objc func internalAgentsChanged() {
        preferences.showsInternalAgents = internalAgentsBox.state == .on
        actions.reloadSessions()
    }

    @objc func openFolder() {
        actions.openThemesFolder()
    }

    @objc func refreshThemes() {
        reloadThemes()
    }

    @objc func openWebsite() {
        Brand.openWebsite()
    }

    @objc func createTheme() {
        actions.createTheme()
    }

    /// The builder may have just written a new folder.
    func themesDidChangeOnDisk() {
        reloadThemes()
    }

    @objc func resetPosition() {
        actions.resetPanelPosition()
    }
}
