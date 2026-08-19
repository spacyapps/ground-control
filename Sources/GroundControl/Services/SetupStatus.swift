// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Whether each agent is actually wired up, and whether anything has ever
/// arrived from it.
///
/// "It doesn't work" is the commonest report this project gets, and answering it
/// has always meant a conversation. Every cause so far has been visible from the
/// outside: a registration written to a path with a space in it, an emitter left
/// behind by an older install, an agent that fires no hook at the moment it
/// matters, or a CLI that was never supported at all.
///
/// The load-bearing line is the last one — **has anything arrived?** A
/// registration proves a file was written, not that the file is ever run. Those
/// came apart once and cost an evening.
enum SetupStatus {
    struct Agent: Equatable {
        let name: String
        /// Its own configuration exists on this Mac, so the CLI is presumably
        /// installed. Absence is not a fault; most people run one or two.
        let detected: Bool
        /// Our emitter appears in that configuration.
        let registered: Bool
        /// Nil when nothing has been seen, otherwise how long ago.
        let lastEvent: Date?
        /// Said out loud where an agent cannot do something, so a missing alarm
        /// reads as a known limit rather than a broken install.
        let caveat: String?
        /// What a switch would install or remove, or nil where there is nothing
        /// to switch — Grok rides Claude Code's registration, and opencode has
        /// no integration to turn on yet.
        let target: HookInstaller.Target?
    }

    /// Everything the panel can currently speak to, in the order a person is
    /// likely to care about.
    static func agents(sessions: [Session], now: Date = Date()) -> [Agent] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claude = home.appendingPathComponent(".claude/settings.json")
        let cursor = home.appendingPathComponent(".cursor/hooks.json")
        let opencode = home.appendingPathComponent(".config/opencode")

        return [
            // One switch, because one registration serves both: Grok reads
            // Claude Code's settings file by design. Two switches would imply
            // they could be turned on separately, and one of them would be a lie.
            Agent(
                name: "Claude Code & Grok",
                detected: exists(claude),
                registered: mentionsEmitter(claude),
                lastEvent: latest(in: sessions, sources: ["claude", "grok"]),
                caveat: nil,
                target: .claude
            ),
            Agent(
                name: "Cursor",
                detected: exists(cursor) || exists(home.appendingPathComponent(".cursor")),
                registered: mentionsEmitter(cursor),
                lastEvent: latest(in: sessions, sources: ["cursor"]),
                caveat: "Its own agent fires no hook while waiting for approval, "
                    + "so those rows never turn red.",
                target: .cursor
            ),
            Agent(
                name: "opencode",
                detected: exists(opencode),
                registered: false,
                lastEvent: latest(in: sessions, sources: ["opencode"]),
                caveat: "Not supported yet — it uses plugins rather than hook commands.",
                target: nil
            )
        ]
    }

    /// The emitter the app installed, and whether it still matches the app.
    ///
    /// These drift silently: an older script omits fields and the panel simply
    /// falls back, so nothing looks wrong.
    /// `current` is nil when the question cannot be answered — outside the app
    /// bundle there is nothing to compare against, and saying "out of date"
    /// because the comparison failed would be a false alarm in the one place
    /// people go to find out whether something is wrong.
    static func emitter() -> (installed: Bool, current: Bool?) {
        let installed = FileManager.default.fileExists(atPath: HookUpdater.installed.path)
        guard installed,
              let bundled = HookUpdater.bundled,
              let ours = try? Data(contentsOf: bundled) else { return (installed, nil) }
        let theirs = try? Data(contentsOf: HookUpdater.installed)
        return (true, ours == theirs)
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Reads the file rather than parsing it: the two configurations have
    /// different shapes, and all that is being asked is whether our command
    /// appears anywhere in it.
    private static func mentionsEmitter(_ url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains("cc-notify")
    }

    private static func latest(in sessions: [Session], sources: [String]) -> Date? {
        sessions.filter { sources.contains($0.source) }.map(\.lastActivity).max()
    }
}
