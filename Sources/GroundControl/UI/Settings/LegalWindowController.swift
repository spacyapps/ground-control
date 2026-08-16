// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// The licence, the disclaimer, and a plain account of what the app touches.
///
/// Its own window rather than another section of Settings: this is read once
/// and referred back to, not adjusted, and Settings is already a long scroll of
/// controls. A separate window also means the text can be selected and copied,
/// which someone deciding whether to trust a monitor may well want to do.
final class LegalWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Ground Control"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.contentView = Self.content()
    }

    func present() {
        // Accessory apps do not come forward on their own, and a window nobody
        // can see is indistinguishable from a menu item that does nothing.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func content() -> NSView {
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 22, height: 20)
        text.textStorage?.setAttributedString(body())

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.documentView = text
        scroll.autoresizingMask = [.width, .height]
        // Only the text scrolls; the width follows the window so the measure
        // stays readable when someone widens it.
        text.autoresizingMask = [.width]
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        return scroll
    }

    /// Markdown-ish by hand: the sections are known and few, and pulling in a
    /// parser to render four kinds of emphasis would be more machinery than the
    /// text it renders.
    private static func body() -> NSAttributedString {
        let output = NSMutableAttributedString()
        let sections = [
            (LegalText.privacyTitle, LegalText.privacy),
            (LegalText.licenceTitle, LegalText.licence),
            (LegalText.disclaimerTitle, LegalText.disclaimer)
        ]
        for (index, section) in sections.enumerated() {
            if index > 0 { output.append(NSAttributedString(string: "\n\n")) }
            output.append(heading(section.0))
            output.append(NSAttributedString(string: "\n\n"))
            output.append(paragraphs(section.1))
        }
        return output
    }

    private static func heading(_ title: String) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ])
    }

    private static func paragraphs(_ source: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { output.append(NSAttributedString(string: "\n")) }
            output.append(emphasised(bulleted(String(line)), style: pointStyle))
        }
        return output
    }

    /// A hanging indent, so the second line of a point starts under the first
    /// word rather than under the bullet. Without it a wrapped point reads as
    /// two points.
    private static let pointStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 9
        style.headIndent = LegalWindowController.indent
        style.tabStops = [NSTextTab(textAlignment: .left, location: LegalWindowController.indent)]
        return style
    }()

    private static let indent: CGFloat = 15

    /// `- point` becomes `•⇥point`. Anything else is left exactly as written.
    private static func bulleted(_ line: String) -> String {
        guard line.hasPrefix("- ") else { return line }
        return "•\t" + line.dropFirst(2)
    }

    /// Turns `**this**` bold, leaving everything else alone.
    private static func emphasised(_ line: String, style: NSParagraphStyle) -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: 12)
        let bold = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let output = NSMutableAttributedString()
        var isBold = false
        for piece in line.components(separatedBy: "**") {
            if !piece.isEmpty {
                output.append(NSAttributedString(string: piece, attributes: [
                    .font: isBold ? bold : body,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: style
                ]))
            }
            isBold.toggle()
        }
        return output
    }
}
