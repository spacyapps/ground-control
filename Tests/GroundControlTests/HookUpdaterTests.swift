// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Walter Mak

import XCTest
@testable import GroundControl

/// `cc-notify` writes the fields the app draws from, and the two are installed
/// separately — so they drift, and the drift is silent: an older script simply
/// omits fields and the app quietly falls back. That cost a morning once
/// already, when a click landing in Finder turned out to be a binary
/// forty-four seconds newer than the process running it.
final class HookUpdaterTests: XCTestCase {
    private var dir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hookupdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ text: String, to name: String, executable: Bool = true) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        }
        return url
    }

    private func contents(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func testAnOlderEmitterIsReplaced() throws {
        let shipped = try write("#!/usr/bin/python3\n# new\n", to: "bundled")
        let installed = try write("#!/usr/bin/python3\n# old\n", to: "installed")

        XCTAssertTrue(HookUpdater.updateIfNeeded(bundled: shipped, installed: installed))
        XCTAssertEqual(try contents(installed), try contents(shipped))
    }

    /// The hook stops running silently without it, which is the very failure
    /// this is meant to end.
    func testTheExecutableBitSurvives() throws {
        let shipped = try write("#!/usr/bin/python3\n# new\n", to: "bundled")
        let installed = try write("#!/usr/bin/python3\n# old\n", to: "installed")

        HookUpdater.updateIfNeeded(bundled: shipped, installed: installed)

        let mode = try FileManager.default
            .attributesOfItem(atPath: installed.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.int16Value, 0o755)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installed.path))
    }

    func testAnIdenticalEmitterIsLeftAlone() throws {
        let same = "#!/usr/bin/python3\n# same\n"
        let shipped = try write(same, to: "bundled")
        let installed = try write(same, to: "installed")

        XCTAssertFalse(HookUpdater.updateIfNeeded(bundled: shipped, installed: installed))
    }

    /// No `cc-notify` means the installer was never run. Putting one in
    /// somebody's `~/bin` uninvited is not this app's business, and would not
    /// help anyway — nothing would be registered to call it.
    func testItNeverInstallsWhereNothingWasInstalled() throws {
        let shipped = try write("#!/usr/bin/python3\n", to: "bundled")
        let absent = dir.appendingPathComponent("not-there")

        XCTAssertFalse(HookUpdater.updateIfNeeded(bundled: shipped, installed: absent))
        XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
    }

    /// Running from a checkout rather than a bundle: nothing shipped, nothing
    /// to do, and certainly nothing to break.
    func testNoBundledCopyIsHarmless() throws {
        let installed = try write("#!/usr/bin/python3\n# mine\n", to: "installed")

        XCTAssertFalse(HookUpdater.updateIfNeeded(bundled: nil, installed: installed))
        XCTAssertEqual(try contents(installed), "#!/usr/bin/python3\n# mine\n")
    }
}
