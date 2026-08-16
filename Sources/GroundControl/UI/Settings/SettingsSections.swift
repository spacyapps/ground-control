// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The two checkbox sections, kept out of `SettingsView` so that file stays
/// about the window rather than about its rows.
extension SettingsView {
    func panelSection(in stack: NSStackView) {
        stack.addArrangedSubview(header("Panel"))

        configure(onTopBox, title: "Always on top", action: #selector(togglesChanged))
        configure(allSpacesBox, title: "Show on all Spaces", action: #selector(togglesChanged))
        configure(analyserBox, title: "Show the analyser", action: #selector(analyserChanged))
        stack.addArrangedSubview(onTopBox)
        stack.addArrangedSubview(allSpacesBox)
        stack.addArrangedSubview(analyserBox)

        let note = caption("The bars across the title strip. Turning them off closes the strip "
            + "up and stops the animation entirely.")
        stack.addArrangedSubview(note)

        // Beside the switch it belongs to, on one line: a colour well on its
        // own row would read as a separate setting.
        let colourRow = NSStackView(views: [
            NSTextField(labelWithString: "Colour"),
            analyserWell,
            NSButton(title: "Use theme's", target: self, action: #selector(analyserColourReset))
        ])
        colourRow.orientation = .horizontal
        colourRow.spacing = 8
        analyserWell.target = self
        analyserWell.action = #selector(analyserColourChanged)
        // Continuous, so dragging around the picker shows the panel changing
        // rather than making you guess and close it.
        analyserWell.isContinuous = true
        NSLayoutConstraint.activate([
            analyserWell.widthAnchor.constraint(equalToConstant: 44),
            analyserWell.heightAnchor.constraint(equalToConstant: 22)
        ])
        if let reset = colourRow.views.last as? NSButton {
            reset.bezelStyle = .rounded
            reset.controlSize = .small
        }
        stack.addArrangedSubview(colourRow)
        stack.setCustomSpacing(14, after: colourRow)

        let reset = NSButton(
            title: "Reset Panel Position",
            target: self,
            action: #selector(resetPosition)
        )
        reset.bezelStyle = .rounded
        stack.addArrangedSubview(reset)
        stack.setCustomSpacing(20, after: reset)
    }

    func advancedSection(in stack: NSStackView) {
        stack.addArrangedSubview(header("Advanced"))

        configure(
            internalAgentsBox,
            title: "Show Claude Code's internal agents",
            action: #selector(internalAgentsChanged)
        )
        stack.addArrangedSubview(internalAgentsBox)
        stack.addArrangedSubview(caption(
            "Internal agents are hidden because their messages read like your own prompts."
        ))

        // Anyone deciding whether to let a monitor near their terminal should
        // be able to find out what it touches without reading the source.
        let legal = NSButton(
            title: "Licence, Privacy & Disclaimer…",
            target: self,
            action: #selector(openLegal)
        )
        legal.bezelStyle = .rounded
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last ?? legal)
        stack.addArrangedSubview(legal)
    }

    /// The small grey line under a checkbox that says what it costs you.
    func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = SettingsChrome.dim
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.preferredMaxLayoutWidth = SettingsView.contentWidth
        return label
    }
}
