// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
import AppKit
@testable import GroundControl

/// What the row menu says about a session.
///
/// A Cursor row never turns red, and nothing on screen explains why — the panel
/// looks broken rather than limited. The menu is where someone asks the
/// question, so it is where the answer belongs.
@MainActor
final class ContextMenuTests: XCTestCase {
    private func session(source: String, needsAction: Bool = false) throws -> Session {
        let json = """
        {"session_id":"s1","source":"\(source)","name":"empty","cwd":"/tmp/empty",\
        "state":"working","needs_action":\(needsAction),"ts":1}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        return Session(id: event.sessionID, latest: event, children: [], acknowledgedAt: nil)
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    func testACursorRowExplainsWhyItNeverTurnsRed() throws {
        let menu = AppCoordinator().contextMenu(for: try session(source: "cursor"))
        XCTAssertTrue(titles(menu).contains("Agent: limited support"))
        XCTAssertTrue(titles(menu).contains("No alert when it waits for approval"))
    }

    /// The note explains; it must never look like something you failed to click.
    func testTheNoteIsNotAnAction() throws {
        let menu = AppCoordinator().contextMenu(for: try session(source: "cursor"))
        let note = menu.items.first { $0.title == "Agent: limited support" }
        XCTAssertNotNil(note?.attributedTitle, "a plain title reads as a disabled action")
        XCTAssertNil(note?.action, "it must not be selectable")
        XCTAssertFalse(note?.isEnabled ?? true)
    }

    /// Claude and Grok have a working alarm, so the note would be a lie there —
    /// and a menu that carries a caveat on every row teaches people to skip it.
    func testOtherCLIsCarryNoNote() throws {
        for source in ["claude", "grok"] {
            let menu = AppCoordinator().contextMenu(for: try session(source: source))
            XCTAssertFalse(
                titles(menu).contains { $0.hasPrefix("Agent:") },
                "\(source) rows should carry no caveat"
            )
        }
    }

    /// The wording never names the CLI. The row already says which one, and the
    /// next editor agent to arrive should need no new string.
    func testTheNoteDoesNotNameTheCLI() throws {
        let menu = AppCoordinator().contextMenu(for: try session(source: "cursor"))
        for title in titles(menu).dropFirst() where title.hasPrefix("Agent") {
            XCTAssertFalse(title.lowercased().contains("cursor"), title)
        }
    }

    /// The actions stay first and unchanged: the note is an addition, not a
    /// rearrangement of a menu people already know.
    func testTheActionsComeFirstAndAreUnchanged() throws {
        let menu = AppCoordinator().contextMenu(for: try session(source: "cursor"))
        XCTAssertEqual(
            Array(titles(menu).prefix(6)),
            ["Jump to Terminal", "Reveal in Finder", "Dismiss Alert",
             "Copy Path", "Rename…", "Remove Row"]
        )
    }
}
