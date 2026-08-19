// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation
import XCTest
import AppKit

/// Where themes live, for tests that need real artwork.
///
/// Two places, and the split is a licensing one rather than a tidiness one.
/// `Themes/` ships inside the app and inside this repository. Everything else
/// is artwork licensed separately from the code, kept outside the repository
/// entirely so that a public clone cannot be read as licensing it under the
/// AGPL — see `docs/THEME-DELIVERY.md`.
///
/// The consequence for tests: extra themes are present on the machine that
/// draws them and absent everywhere else, so a test that needs one must skip
/// rather than fail. A clone with no artwork is the normal case, not a broken
/// checkout.
enum ThemeLocations {
    /// Repo root, derived from this file rather than the working directory,
    /// which differs between `swift test` and Xcode.
    static var repo: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // GroundControlTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
    }

    /// Ships with the app.
    static var shipped: URL { repo.appendingPathComponent("Themes") }

    /// Licensed separately and kept out of the repository. Overridable with
    /// `EXTRA_THEMES_DIR`, the same variable `Scripts/build-app.sh` reads, so
    /// the build and the tests can never disagree about where to look.
    static var extra: URL {
        if let override = ProcessInfo.processInfo.environment["EXTRA_THEMES_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Projects/GroundControlThemes")
    }

    static var roots: [URL] { [shipped, extra] }

    /// A named theme folder if it is on this machine, otherwise nil.
    static func folder(named name: String) -> URL? {
        roots
            .map { $0.appendingPathComponent(name) }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("theme.json").path) }
    }
}

/// The folder, or a skipped test — never a failure.
///
/// Absent artwork is the normal state of a clone, so a test that needs the real
/// thing has to stand down rather than go red.
func requiredThemeFolder(named name: String) throws -> URL {
    guard let folder = ThemeLocations.folder(named: name) else {
        throw XCTSkip("\(name) is artwork licensed separately; not on this machine")
    }
    return folder
}

/// Stands a test down where AppKit cannot lay text out.
///
/// CI runs on a hosted macOS runner with no logged-in GUI session, and there
/// `NSTextField` reports no useful size — so any assertion about a measured
/// height fails for a reason that has nothing to do with the code. The same
/// shape as skipping when artwork is absent: the environment is not wrong, it
/// simply cannot answer the question.
func requiresWindowServer() throws {
    if ProcessInfo.processInfo.environment["CI"] != nil {
        throw XCTSkip("no GUI session on CI; text cannot be laid out")
    }
    if NSScreen.screens.isEmpty {
        throw XCTSkip("no screen attached; text cannot be laid out")
    }
}
