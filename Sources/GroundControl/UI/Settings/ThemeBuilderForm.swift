// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The questions "Create a Theme" asks, kept out of the window controller so
/// that file stays about the window, the brief and the buttons.
///
/// Same split as `SettingsSections`, and for the same reason: the form grows
/// every time a theme learns a new trick, and it should not drag the controller
/// past its limits each time.
extension ThemeBuilderWindowController {
    func buildContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 560))

        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8
        form.translatesAutoresizingMaskIntoConstraints = false

        addIntroduction(to: form)
        form.addArrangedSubview(field(nameField, label: "Theme name"))
        form.addArrangedSubview(field(subjectField, label: "Character or mascot"))
        addReferenceQuestion(to: form)
        addLookQuestions(to: form)
        addWordsQuestion(to: form)

        animateBox.setButtonType(.switch)
        animateBox.title = "Animate working and needs-input (GIF)"
        animateBox.state = .on
        animateBox.target = self
        animateBox.action = #selector(regenerate)
        form.addArrangedSubview(animateBox)
        form.addArrangedSubview(statesTable())
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
            // Capped rather than pinned to the window. Widening the window used
            // to stretch every field with it, so "Avatar size" became a box a
            // thousand points wide holding the number 48. Extra width goes to
            // the prompt below, which is the only thing here that wants it.
            form.widthAnchor.constraint(equalToConstant: Self.formWidth),
            form.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -18),

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

    /// What to expect before they spend an hour on it.
    ///
    /// Someone whose first images come back not quite right will conclude the
    /// feature is broken. They are supposed to come back not quite right — the
    /// prompt asks for drafts on purpose — and saying so here costs two lines.
    func addIntroduction(to form: NSStackView) {
        form.addArrangedSubview(caption("A sketch, not a specification — the model asks you to confirm each "
                + "of these before it draws. Answer roughly, then paste part one "
                + "into any image-capable LLM."))
        // Said before they start, because the alternative is someone deciding
        // the feature is broken when the first images come back not quite right.
        // They are supposed to come back not quite right.
        form.addArrangedSubview(caption(
            "Expect a conversation rather than one shot. The prompt asks for still "
            + "drafts first so you can say what to change — colours, pose, how bold "
            + "the alarm state reads — before anything is animated. Two or three "
            + "rounds is normal."
        ))
    }

    /// How it should look, in words — the part an attached picture makes easier
    /// but never quite replaces.
    private func addLookQuestions(to form: NSStackView) {
        form.addArrangedSubview(field(styleField, label: "Visual style"))
        form.addArrangedSubview(field(moodField, label: "Mood and colours"))
        form.addArrangedSubview(field(backgroundField, label: "Panel background"))
        form.addArrangedSubview(caption(
            "Leave the background blank for colours only. The panel resizes, so anything here "
            + "is described to the model as nine-slice art: detail in the corners, tiling centre."
        ))
    }

    /// Whether they have a picture of the character.
    ///
    /// The hardest part of this form is describing a face in words, and it is
    /// where the second round usually comes from. An image skips it — and one
    /// image for all four moods is also what keeps them looking like the same
    /// character rather than four cousins.
    private func addReferenceQuestion(to form: NSStackView) {
        referenceBox.setButtonType(.switch)
        referenceBox.title = "I have a picture of them to attach"
        referenceBox.target = self
        referenceBox.action = #selector(regenerate)
        form.addArrangedSubview(referenceBox)
        form.addArrangedSubview(caption(
            "Describing a face in words is the hardest part of this. If you have an image, "
            + "attach it to your first message and the prompt will tell the model to work "
            + "from it — and to derive all four moods from that one picture, so they look "
            + "like the same character rather than four cousins."
        ))
    }

    /// The one part of a theme nobody discovers on their own.
    ///
    /// The words scroll past every half-minute and read as part of the app
    /// rather than as content, so an author never thinks to look for them. Asked
    /// here, at the moment they are inventing a voice for the thing, they are
    /// answered rather than looked up.
    func addWordsQuestion(to form: NSStackView) {
        form.addArrangedSubview(field(wordsField, label: "Display words"))
        form.addArrangedSubview(caption(
            "The little LED display spells these while nothing is happening. Separate them "
            + "with commas — A–Z, 0–9 and . - ! only, 13 characters each. Leave it blank and "
            + "the model writes some in your theme's voice."
        ))
    }

    /// The key colour, which is the one frame decision the author must make
    /// here: it depends on the artwork, which only they can see coming.
    ///
    /// There used to be a frame-kind picker beside it. Every frame is a
    /// nine-grid now, so the choice was between one option and a worse one.
    func addFrameQuestion(to form: NSStackView) {
        form.addArrangedSubview(frameRow())
        form.addArrangedSubview(caption(
            "Pick a colour your artwork never uses. Everything that is not frame is "
            + "filled with it and removed on load, so a green frame keyed on green "
            + "erases itself."
        ))
    }

    /// What the four avatars are for, shown while the author is deciding rather
    /// than only inside the generated prompt.
    ///
    /// Motion belongs to the two states that are asking for something. The
    /// other column is the part authors get wrong: at 48pt an expression is
    /// invisible, so the state has to be carried by colour and contrast.
    func statesTable() -> NSView {
        let grid = NSGridView(numberOfColumns: 3, rows: 0)
        grid.rowSpacing = 4
        grid.columnSpacing = 14

        func cell(_ text: String, header: Bool = false, strong: Bool = false) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: strong ? .semibold : .regular)
            label.textColor = header || !strong ? .secondaryLabelColor : .labelColor
            return label
        }

        grid.addRow(with: [cell("State", header: true),
                           cell("Motion", header: true),
                           cell("Must read as", header: true)])

        motionCells = []
        let states = [
            ("idle", false, "quiet — dim, cool, recedes"),
            ("working", true, "busy — moving, cool blue"),
            ("needs input", true, "STOP — warmest, highest contrast"),
            ("done", false, "finished — settled green")
        ]
        for (name, animates, reads) in states {
            let motion = cell("still")
            if animates { motionCells.append(motion) }
            grid.addRow(with: [cell(name, strong: true), motion, cell(reads, strong: name == "needs input")])
        }
        updateMotionCells()

        // NSGridView fills whatever it is given, which flung the two right-hand
        // columns to the far edge of the window. A spacer beside it takes the
        // slack so the table keeps its natural width at the leading edge.
        grid.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [grid, spacer])
        row.orientation = .horizontal
        row.distribution = .fill
        row.spacing = 0
        return row
    }

    /// The two attention states follow the checkbox; the resting two never do.
    func updateMotionCells() {
        let animated = animateBox.state == .on
        for cell in motionCells {
            cell.stringValue = animated ? "animated" : "still"
            cell.textColor = animated ? .labelColor : .secondaryLabelColor
        }
    }

    func frameRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        // Named by colour rather than hex: the point is picking one the art
        // never uses, which is a question about the art, not about notation.
        for (title, _) in Self.keyColours {
            keyPicker.addItem(withTitle: title)
        }
        keyPicker.target = self
        keyPicker.action = #selector(regenerate)

        row.addArrangedSubview(NSTextField(labelWithString: "Transparent"))
        row.addArrangedSubview(keyPicker)
        return row
    }

    /// A key colour has to be one the artwork never contains, so the choice is
    /// the author's — a green frame keyed on green erases itself.
    static let keyColours = [
        ("Green — unless the art is green", "#00FF00"),
        ("Magenta — unless the art is pink", "#FF00FF"),
        ("Blue — unless the art is blue", "#0000FF")
    ]

    func geometryRow() -> NSView {
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

    func buttonRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let regenerateButton = NSButton(title: "Update", target: self, action: #selector(regenerate))
        // Two pastes, two buttons. Part one is the moods and is often all
        // anybody needs; part two is the frame, and goes into the same
        // conversation once the moods are right.
        let copyButton = NSButton(
            title: "Copy Part 1 — Moods",
            target: self,
            action: #selector(copyPrompt)
        )
        let copyFrameButton = NSButton(
            title: "Copy Part 2 — Frame",
            target: self,
            action: #selector(copyFramePrompt)
        )
        let createButton = NSButton(
            title: "Create Folder",
            target: self,
            action: #selector(createFolder)
        )
        createButton.keyEquivalent = "\r"

        for button in [regenerateButton, copyButton, copyFrameButton, createButton] {
            button.bezelStyle = .rounded
            row.addArrangedSubview(button)
        }
        return row
    }

    func field(_ control: NSTextField, label: String) -> NSView {
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

    func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        // A label does not wrap on its own, so every caption here was one long
        // line running the width of the window and beyond it. They wrap to the
        // form now, which is what let this one be more than a sentence.
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = Self.formWidth
        return label
    }

    /// The form's measure. Capped rather than following the window, so widening
    /// the window gives the prompt the extra room instead of stretching fields.
    static let formWidth: CGFloat = 584

    /// Placeholders double as a worked example, so the window is never a blank
    /// form staring back at you.
    func applyPlaceholders() {
        let example = ThemeBrief.placeholder
        wordsField.placeholderString = example.words.joined(separator: ", ")
        nameField.placeholderString = example.name
        subjectField.placeholderString = example.subject
        styleField.placeholderString = example.style
        moodField.placeholderString = example.mood
        backgroundField.placeholderString = example.background
    }
}
