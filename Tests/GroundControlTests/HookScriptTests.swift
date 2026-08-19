// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// The installer and the uninstaller edit other people's configuration files.
/// Everything else in this suite is Swift; these two are shell, and they are the
/// part that can do real damage — a bad merge takes someone's own hooks with it,
/// and a bad uninstall leaves a registration pointing at a command that is gone,
/// which fails on every tool use.
///
/// So they are run for real here, against a sandboxed `HOME`.
final class HookScriptTests: XCTestCase {
    private var home = URL(fileURLWithPath: "/tmp")

    private var scripts: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Scripts")
    }

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("hooks-\(UUID().uuidString)")
        for folder in [".claude", ".cursor"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    private func run(_ script: String, _ target: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scripts.appendingPathComponent(script).path, target]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func write(_ json: String, to path: String) throws {
        try json.write(to: home.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    private func read(_ path: String) -> String {
        (try? String(contentsOf: home.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    private func mentions(_ needle: String, in path: String) -> Int {
        read(path).components(separatedBy: needle).count - 1
    }

    // MARK: - Adding only ours

    func testItKeepsHooksSomebodyElsePutThere() throws {
        try write(##"""
        {"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
        """##, to: ".claude/settings.json")

        try run("install-hooks.sh", "claude")

        XCTAssertEqual(
            mentions("say done", in: ".claude/settings.json"),
            1,
            "somebody else's hook was lost"
        )
        XCTAssertTrue(
            read(".claude/settings.json").contains("\"model\": \"opus\""),
            "unrelated settings must survive a merge"
        )
        XCTAssertGreaterThan(mentions("cc-notify", in: ".claude/settings.json"), 0)
    }

    func testRunningItTwiceDoesNotRegisterTwice() throws {
        try write("{}", to: ".claude/settings.json")
        try run("install-hooks.sh", "claude")
        let once = mentions("cc-notify", in: ".claude/settings.json")
        try run("install-hooks.sh", "claude")
        XCTAssertEqual(
            mentions("cc-notify", in: ".claude/settings.json"),
            once,
            "re-running the installer must be safe"
        )
    }

    func testInstallingOneAgentLeavesTheOtherAlone() throws {
        try write("{}", to: ".claude/settings.json")
        try run("install-hooks.sh", "cursor")
        XCTAssertEqual(mentions("cc-notify", in: ".claude/settings.json"), 0)
        XCTAssertGreaterThan(mentions("cc-notify", in: ".cursor/hooks.json"), 0)
    }

    // MARK: - Removing only ours

    func testUninstallLeavesSomebodyElsesHooksBehind() throws {
        try write(##"""
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
        """##, to: ".claude/settings.json")
        try run("install-hooks.sh", "claude")
        try run("uninstall-hooks.sh", "claude")

        XCTAssertEqual(mentions("cc-notify", in: ".claude/settings.json"), 0, "ours should be gone")
        XCTAssertEqual(
            mentions("say done", in: ".claude/settings.json"),
            1,
            "and theirs should not be"
        )
    }

    /// The important one. Older builds installed the emitter to `~/bin`, and
    /// alpha testers still carry those registrations. The uninstaller matches on
    /// the name rather than the path, so any version's leftovers can be cleared
    /// by the current script — otherwise a tester is stranded with a hook
    /// pointing at a command that no longer exists.
    func testItRemovesRegistrationsFromAnyOlderInstall() throws {
        try write(##"""
        {"hooks":{"Stop":[{"hooks":[
          {"type":"command","command":"/Users/someone/bin/cc-notify"},
          {"type":"command","command":"~/Library/Application Support/GroundControl/bin/cc-notify"},
          {"type":"command","command":"say done"}
        ]}]}}
        """##, to: ".claude/settings.json")

        try run("uninstall-hooks.sh", "claude")

        XCTAssertEqual(
            mentions("cc-notify", in: ".claude/settings.json"),
            0,
            "a registration from any folder is still ours to remove"
        )
        XCTAssertEqual(mentions("say done", in: ".claude/settings.json"), 1)
    }

    // MARK: - The shared emitter

    func testATargetedUninstallKeepsTheEmitterForTheOthers() throws {
        try write("{}", to: ".claude/settings.json")
        try run("install-hooks.sh", "all")
        try run("uninstall-hooks.sh", "cursor")

        let emitter = home.appendingPathComponent(".groundcontrol/bin/cc-notify").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: emitter),
            "Claude Code is still registered and needs it"
        )
        XCTAssertGreaterThan(mentions("cc-notify", in: ".claude/settings.json"), 0)
    }

    func testUninstallingEverythingRemovesTheEmitter() throws {
        try write("{}", to: ".claude/settings.json")
        try run("install-hooks.sh", "all")
        try run("uninstall-hooks.sh", "all")

        let emitter = home.appendingPathComponent(".groundcontrol/bin/cc-notify").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: emitter))
        XCTAssertEqual(mentions("cc-notify", in: ".claude/settings.json"), 0)
        XCTAssertEqual(mentions("cc-notify", in: ".cursor/hooks.json"), 0)
    }

    /// Both scripts back up before they touch anything, because they are editing
    /// a file the user did not ask them to edit.
    func testItBacksUpBeforeEditing() throws {
        try write(##"{"model":"opus"}"##, to: ".claude/settings.json")
        try run("install-hooks.sh", "claude")

        let backups = try FileManager.default
            .contentsOfDirectory(atPath: home.appendingPathComponent(".claude").path)
            .filter { $0.contains("settings.json.bak-") }
        XCTAssertFalse(backups.isEmpty, "no backup was taken")
    }

    /// Uninstalling twice must not leave two backups. Ten copies of an empty
    /// hooks.json turned up in a real ~/.cursor after a few flicks of the
    /// switch, because the uninstaller backed up whether or not it had anything
    /// to remove.
    func testItDoesNotBackUpWhenThereIsNothingOfOursToRemove() throws {
        try write(##"""
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
        """##, to: ".claude/settings.json")

        for _ in 0..<3 { try run("uninstall-hooks.sh", "claude") }

        let backups = try FileManager.default
            .contentsOfDirectory(atPath: home.appendingPathComponent(".claude").path)
            .filter { $0.contains("settings.json.bak-") }
        XCTAssertTrue(backups.isEmpty, "nothing of ours was there, so nothing needed backing up")
        XCTAssertEqual(mentions("say done", in: ".claude/settings.json"), 1)
    }

    /// And when there is something to remove, the backups are kept to three,
    /// the same as the installer keeps them.
    func testBackupsAreKeptToThree() throws {
        for _ in 0..<5 {
            try write("{}", to: ".claude/settings.json")
            try run("install-hooks.sh", "claude")
            try run("uninstall-hooks.sh", "claude")
        }
        let backups = try FileManager.default
            .contentsOfDirectory(atPath: home.appendingPathComponent(".claude").path)
            .filter { $0.contains("settings.json.bak-") }
        XCTAssertLessThanOrEqual(backups.count, 3, "backups piled up: \(backups.count)")
    }
}
