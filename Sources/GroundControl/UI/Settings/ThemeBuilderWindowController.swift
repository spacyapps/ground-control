// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// "Create a Theme…": a few questions, then a prompt to paste into an
/// image-capable LLM, and a folder already waiting for the results.
final class ThemeBuilderWindowController: NSWindowController {
    private let nameField = NSTextField(string: "")
    private let subjectField = NSTextField(string: "")
    private let styleField = NSTextField(string: "")
    private let moodField = NSTextField(string: "")
    private let backgroundField = NSTextField(string: "")
    private let animateBox = NSButton()
    private let sizeField = NSTextField(string: "48")
    private let framePicker = NSPopUpButton()
    private let keyPicker = NSPopUpButton()
    private let positionPicker = NSPopUpButton()
    private let promptView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")

    private let onThemesChanged: () -> Void

    init(onThemesChanged: @escaping () -> Void) {
        self.onThemesChanged = onThemesChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Create a Theme"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.contentView = buildContent()
        applyPlaceholders()
        regenerate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ThemeBuilderWindowController is created in code only")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 560))

        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8
        form.translatesAutoresizingMaskIntoConstraints = false

        form.addArrangedSubview(caption("Answer these, then paste the prompt into any image-capable LLM."))
        form.addArrangedSubview(field(nameField, label: "Theme name"))
        form.addArrangedSubview(field(subjectField, label: "Character or mascot"))
        form.addArrangedSubview(field(styleField, label: "Visual style"))
        form.addArrangedSubview(field(moodField, label: "Mood and colours"))
        form.addArrangedSubview(field(backgroundField, label: "Panel background"))
        form.addArrangedSubview(caption(
            "Leave the background blank for colours only. The panel resizes, so anything here "
            + "is described to the model as nine-slice art: detail in the corners, tiling centre."
        ))

        animateBox.setButtonType(.switch)
        animateBox.title = "Animate working and needs-input (GIF)"
        animateBox.state = .on
        animateBox.target = self
        animateBox.action = #selector(regenerate)
        form.addArrangedSubview(animateBox)
        addFrameQuestion(to: form)
        form.addArrangedSubview(geometryRow())

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        promptView.isEditable = false
        promptView.isSelectable = true
        promptView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        promptView.textContainerInset = NSSize(width: 6, height: 6)
        scroll.documentView = promptView

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor

        let buttons = buttonRow()
        buttons.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(form)
        root.addSubview(scroll)
        root.addSubview(statusLabel)
        root.addSubview(buttons)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            form.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            form.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),

