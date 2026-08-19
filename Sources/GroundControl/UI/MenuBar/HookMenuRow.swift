// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// One integration inside the Hooks menu: a switch, its name, and what it is
/// currently doing.
///
/// A menu item can host a view, which is what makes a real switch possible here
/// rather than a tick. A tick says "registered"; a switch says "this is a thing
/// you can turn off", which is the truer description of what clicking does.
///
/// The line underneath is the one that matters. A registration only proves a
/// file was written — "last seen 1m ago" proves it is being run, and those two
/// came apart once and cost an evening.
final class HookMenuRow: NSView {
    private let toggle = NSSwitch()
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let onToggle: (Bool) -> Void

    /// Menus draw their own highlight behind an item's view, so this one paints
    /// nothing and simply lays text out on top of it.
    init(agent: SetupStatus.Agent, width: CGFloat, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        super.init(frame: .zero)

        toggle.state = agent.registered ? .on : .off
        toggle.controlSize = .mini
        toggle.target = self
        toggle.action = #selector(flipped)
        // Nothing to switch for an agent that is absent or unsupported. Shown
        // anyway with the reason beneath: "why is opencode missing" is the
        // question this menu exists to answer.
        toggle.isEnabled = agent.detected && agent.target != nil

        name.font = .menuFont(ofSize: 13)
        name.textColor = toggle.isEnabled ? .labelColor : .secondaryLabelColor

        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byWordWrapping
        detail.maximumNumberOfLines = 3
        detail.preferredMaxLayoutWidth = width - 76

        name.stringValue = agent.name
        detail.stringValue = Self.summary(of: agent)

        for view in [toggle, name, detail] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            toggle.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            name.leadingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: toggle.centerYAnchor),
            detail.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            widthAnchor.constraint(equalToConstant: width)
        ])

        // A menu sizes an item from its view's *frame*, and never runs a layout
        // pass to work one out. Left at zero the row is present but empty: the
        // switch draws, because it sizes itself, and every label lands outside
        // the box. So the frame is resolved here, once, and handed over solid.
        layoutSubtreeIfNeeded()
        frame = NSRect(origin: .zero, size: NSSize(width: width, height: fittingSize.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HookMenuRow is created in code only")
    }

    @objc private func flipped() {
        onToggle(toggle.state == .on)
    }

    /// State first, then the limitation, because the limitation is permanent and
    /// the state is what changed since you last looked.
    static func summary(of agent: SetupStatus.Agent) -> String {
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
}
