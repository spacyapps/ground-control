// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// Claude for Desktop runs several conversations in one window, so raising the
/// app lands on whichever was last open — rarely the row that was clicked. Its
/// own `claude://code/continue?session=local_…` opens a named one, and the join
/// from the hook's session id to that name is a `cliSessionId` field in a small
/// JSON the app writes for itself.
///
/// That file belongs to somebody else and is undocumented, so every one of
/// these checks is really the same question: when it is not what we expect,
/// does the click still land somewhere?
final class ClaudeDesktopSessionsTests: XCTestCase {
    private var root = FileManager.default.temporaryDirectory
    private var workspace = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-desktop-\(UUID().uuidString)")
        // <root>/<account>/<workspace>/local_*.json — two levels, as the app
        // lays it out.
        workspace = root
            .appendingPathComponent("account-uuid")
            .appendingPathComponent("workspace-uuid")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(local: String, cli: String, archived: Bool = false, title: String = "A session") throws {
        let json = """
        {"sessionId":"\(local)","cliSessionId":"\(cli)","isArchived":\(archived),
         "title":"\(title)","cwd":"/Users/you/project","lastActivityAt":1789863396319}
        """
        try json.write(
            to: workspace.appendingPathComponent("\(local).json"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - The join

    func testFindsTheDesktopIdForAHookSessionID() throws {
        try write(local: "local_55150fef-abc6-4237-bb1b-9d62af45c67c",
                  cli: "dc7b3130-2274-4075-b1ef-13e60ba1404d")

        XCTAssertEqual(
            ClaudeDesktopSessions.localSessionID(
                for: "dc7b3130-2274-4075-b1ef-13e60ba1404d", in: root
            ),
            "local_55150fef-abc6-4237-bb1b-9d62af45c67c"
        )
    }

    func testPicksTheRightSessionOutOfSeveral() throws {
        try write(local: "local_aaaaaaaa-0000-0000-0000-000000000001", cli: "cli-one")
        try write(local: "local_bbbbbbbb-0000-0000-0000-000000000002", cli: "cli-two")
        try write(local: "local_cccccccc-0000-0000-0000-000000000003", cli: "cli-three")

        XCTAssertEqual(
            ClaudeDesktopSessions.localSessionID(for: "cli-two", in: root),
            "local_bbbbbbbb-0000-0000-0000-000000000002"
        )
    }

    /// The app's own handler filters archived sessions out, so a link naming
    /// one opens nothing and reads as a dead click. Better to raise the app.
    func testSkipsAnArchivedSession() throws {
        try write(local: "local_dddddddd-0000-0000-0000-000000000004", cli: "cli-old", archived: true)

        XCTAssertNil(ClaudeDesktopSessions.localSessionID(for: "cli-old", in: root))
    }

    // MARK: - Every way it can be absent

    func testAnUnknownSessionFindsNothing() throws {
        try write(local: "local_eeeeeeee-0000-0000-0000-000000000005", cli: "cli-known")

        XCTAssertNil(ClaudeDesktopSessions.localSessionID(for: "cli-unknown", in: root))
    }

    func testAMissingFolderFindsNothing() {
        let gone = root.appendingPathComponent("not-here")

        XCTAssertNil(ClaudeDesktopSessions.localSessionID(for: "cli-one", in: gone))
    }

    func testUnreadableJSONFindsNothingRatherThanThrowing() throws {
        try "{ this is not json".write(
            to: workspace.appendingPathComponent("local_broken.json"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertNil(ClaudeDesktopSessions.localSessionID(for: "cli-one", in: root))
    }

    /// If the app ever renames its own ids, the link must not be built: its URL
    /// handler validates the shape and would simply ignore us.
    func testAnIdThatIsNotTheirShapeIsRefused() throws {
        try write(local: "session_something-else", cli: "cli-shape")

        XCTAssertNil(ClaudeDesktopSessions.localSessionID(for: "cli-shape", in: root))
        XCTAssertNil(ClaudeDesktopSessions.continueURL(localSessionID: "session_something-else"))
    }

    func testAnEmptySessionIDIsRefused() {
        XCTAssertNil(ClaudeDesktopSessions.localSessionID(for: "", in: root))
    }

    // MARK: - The link

    func testTheLinkIsTheAppsOwnRoute() throws {
        let url = try XCTUnwrap(
            ClaudeDesktopSessions.continueURL(localSessionID: "local_55150fef-abc6-4237-bb1b-9d62af45c67c")
        )

        XCTAssertEqual(url.scheme, "claude")
        XCTAssertEqual(url.absoluteString,
                       "claude://code/continue?session=local_55150fef-abc6-4237-bb1b-9d62af45c67c"
                       + "&source=groundcontrol")
    }

    // MARK: - Where a click lands

    func testAClaudeDesktopRowGoesToItsOwnConversation() {
        let probe = TerminalFocuser.Probe(
            isBundleRunning: { _ in true },
            bundleID: { _ in ClaudeDesktopSessions.bundleID },
            claudeDesktopSession: { _ in "local_55150fef-abc6-4237-bb1b-9d62af45c67c" }
        )

        XCTAssertEqual(
            TerminalFocuser.destination(
                tty: nil,
                hostApp: "/Applications/Claude.app",
                hostID: ClaudeDesktopSessions.bundleID,
                fallbackPath: "/Users/you/project",
                sessionID: "dc7b3130",
                probe: probe
            ),
            .claudeDesktopSession(localID: "local_55150fef-abc6-4237-bb1b-9d62af45c67c")
        )
    }

    /// The whole point of the fallback: an app that has moved its storage, or
    /// a session it has not written yet, must not cost you the click.
    func testAnUnresolvedSessionStillRaisesTheApp() {
        let probe = TerminalFocuser.Probe(
            isBundleRunning: { _ in true },
            bundleID: { _ in ClaudeDesktopSessions.bundleID },
            claudeDesktopSession: { _ in nil }
        )

        XCTAssertEqual(
            TerminalFocuser.destination(
                tty: nil,
                hostApp: "/Applications/Claude.app",
                hostID: ClaudeDesktopSessions.bundleID,
                fallbackPath: "/Users/you/project",
                sessionID: "dc7b3130",
                probe: probe
            ),
            .application(bundleID: ClaudeDesktopSessions.bundleID)
        )
    }

    /// Only Claude for Desktop. A terminal session keeps its tab, which is a
    /// better landing than any app-level jump.
    func testATerminalSessionIsUntouchedByThis() {
        let probe = TerminalFocuser.Probe(
            isBundleRunning: { $0 == "com.apple.Terminal" },
            bundleID: { _ in "com.apple.Terminal" },
            claudeDesktopSession: { _ in "local_should-not-be-used" }
        )

        XCTAssertEqual(
            TerminalFocuser.destination(
                tty: "/dev/ttys004",
                hostApp: "/System/Applications/Utilities/Terminal.app",
                hostID: "com.apple.Terminal",
                fallbackPath: nil,
                sessionID: "dc7b3130",
                probe: probe
            ),
            .terminalTab(tty: "/dev/ttys004", bundleID: "com.apple.Terminal")
        )
    }
}