            scroll.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),

            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            statusLabel.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -10),

            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        return root
    }

    /// The two choices that govern every image the author is about to draw, so
    /// they belong in the questions rather than buried in the prompt.
    private func addFrameQuestion(to form: NSStackView) {
        form.addArrangedSubview(frameRow())
        form.addArrangedSubview(caption(
            "Simple scales the whole picture and suits any artwork. Nine-grid holds "
            + "the corners and repeats the edges, so the panel can be dragged to any "
            + "shape — it asks more of the art, and it is how spacyAppsLunarAvatar works."
        ))
    }

    private func frameRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        for style in ThemeBrief.Frame.allCases {
            framePicker.addItem(withTitle: style.title)
        }
        framePicker.target = self
        framePicker.action = #selector(regenerate)

        // Named by colour rather than hex: the point is picking one the art
        // never uses, which is a question about the art, not about notation.
        for (title, _) in Self.keyColours {
            keyPicker.addItem(withTitle: title)
        }
        keyPicker.target = self
        keyPicker.action = #selector(regenerate)

        row.addArrangedSubview(NSTextField(labelWithString: "Frame"))
        row.addArrangedSubview(framePicker)
        row.addArrangedSubview(NSTextField(labelWithString: "Transparent"))
        row.addArrangedSubview(keyPicker)
        return row
    }

    /// A key colour has to be one the artwork never contains, so the choice is
    /// the author's — a green frame keyed on green erases itself.
    private static let keyColours = [
        ("Green — unless the art is green", "#00FF00"),
        ("Magenta — unless the art is pink", "#FF00FF"),
        ("Blue — unless the art is blue", "#0000FF")
    ]

    private func geometryRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let sizeLabel = NSTextField(labelWithString: "Avatar size")
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        sizeField.widthAnchor.constraint(equalToConstant: 54).isActive = true
        sizeField.target = self
        sizeField.action = #selector(regenerate)

        positionPicker.addItems(withTitles: ["right", "left"])
        positionPicker.target = self
        positionPicker.action = #selector(regenerate)

        row.addArrangedSubview(sizeLabel)
        row.addArrangedSubview(sizeField)
        row.addArrangedSubview(NSTextField(labelWithString: "Position"))
        row.addArrangedSubview(positionPicker)
        return row
    }

    private func buttonRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let regenerateButton = NSButton(title: "Update Prompt", target: self, action: #selector(regenerate))
        let copyButton = NSButton(title: "Copy Prompt", target: self, action: #selector(copyPrompt))
        let createButton = NSButton(
            title: "Create Folder & Copy",
            target: self,
            action: #selector(createFolder)
        )
        createButton.keyEquivalent = "\r"

        for button in [regenerateButton, copyButton, createButton] {
            button.bezelStyle = .rounded
            row.addArrangedSubview(button)
        }
        return row
    }

    private func field(_ control: NSTextField, label: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let title = NSTextField(labelWithString: label)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.widthAnchor.constraint(equalToConstant: 140).isActive = true
        title.alignment = .right

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        control.target = self
        control.action = #selector(regenerate)

        row.addArrangedSubview(title)
        row.addArrangedSubview(control)
        return row
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// Placeholders double as a worked example, so the window is never a blank
    /// form staring back at you.
    private func applyPlaceholders() {
        let example = ThemeBrief.placeholder
        nameField.placeholderString = example.name
        subjectField.placeholderString = example.subject
        styleField.placeholderString = example.style
        moodField.placeholderString = example.mood
        backgroundField.placeholderString = example.background
    }

    // MARK: - Brief

    private var brief: ThemeBrief {
        func value(_ control: NSTextField, fallback: String) -> String {
            let text = control.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? fallback : text
        }
        let example = ThemeBrief.placeholder
        return ThemeBrief(
            name: value(nameField, fallback: example.name),
            subject: value(subjectField, fallback: example.subject),
            style: value(styleField, fallback: example.style),
            mood: value(moodField, fallback: example.mood),
            wantsAnimation: animateBox.state == .on,
            frame: ThemeBrief.Frame.allCases[
                max(0, min(ThemeBrief.Frame.allCases.count - 1, framePicker.indexOfSelectedItem))
            ],
            keyColour: Self.keyColours[
                max(0, min(Self.keyColours.count - 1, keyPicker.indexOfSelectedItem))
            ].1,
            // Blank is meaningful here: it means "no background", so this one
            // does not fall back to the placeholder like the others.
            background: backgroundField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarSize: max(16, min(160, Int(sizeField.stringValue) ?? example.avatarSize)),
            position: positionPicker.titleOfSelectedItem ?? "right"
        )
    }

    // MARK: - Actions

    @objc private func regenerate() {
        promptView.string = ThemePromptBuilder.prompt(for: brief)
        statusLabel.stringValue = ""
    }

    @objc private func copyPrompt() {
        regenerate()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(promptView.string, forType: .string)
        statusLabel.stringValue = "Prompt copied — paste it into your LLM."
    }

    @objc private func createFolder() {
        regenerate()
        let brief = self.brief
        do {
            let folder = try ThemeScaffold.create(from: brief)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(promptView.string, forType: .string)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
            onThemesChanged()
            statusLabel.stringValue = "Created “\(brief.slug)”. Prompt copied — drop the images in."
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }
}
