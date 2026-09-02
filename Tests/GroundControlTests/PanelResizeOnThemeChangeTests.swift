// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// `free` means the height is the person's — a drag sets it and nothing takes
/// it back. The one exception is changing themes: a switch should land the new
/// skin near its own content, not at whatever height the last one was left at.
@MainActor
final class PanelResizeOnThemeChangeTests: XCTestCase {
    private func freeSkin(insetTop: CGFloat) -> Theme {
        var theme = DefaultTheme.theme
        theme.layout.resize = .free
        theme.layout.contentInset = NSEdgeInsets(top: insetTop, left: 20, bottom: 20, right: 20)
        theme.window = Theme.Window(
            shape: BackgroundImage(
                url: URL(fileURLWithPath: "/x.gif"), mode: .tile, capInsets: NSEdgeInsets()
            ),
            locksAspect: false,
            aspectRatio: 1
        )
        return theme
    }

    private func idleSession(_ id: String) throws -> Session {
        let json = """
        {"session_id":"\(id)","source":"claude","name":"\(id)","cwd":"/tmp/\(id)",\
        "state":"idle","needs_action":false,"ts":1}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        return Session(id: event.sessionID, latest: event, children: [], acknowledgedAt: nil)
    }

    private func controller() throws -> PanelController {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "themeSwitch-\(UUID().uuidString)"))
        return PanelController(preferences: Preferences(defaults: defaults))
    }

    func testAThemeSwitchRefitsAFreePanelToItsRows() throws {
        let controller = try controller()
        controller.show()
        let panel = try XCTUnwrap(controller.panel)
        try XCTSkipUnless(panel.isVisible, "no window server")

        controller.apply(sessions: [
            try idleSession("a"), try idleSession("b"), try idleSession("c")
        ])
        controller.apply(theme: freeSkin(insetTop: 40))
        let fitted = panel.frame.height

        // A drag stretches it well past its content.
        var stretched = panel.frame
        stretched.size.height = fitted + 400
        panel.setFrame(stretched, display: false)

        // Switching themes is the one moment that takes that back.
        controller.apply(theme: freeSkin(insetTop: 40))
        XCTAssertEqual(panel.frame.height, fitted, accuracy: 8, "the switch refit to the rows")
    }

    func testASessionUpdateLeavesADraggedFreeHeightAlone() throws {
        let controller = try controller()
        controller.show()
        let panel = try XCTUnwrap(controller.panel)
        try XCTSkipUnless(panel.isVisible, "no window server")

        controller.apply(theme: freeSkin(insetTop: 40))
        controller.apply(sessions: [try idleSession("a")])

        var stretched = panel.frame
        stretched.size.height += 300
        panel.setFrame(stretched, display: false)
        let dragged = panel.frame.height

        controller.apply(sessions: [try idleSession("a"), try idleSession("b")])
        XCTAssertEqual(panel.frame.height, dragged, accuracy: 0.5, "a free height is the person's")
    }

    /// First launch: a saved frame from a previous session can be far too short
    /// for the current skin, and the resize grip that would fix it is easy to
    /// lose in the artwork — so the first `show()` refits like a theme switch.
    func testFirstLaunchRefitsASquishedFreePanel() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "launch-\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults)
        preferences.panelFrame = NSStringFromRect(NSRect(x: 100, y: 400, width: 360, height: 110))
        let controller = PanelController(preferences: preferences)

        // The launch order: theme, then sessions, then the panel appears.
        controller.apply(theme: freeSkin(insetTop: 40))
        controller.apply(sessions: [
            try idleSession("a"), try idleSession("b"), try idleSession("c")
        ])
        controller.show()
        let panel = try XCTUnwrap(controller.panel)
        try XCTSkipUnless(panel.isVisible, "no window server")

        XCTAssertGreaterThan(panel.frame.height, 200, "the squished panel grew to fit its rows")
        XCTAssertEqual(panel.frame.width, 360, accuracy: 0.5, "the saved width is kept")
    }

    /// Reopening the panel is not a launch — a height the person dragged holds.
    func testReopeningAFreePanelKeepsTheDraggedHeight() throws {
        let controller = try controller()
        controller.apply(theme: freeSkin(insetTop: 40))
        controller.apply(sessions: [try idleSession("a")])
        controller.show()
        let panel = try XCTUnwrap(controller.panel)
        try XCTSkipUnless(panel.isVisible, "no window server")

        var tall = panel.frame
        tall.size.height += 250
        panel.setFrame(tall, display: false)
        let dragged = panel.frame.height

        controller.hide()
        controller.show()
        XCTAssertEqual(panel.frame.height, dragged, accuracy: 0.5, "a toggle-open respects the drag")
    }
}
