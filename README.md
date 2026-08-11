# SkinTerminal

A macOS menu-bar app that monitors your Claude CLI sessions and shows, at a
glance, which ones need your attention — with a WinAmp-style skinnable UI
(themes as image/video bundles).

- **Menu-bar icon** that badges when a session needs you.
- **Free-floating panel** (optional always-on-top / all-Spaces) listing each
  session: name, latest message, a red dot when it needs action, and a
  themeable avatar.
- **Click a session** to jump straight to its terminal tab.
- **Skinnable** via drop-in theme folders (`Themes/<name>/theme.json`).

> Status: early. This repo ships the **scaffold, spec, and a working
> `cc-notify`** — the hook side is built and verified against live payloads.
> The Swift app is not written yet. See `docs/SPEC.md` for the build plan and
> `docs/STRUCTURE.md` for the code layout.

## Build (from source)

```bash
swift build
swift run
```

Requires macOS 13+ and Swift 5.9+. SwiftLint runs as a build plugin.

## How it works

Claude Code hooks call a small script (`Scripts/cc-notify`) that writes one
`.jsonl` file per session into a temp folder, named by the session's id. The
app watches that folder — **file exists ⇔ row exists** — and shows the last
line of each file as that session's current state. Files untouched for 24h are
purged automatically.

Rows show what Claude actually said, not a generic status: the `Stop` hook
hands over the full assistant message, and `Notification` carries the real
"waiting for you" text.

```bash
./Scripts/install-hooks.sh    # installs cc-notify + merges into ~/.claude/settings.json
```

It **merges** — existing hooks on the same events keep working — and backs up
your settings first. Hooks take effect immediately; no restart.

Works with **Claude Code** and **Grok** today — Grok reads `~/.claude/settings.json`
by design, so one install covers both. The app itself is CLI-agnostic; only the
emitter script knows anything about a vendor.

See `docs/SPEC.md` §3 for the event contract, `docs/HOOK-PAYLOADS.md` for the
measured payloads it is built on, and `docs/LIMITATIONS.md` for what is proven
versus merely believed.

## Themes

Copy `Themes/default/` and edit `theme.json`. Everything is optional — the app
fills in defaults. Full guide: `docs/THEMING.md`.

## Install (non-developers)

Download the `.dmg` from Releases, drag to Applications, then **right-click →
Open** the first time (the build is unsigned/open-source).

## License

MIT — see `LICENSE`.
