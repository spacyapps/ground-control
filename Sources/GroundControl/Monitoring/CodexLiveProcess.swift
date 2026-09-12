// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Finds the terminal a **still-running** `codex` process is sitting in, so a
/// Codex row has somewhere to jump to.
///
/// **This is the one place in the app that looks past its own files**, and it
/// is a deliberate, narrow exception to "the app reads; it does not probe"
/// (`docs/ARCHITECTURE.md`). Every other integration gets a tty for free:
/// their hook runs *inside* the CLI's own process, so `cc-notify` can walk
/// straight up from itself. `CodexWatcher` has no such moment — it only ever
/// reads files after the fact, and Codex's own transcripts record no tty,
/// pid, or host at all. Without this, every Codex row fell through
/// `TerminalFocuser`'s last resort and revealed its folder in Finder.
///
/// What makes it cheap enough to justify: `codex` is itself the top-level
/// process (its parent is the shell, not another hook script), so a single
/// `lsof` on its pid gives both its cwd and its controlling tty directly —
/// no multi-hop walk needed to find the tty, only a short one to name the
/// terminal app. Measured live 2026-09-11:
///
/// ```
/// codex  33266  cwd  DIR  …  /Users/you/github/empty2
/// codex  33266   0u  CHR  …  /dev/ttys012
///
/// 33266 17729 codex
/// 17729 17728 -zsh
/// 17728  1407 login
///  1407     1 /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
/// ```
///
/// Bounded on purpose: only processes actually named `codex` are inspected,
/// so when none are running (the common case for an old thread) this costs
/// one `ps` and stops.
///
/// **Matched by `cwd`, which is as precise as the data allows.** A running
/// `codex` does not hold its own rollout file open — checked; it appends and
/// closes — so there is nothing tying a *pid* to a *thread id*, only to a
/// directory. Every thread that ever ran in a folder therefore resolves to
/// whichever `codex` is working there now. For a finished thread that is
/// slightly generous rather than wrong: the click lands on the terminal
/// where Codex is working in that folder, which beats the alternative of
/// falling through to Finder. When no `codex` is running there at all, the
/// row keeps no tty and falls back to the folder, which is the honest
/// answer for a session that no longer exists.
enum CodexLiveProcess {
    struct Match: Equatable {
        let tty: String?
        let hostApp: String?
        let hostID: String?
    }

    /// How long a lookup stands before it is worth asking the system again.
    ///
    /// The poll that drives this runs every 3s and mostly finds nothing has
    /// changed; a terminal's tty does not move under a running process, and
    /// a `codex` that starts is picked up on the next expiry at worst. So
    /// this is the difference between a `ps` every 3 seconds forever and one
    /// every 15 — for a value that changes when someone opens a terminal.
    static let cacheLifetime: TimeInterval = 15

    private static var cached: (taken: Date, processes: [(pid: Int32, cwd: String, tty: String?)])?

    /// Every running `codex`, by pid and cwd — one `ps`, then one `lsof`
    /// each, at most once per `cacheLifetime`. Main-thread only, like the
    /// timer that calls it.
    static func all(
        now: Date = Date(),
        runner: (([String]) -> String?) = CodexLiveProcess.run
    ) -> [(pid: Int32, cwd: String, tty: String?)] {
        if let cached, now.timeIntervalSince(cached.taken) < cacheLifetime {
            return cached.processes
        }
        let found = lookUp(runner: runner)
        cached = (now, found)
        return found
    }

    /// Forgets the cache — for tests, and for anything that knows the world
    /// just changed.
    static func clearCache() { cached = nil }

    private static func lookUp(runner: (([String]) -> String?)) -> [(pid: Int32, cwd: String, tty: String?)] {
        guard let listing = runner(["/bin/ps", "-eo", "pid=,comm="]) else { return [] }
        // No `codex` running is the common case for a folder whose session
        // has ended: one `ps`, no `lsof` at all, done.
        return pids(fromPS: listing).compactMap { pid in
            guard let lsof = runner(["/usr/sbin/lsof", "-p", String(pid)]),
                  let found = cwdAndTTY(fromLsof: lsof)
            else { return nil }
            return (pid, found.cwd, found.tty)
        }
    }

    /// The terminal hosting an already-located `codex` — its tty is already
    /// known from `all()`, so this only walks up to name the app.
    static func terminal(
        forPID pid: Int32, tty: String?, runner: (([String]) -> String?) = CodexLiveProcess.run
    ) -> Match {
        let host = hostApp(forPID: pid, runner: runner)
        return Match(tty: tty, hostApp: host?.path, hostID: host?.bundleID)
    }

    // MARK: - Pure parsing, tested from captured output

    /// `ps -eo pid=,comm=` lines, keeping only processes named exactly
    /// `codex` — never `Code Helper`, `codex-something`, or anything that
    /// merely contains it.
    static func pids(fromPS listing: String) -> [Int32] {
        listing.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2, fields[1] == "codex", let pid = Int32(fields[0]) else { return nil }
            return pid
        }
    }

    /// Default `lsof` output: `COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME`.
    /// The `cwd` row names the working directory; a `CHR` row pointing at
    /// `/dev/ttys…` names the controlling terminal. A path can contain
    /// spaces, so NAME is everything from field 8 on, not just the last one.
    static func cwdAndTTY(fromLsof listing: String) -> (cwd: String, tty: String?)? {
        var cwd: String?
        var tty: String?
        for line in listing.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 9 else { continue }
            let name = fields.dropFirst(8).joined(separator: " ")
            if fields[3] == "cwd" { cwd = name }
            if fields[4] == "CHR", name.hasPrefix("/dev/ttys"), tty == nil { tty = name }
        }
        guard let cwd else { return nil }
        return (cwd, tty)
    }

    /// The **outermost** `.app` in a bundled executable's path — the same
    /// rule `cc-notify` uses, and for the same reason: an Electron helper is
    /// a bundle inside a bundle, and taking the nearest one raises the wrong
    /// app entirely (every Electron app shares
    /// `com.github.Electron.helper`). Requires `.app/Contents/MacOS/` to
    /// appear at all, so an ordinary path that merely contains `.app/` is
    /// not mistaken for a bundle — then takes the *first* `.app/`, which is
    /// the outer one.
    static func appBundlePath(fromCommand command: String) -> String? {
        guard command.contains(".app/Contents/MacOS/") else { return nil }
        guard let outermost = command.range(of: ".app/") else { return nil }
        return String(command[..<outermost.lowerBound]) + ".app"
    }

    // MARK: - Walking up to the terminal

    private static func hostApp(
        forPID pid: Int32, runner: (([String]) -> String?)
    ) -> (path: String, bundleID: String?)? {
        var current = pid
        // Bounded: an ancestry this long is a loop or a surprise, and either
        // way is not worth another syscall.
        for _ in 0..<12 {
            guard let line = runner(["/bin/ps", "-o", "ppid=,comm=", "-p", String(current)]) else { return nil }
            let fields = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard fields.count == 2, let parent = Int32(fields[0]) else { return nil }

            if let path = appBundlePath(fromCommand: String(fields[1])) {
                return (path, Bundle(path: path)?.bundleIdentifier)
            }
            guard parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    /// Never through a shell — the arguments are fixed here, and a shell in
    /// the path is a way for a filename to become a command.
    static func run(_ arguments: [String]) -> String? {
        guard let first = arguments.first else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: first)
        process.arguments = Array(arguments.dropFirst())
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
