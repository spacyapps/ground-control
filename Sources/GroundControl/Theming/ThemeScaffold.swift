// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Creates a theme folder with a ready `theme.json`, so the only thing left to
/// do is drop in the artwork the LLM produced.
///
/// Writing the manifest here rather than asking the author to save it means the
/// folder name, the theme name and the filenames referenced by the manifest are
/// guaranteed to agree — the three things most likely to be mistyped.
enum ThemeScaffold {
    enum Failure: LocalizedError {
        case alreadyExists(String)

        var errorDescription: String? {
            switch self {
            case .alreadyExists(let name):
                return "A theme folder named “\(name)” already exists."
            }
        }
    }

    @discardableResult
    static func create(from brief: ThemeBrief, in directory: URL = Paths.userThemes) throws -> URL {
        let folder = directory.appendingPathComponent(brief.slug, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            throw Failure.alreadyExists(brief.slug)
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ThemeStarterManifest.text(for: brief)
            .write(to: folder.appendingPathComponent("theme.json"), atomically: true, encoding: .utf8)

        // The prompt goes in beside it: the folder becomes self-describing, and
        // the author can re-open it later to iterate without rebuilding the brief.
        // Two files, because one file gets pasted whole. The prompt tells the
        // model to do the moods and stop, and then — in the same paste — showed
        // it the nine-grid, the manifest and a set of example colours. It
        // reported the contradiction rather than falling for it, and was right
        // to: staging that only exists in the text is not staging.
        try ThemePromptBuilder.partOne(for: brief).write(
            to: folder.appendingPathComponent("PROMPT-1-moods.md"),
            atomically: true,
            encoding: .utf8
        )
        try ThemePromptBuilder.partTwo(for: brief).write(
            to: folder.appendingPathComponent("PROMPT-2-frame.md"),
            atomically: true,
            encoding: .utf8
        )

        return folder
    }
}
