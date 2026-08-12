# Ground Control

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

Requires macOS 13+ and Swift 5.9+. **No third-party dependencies** — the app
imports only AppKit, AVFoundation, Foundation and os. Linting uses the
standalone `swiftlint` binary (`brew install swiftlint`).

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
fills in defaults.

`Themes/spacyAppsLunarAvatar/` is a complete example: per-state avatars, a
shaped window whose antennae extend past the panel edge, and its own matrix
messages. Full guide: `docs/THEMING.md`.

A skin can go **behind** the rows or **in front of** them (`window.overlay`),
which is how a picture frame overlaps its own contents. Artwork arrives from
image models without usable alpha, so `removeBackground` chroma-keys it at load
and suppresses the rim the key leaves behind. The ✕ and ↔ marks always draw
above the skin, so no theme can hide the only ways to close and resize the
panel.

## Install (non-developers)

**1. Install the app.** Download the `.dmg` from Releases, open it, drag Ground
Control to Applications. It is signed with a Developer ID and notarised by
Apple, so it opens on a double-click — no right-click, no warning.

**2. Wire up your agent CLI.** The panel stays empty until an agent tells it
something, which is what the hooks are for. One command:

```bash
/Applications/GroundControl.app/Contents/Resources/install-hooks.sh
```

That installs `cc-notify` to `~/bin` and registers it in
`~/.claude/settings.json`, backing up the file first. It merges rather than
overwrites, so hooks you already have are kept, and it is safe to re-run.
Claude Code and Grok both read that file and both are covered.

**3. Start a session.** Open a *new* terminal — a CLI already running has not
loaded the hooks — and start Claude Code or Grok. A row appears as soon as it
does anything.

Click a row to jump to the terminal it belongs to. The menu-bar icon toggles the
panel and opens Settings, where you can pick a theme, and **Theme → Open Themes
Folder…** is where your own themes go.

### If no rows appear

- Was the terminal opened *after* running the installer? Hooks load at start.
- `ls ~/.groundcontrol/sessions/` — files here mean the hooks are firing and the
  problem is the app; an empty folder means the CLI is not calling them.
- Hooks are never allowed to interrupt your agent, so `cc-notify` fails
  silently by design. `docs/LIMITATIONS.md` covers what that hides.

## Uninstall

Delete the app, remove `~/bin/cc-notify`, and take the `cc-notify` entries out
of `~/.claude/settings.json` (a dated backup sits beside it). Session files live
in `~/.groundcontrol/`, themes in
`~/Library/Application Support/GroundControl/Themes/`.

## License

GPL-3.0-or-later — see `LICENSE`.
