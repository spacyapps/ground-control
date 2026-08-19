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

/// "Does it work?", answered without a conversation.
///
/// Every failed setup this project has seen was visible from outside the app:
/// a registration written to a path with a space in it, an emitter left over
/// from an older install, an agent that fires nothing at the moment it matters,
/// a CLI that was never supported. Each cost an evening of questions.
extension SettingsView {
    func setupSection(in stack: NSStackView) {
        stack.addArrangedSubview(header("Setup", width: SettingsView.sideWidth))

        for agent in SetupStatus.agents(sessions: actions.currentSessions()) {
            stack.addArrangedSubview(agentRow(agent))
        }

        let emitter = SetupStatus.emitter()
        stack.addArrangedSubview(caption(emitterLine(emitter)))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last ?? stack)
    }

    /// One agent, one line, and the line that matters is the last part of it:
    /// **has anything arrived?** A registration only proves a file was written.
    private func agentRow(_ agent: SetupStatus.Agent) -> NSView {
        let label = NSTextField(labelWithString: "\(mark(for: agent))  \(agent.name)")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = agent.detected ? .labelColor : SettingsChrome.dim

        let detail = caption(state(of: agent))
        detail.maximumNumberOfLines = 3

        let column = NSStackView(views: [label, detail])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 1
        return column
    }

    private func mark(for agent: SetupStatus.Agent) -> String {
        guard agent.detected else { return "○" }
        if agent.lastEvent != nil { return "●" }
        return agent.registered ? "◐" : "○"
    }

    private func state(of agent: SetupStatus.Agent) -> String {
        var parts: [String] = []
        if !agent.detected {
            parts.append("not installed on this Mac")
        } else if !agent.registered {
            parts.append("installed, not registered")
        } else if let seen = agent.lastEvent {
            parts.append("working — last seen \(ElapsedFormatter.short(since: seen)) ago")
        } else {
            parts.append("registered, nothing received yet")
        }
        if let caveat = agent.caveat, agent.detected { parts.append(caveat) }
        return parts.joined(separator: ". ")
    }

    private func emitterLine(_ emitter: (installed: Bool, current: Bool?)) -> String {
        guard emitter.installed else {
            return "The reporting script is not installed. Choose Set Up Hooks… from the menu."
        }
        switch emitter.current {
        case true: return "Reporting script installed and matching this version."
        case false: return "Reporting script is older than this app — relaunching updates it."
        case nil: return "Reporting script installed."
        }
    }
}
