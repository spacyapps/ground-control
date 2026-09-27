# Ground Control — notes for Claude

A macOS app (Swift Package Manager, AppKit, macOS 13+) that watches the session
files agent CLIs write and shows one row per session in a floating panel. It
never talks to an agent directly; `docs/ARCHITECTURE.md` explains the pipeline.

## Build, test, lint

- `swift build` / `swift test`
- `swiftlint --strict` — CI runs it, and the local pre-commit hook runs it over
  the whole project. Git hooks live in `.git/hooks` and do not travel with a
  clone; `docs/CONTRIBUTING-NOTES.md` has both.
- `./Scripts/build-app.sh` — builds `GroundControl.app`.
- `./Scripts/build-zip.sh`, `./Scripts/build-dmg.sh` — notarise and staple a
  distributable. They publish an artefact: confirm before running either.
- `./Scripts/licence-audit.sh` — run before every release.

## Where to look

- `docs/STRUCTURE.md`       -> file-by-file layout (read before adding a file)
- `docs/ARCHITECTURE.md`    -> how a row appears, watcher to panel
- `docs/HOOK-PAYLOADS.md`   -> Claude Code payloads, measured live (trust over vendor docs)
- `docs/CODEX-*`, `GROK-*`  -> the same, per other CLI
- `docs/THEMING.md`         -> manifest keys and the art rules each one enforces
- `docs/LIMITATIONS.md`     -> dated claims, verified vs only believed
- `docs/SPEC.md`            -> the original build spec; older than the code, so check both

## Rules

- **No third-party dependencies.** Deliberate; `Package.swift` says why.
- **No network code.** The app's privacy claims depend on it — nothing in
  `Sources/` may open a connection.
- **Every source file carries the SPDX header**: `AGPL-3.0-or-later`,
  `Copyright (c) 2026 Walter Mak`.
- **Probe a CLI's real hook payload before writing integration code for it.**
  Code written from documentation alone has failed silently here twice.
- **This repository is public.** `Themes/` holds only the themes that ship with
  the app; paid and private themes live outside it and are never copied in.
