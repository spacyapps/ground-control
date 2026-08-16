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

**Cursor's own agent has limited support.** Composer chats appear as rows, named
after the question they started from, and clicking one raises Cursor — the
installer registers `~/.cursor/hooks.json` when Cursor is present. The alarm
cannot work there: Cursor fires no hook while its agent waits for approval, so a
blocked chat looks like a busy one. Measured, and confirmed against Cursor's own
docs and an open feature request — see `docs/LIMITATIONS.md`. Claude Code running
in Cursor's *terminal* is fully supported, alarm included.

See `docs/SPEC.md` §3 for the event contract, `docs/HOOK-PAYLOADS.md` for the
measured payloads it is built on, `docs/ARCHITECTURE.md` for how a hook event
becomes a row, and `docs/LIMITATIONS.md` for what is proven
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

Or click the menu-bar icon and choose **Set Up Hooks…**, which runs the same
thing without a terminal.

It installs `cc-notify` to `~/Library/Application Support/GroundControl/bin/`
and registers it in `~/.claude/settings.json`, backing up the file first. **You only run it once** —
later versions of the app update the installed emitter themselves on launch, so
the two halves cannot drift apart. It never installs one where you have not, and
never touches your settings. It merges rather than
overwrites, so hooks you already have are kept, and it is safe to re-run.
Claude Code and Grok both read that file and both are covered.

If Cursor is installed it also registers `~/.cursor/hooks.json`, which is what
its own agent reads — merging there too, and backing up anything already in it.
**Restart Cursor** afterwards: it reads that file at startup. Nothing else needs
restarting.

**3. Start a session.** Open a *new* terminal — a CLI already running has not
loaded the hooks — and start Claude Code or Grok. A row appears as soon as it
does anything.

Click a row to jump to the terminal it belongs to. The menu-bar icon toggles the
panel and opens Settings, where you can pick a theme, and **Theme → Open Themes
Folder…** is where your own themes go.

Clicking a row goes to the exact tab in iTerm2 and Terminal, and raises the
owning application for anything else — VS Code and its forks, Warp, Ghostty,
WezTerm. If a click opens Finder instead, the hooks predate that support: re-run
the installer above.

Rows come from agent CLIs that fire hooks, so **Claude Code running in VS Code's
integrated terminal appears**, while VS Code's own Copilot chat does not — it
never calls the emitter. See `docs/LIMITATIONS.md`.

### If no rows appear

- Was the terminal opened *after* running the installer? Hooks load at start.
- **Check the registration.** Claude Code shows its own hooks in a panel —
  *Agent Customizations → Hooks* — which is quicker than reading JSON, and lists
  `cc-notify` against each event it fires on. Hooks you already had are listed
  beside it, since the installer merges rather than replaces. (That panel does
  not render `Notification` hooks, so seeing seven entries rather than eight is
  normal; `~/.claude/settings.json` is the source of truth.) These are Claude
  Code's settings and have no bearing on VS Code's own Copilot chat.
- `ls ~/.groundcontrol/sessions/` — files here mean the hooks are firing and the
  problem is the app; an empty folder means the CLI is not calling them.
- Hooks are never allowed to interrupt your agent, so `cc-notify` fails
  silently by design. `docs/LIMITATIONS.md` covers what that hides.

## Uninstall

Click the menu-bar icon and choose **Remove Hooks…** — or run
`~/Library/Application\ Support/GroundControl/bin/uninstall-hooks.sh`, which is
kept there so it still works after the app is gone. It takes the `cc-notify` entries out
of `~/.claude/settings.json` (a dated backup sits beside it). Session files live
in `~/.groundcontrol/`, themes in
`~/Library/Application Support/GroundControl/Themes/`.

## License

GPL-3.0-or-later — see `LICENSE`.
