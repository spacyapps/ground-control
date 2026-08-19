// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The two checkbox sections, kept out of `SettingsView` so that file stays
/// about the window rather than about its rows.
extension SettingsView {
    func panelSection(in stack: NSStackView) {
        stack.addArrangedSubview(header("Panel", width: SettingsView.sideWidth))

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
        stack.addArrangedSubview(header("Advanced", width: SettingsView.sideWidth))

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
        // Captions live in the narrow column, so they run to more lines there
        // than they did across the full width.
        label.maximumNumberOfLines = 4
        label.preferredMaxLayoutWidth = SettingsView.sideWidth
        return label
    }
}

/// "Does it work?", answered without a conversation — and fixed in the same
/// place it is answered.
///
/// Every failed setup this project has seen was visible from outside the app: a
/// registration written to a path with a space in it, an emitter left behind by
/// an older install, an agent that fires nothing at the moment it matters, a CLI
/// that was never supported. Each cost an evening of questions.
///
/// The menu used to offer "Set Up Hooks…" and "Remove Hooks…", which could only
/// say yes or no to all of them at once. One switch per integration says which,
/// and one integration can be turned off without disturbing the others.
extension SettingsView {
    func setupSection(in stack: NSStackView) {
        stack.addArrangedSubview(header("Hooks", width: SettingsView.sideWidth))
        rebuildSetup()
    }

    /// Re-reads the world and redraws these rows in place.
    ///
    /// Called after a switch, because what the rows say is derived from files on
    /// disk rather than from the switch itself — which is the point. If the
    /// script failed, the switch goes back on its own.
    func rebuildSetup() {
        guard let column = setupColumn else { return }
        for view in setupViews { column.removeArrangedSubview(view); view.removeFromSuperview() }
        setupViews = []

        var added: [NSView] = []
        for agent in SetupStatus.agents(sessions: actions.currentSessions()) {
            added.append(agentRow(agent))
        }
        added.append(caption(emitterLine(SetupStatus.emitter())))

        // Straight after the Hooks header, which is the last thing in the column
        // when this first runs and stays put on every rebuild after it.
        let start = (column.arrangedSubviews.firstIndex { ($0 as? NSTextField) == nil
            && $0.subviews.contains { ($0 as? NSTextField)?.stringValue == "HOOKS" } }).map { $0 + 1 }
            ?? column.arrangedSubviews.count
        for (offset, view) in added.enumerated() {
            column.insertArrangedSubview(view, at: min(start + offset, column.arrangedSubviews.count))
        }
        setupViews = added
        if let last = added.last { column.setCustomSpacing(20, after: last) }
    }

    /// One integration: a switch, its name, and the line that matters —
    /// **has anything arrived?** A registration only proves a file was written.
    private func agentRow(_ agent: SetupStatus.Agent) -> NSView {
        let name = NSTextField(labelWithString: agent.name)
        name.font = .systemFont(ofSize: 11, weight: .medium)
        name.textColor = agent.detected ? .labelColor : SettingsChrome.dim

        let toggle = NSSwitch()
        toggle.state = agent.registered ? .on : .off
        toggle.controlSize = .mini
        toggle.target = self
        toggle.action = #selector(hookToggled(_:))
        toggle.identifier = agent.target.map { NSUserInterfaceItemIdentifier($0.rawValue) }
        // Nothing to switch on for an agent that is not here, or not yet
        // supported. Greyed out with the reason underneath beats a control that
        // silently does nothing.
        toggle.isEnabled = agent.detected && agent.target != nil

        let heading = NSStackView(views: [toggle, name])
        heading.orientation = .horizontal
        heading.spacing = 8

        let detail = caption(state(of: agent))
        detail.maximumNumberOfLines = 3

        let column = NSStackView(views: [heading, detail])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        return column
    }

    private func state(of agent: SetupStatus.Agent) -> String {
        var parts: [String] = []
        if !agent.detected {
            parts.append("not installed on this Mac")
        } else if !agent.registered {
            parts.append("off")
        } else if let seen = agent.lastEvent {
            parts.append("working — last seen \(ElapsedFormatter.short(since: seen)) ago")
        } else {
            parts.append("on, nothing received yet")
        }
        if let caveat = agent.caveat, agent.detected { parts.append(caveat) }
        return parts.joined(separator: ". ")
    }

    private func emitterLine(_ emitter: (installed: Bool, current: Bool?)) -> String {
        guard emitter.installed else {
            return "The reporting script is not installed yet. Turn an agent on above."
        }
        switch emitter.current {
        case true: return "Reporting script installed and matching this version."
        case false: return "Reporting script is older than this app — relaunching updates it."
        case nil: return "Reporting script installed."
        }
    }
}
