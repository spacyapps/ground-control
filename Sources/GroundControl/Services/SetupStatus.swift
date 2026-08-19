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
    /// One switch, because there is one thing to decide: whether Ground
    /// Control is listening at all.
    ///
    /// It was a switch per integration for a while. Two of the three could
    /// never be anything but off — opencode has nothing to turn on, and
    /// Cursor's own agent is an extra almost nobody wants to think about — so
    /// the row that mattered was surrounded by rows that looked broken.
    /// Everything else is now stated underneath as a fact rather than offered
    /// as a control.
    static func summary(sessions: [Session], now: Date = Date()) -> Agent {
        Agent(
            name: "Hooks",
            detected: true,
            registered: mentionsEmitter(claudeSettings),
            lastEvent: latest(in: sessions, sources: ["claude", "grok", "cursor", "opencode"]),
            caveat: nil,
            target: .all
        )
    }

    /// opencode, when it is on the machine. It earns a switch of its own
    /// because it is a genuinely separate decision — a plugin written into
    /// somebody's opencode config — and because, unlike the rows this replaced,
    /// it can actually be turned on.
    static func opencode(sessions: [Session]) -> Agent? {
        guard exists(home.appendingPathComponent(".config/opencode")) else { return nil }
        return Agent(
            name: "opencode",
            detected: true,
            registered: mentionsGroundControl(opencodeConfig),
            lastEvent: latest(in: sessions, sources: ["opencode"]),
            caveat: "Installs a plugin, since opencode has no hook commands. "
                + "It does report while waiting for you, so its rows turn red.",
            target: .opencode
        )
    }

    private static var opencodeConfig: URL {
        let dir = home.appendingPathComponent(".config/opencode")
        let json = dir.appendingPathComponent("opencode.json")
        return exists(json) ? json : dir.appendingPathComponent("opencode.jsonc")
    }

    /// The plugin is named in the config rather than the emitter, so this looks
    /// for a different string than the hook-based agents do.
    private static func mentionsGroundControl(_ url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains("groundcontrol")
    }

    /// What the switch covers, what it also picks up, and what it cannot reach.
    /// Facts, in the order someone wants them: what works, then the surprises.
    static func facts() -> [String] {
        var lines = [
            "Covers Claude Code, Grok, and any agent running in a terminal —",
            "VS Code, Cursor, Warp, Ghostty, iTerm2, Terminal."
        ]
        if exists(cursorHooks) || exists(home.appendingPathComponent(".cursor")) {
            lines.append(mentionsEmitter(cursorHooks)
                ? "Also watching Cursor's Composer chats — they never turn red."
                : "Cursor's Composer chats are not being watched.")
        }
        // Named rather than implied, because Xcode's is the one that looks
        // like it should work: it *is* Claude Code, it can read the hook
        // registrations and reach the emitter, and its entrypoint runs none of
        // them. "An editor's own chat" would not have warned anybody.
        if exists(URL(fileURLWithPath: "/Applications/Xcode.app")) {
            lines.append("Not covered: Xcode's coding assistant, or any editor's own chat.")
        } else {
            lines.append("Not covered: an editor's own chat.")
        }
        return lines
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }
    private static var cursorHooks: URL { home.appendingPathComponent(".cursor/hooks.json") }

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
