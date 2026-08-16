// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// "Create a Theme…": a few questions, then a prompt to paste into an
/// image-capable LLM, and a folder already waiting for the results.
final class ThemeBuilderWindowController: NSWindowController {
    let nameField = NSTextField(string: "")
    let subjectField = NSTextField(string: "")
    let styleField = NSTextField(string: "")
    let moodField = NSTextField(string: "")
    let backgroundField = NSTextField(string: "")
    let wordsField = NSTextField(string: "")
    let animateBox = NSButton()
    let sizeField = NSTextField(string: "48")
    let framePicker = NSPopUpButton()
    /// The motion cells, kept so the table can answer the animation checkbox
    /// rather than describing a fixed arrangement.
    var motionCells: [NSTextField] = []
    let keyPicker = NSPopUpButton()
    let positionPicker = NSPopUpButton()
    let promptView = NSTextView()
    let statusLabel = NSTextField(labelWithString: "")

    let onThemesChanged: () -> Void

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
            position: positionPicker.titleOfSelectedItem ?? "right",
            // Filtered by the same rule the loader uses, so what the field
            // accepts and what the display can draw cannot disagree.
            words: MatrixMessages.usable(
                wordsField.stringValue.split(separator: ",").map(String.init)
            )
        )
    }

    // MARK: - Actions

    @objc func regenerate() {
        updateMotionCells()
        promptView.string = ThemePromptBuilder.prompt(for: brief)
        statusLabel.stringValue = ""
    }

    @objc func copyPrompt() {
        regenerate()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(promptView.string, forType: .string)
        statusLabel.stringValue = "Prompt copied — paste it into your LLM."
    }

    @objc func createFolder() {
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
