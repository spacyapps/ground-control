# SkinTerminal — Build Specification

A macOS menu-bar app that monitors multiple Claude Code sessions and shows,
at a glance, which ones need your attention — with a WinAmp-style skinnable
UI (themes as image/video bundles). Free-floating panel, always-available
menu-bar icon.

This document is the single source of truth for the build. Read
`docs/STRUCTURE.md` for the code layout, `docs/THEMING.md` for the theme
format, and `docs/HOOK-PAYLOADS.md` for the measured hook data this spec
depends on.

> **Revision note.** §2–§4 and §8–§10 were rewritten after probing live hook
> payloads on Claude Code 2.1.226. The original spec keyed sessions on tty and
> assumed a `message` field; neither survived contact. Every field named below
> is observed, not assumed.

---

## 1. Tech

- **Language:** Swift
- **UI framework:** AppKit (not SwiftUI) — needed for `NSStatusItem`,
  non-activating floating `NSPanel`, window levels, AppleScript automation,
  and the custom skin engine. SwiftUI is acceptable only for the Settings
  window if convenient.
- **App type:** `LSUIElement` agent app — no Dock icon, lives in the menu bar.
  Set `NSApp.setActivationPolicy(.accessory)` and `LSUIElement=true` in
  Info.plist.
- **No embedded terminals.** The app is a pure monitor + launcher. It watches
  external session files and jumps to real Terminal/iTerm tabs. (SwiftTerm was
  considered and dropped.)
- **Distribution:** open-source (MIT) on GitHub; unsigned `.dmg` via
  `create-dmg` for non-devs (first launch needs right-click → Open). No App
  Store (sandbox would fight AppleScript + process launch). No notarization in
  v1.

---

## 2. Monitoring model (the core)

**One invariant governs everything: file ⇔ row.**

- Each session = one `.jsonl` file in the sessions folder.
- File exists ⇒ a row exists. No file ⇒ no row.
- The app **watches the folder** and mirrors it: file added → row added; file
  changed → row updated; file removed → row removed. The app never decides to
  remove a row on its own — it only reflects the folder.
- **Latest state = the last line of the file.** The row reads the last JSON
  line for its name, message, and state.

**Sessions folder:** `${TMPDIR}/skinterminal/` (ephemeral by design — we only
care about latest activity). Fall back to `/tmp/skinterminal/` if `TMPDIR` is
unset.

**Layout:**

```
${TMPDIR}/skinterminal/
├── <session_id>.jsonl                     one per session   -> one top-level row
└── agents/
    └── <session_id>__<agent_id>.jsonl     one per subagent  -> one child row
```

**File key = `session_id`**, taken straight from the hook payload. It is
unique per session and stable for the session's whole life.

> **Why not tty** (the original design): a hook runs with stdin bound to the
> payload pipe, so `tty` reports `not a tty` and every session collapses into
> one `unknown.jsonl` file. tty is also absent from the payload. It is still
> needed for jump-to-tab, but it is now a *property of* a session, not its
> identity — see §7. Full evidence in `docs/HOOK-PAYLOADS.md`.

**Purge (the only removal rule):**
- Delete any session file not modified in > **24h** (mtime-based). Same rule
  applies to `agents/`.
- App runs the purge on launch and on a timer (hourly is fine).
- OS temp-purge is a free backstop.
- Deleting a file flows through the same "file gone → row gone" path.
- A re-interacted session simply recreates its file and the row reappears.
- There is **no** "session ended" event, no grace period, no manual dismiss in
  v1. mtime is the entire lifecycle.

---

## 3. Event contract (hook → script → file)

Claude Code hooks run a shell command on events. They all point at one script,
`Scripts/cc-notify`, which appends a JSON line to the session's file.

**No argument is needed** — the payload carries `hook_event_name`, so every
event registers the identical command:

```json
{ "type": "command", "command": "~/bin/cc-notify" }
```

**Hooks used** (`~/.claude/settings.json`, merged by `install-hooks.sh` so
existing hooks on the same events survive):

| Event | Row becomes | Message source |
|---|---|---|
| `UserPromptSubmit` | working, dot **off** | `prompt` |
| `PreToolUse` | working, dot off | `tool_input.description` / `.file_path`, else `tool_name` |
| `Notification` | needsInput, dot **on** | `message` |
| `Stop` | done, dot **off** | `last_assistant_message` |
| `SubagentStop` | (child row) | `last_assistant_message` |

**Line format** — last line wins:

```json
{"schema":1,
 "session_id":"0ff3699a-597f-44c2-8a5f-3665332bc659",
 "name":"avaterm",
 "cwd":"/Users/waltermak/github/avaterm",
 "tty":"/dev/ttys008",
 "event":"Notification",
 "state":"needsInput",
 "message":"Claude is waiting for your input",
 "needs_action":true,
 "notification_type":"idle_prompt",
 "transcript_path":"/Users/waltermak/.claude/projects/…/<session_id>.jsonl",
 "ts":1786345349}
```

**Naming.** `name` prefers `session_title` (the name you gave the session in
Claude) and falls back to `basename(cwd)`. Measured across five live sessions,
two differed — and the title was the better label both times (`spacyapps` over
`fluffy-carnival`, `secretstuff` over `iOS8_miVault`). `session_title` ships
**only** on `UserPromptSubmit`, so `cc-notify` latches it from the previous
line of the file.

**No transcript parsing required.** `Stop` carries the full assistant message
and `Notification` carries real text, so rows show what Claude actually said
without reading `transcript_path`. The path is recorded in each line anyway —
it is the hook for a future "show more" without changing the contract.

**The dot.** `needs_action` drives it: on at `Notification`, off at every other
event, and cleared locally when the user clicks the row. `notification_type`
is carried through so the UI *may* distinguish "waiting for you"
(`idle_prompt`) from a permission request — see §10.

---

## 4. Subagents / groups

Subagents share the orchestrator's process, tty **and `session_id`**, so they
cannot be separated by session key alone. But `SubagentStop` carries
**`agent_id`** — a stable per-subagent identifier — which is exactly the
unlock the original spec said Option B required.

`cc-notify` therefore writes each subagent to its own file under `agents/`,
named `<session_id>__<agent_id>.jsonl`. The file ⇔ row invariant holds one
level down: the app groups children by the `session_id` prefix.

**Ship Option A; the data for B is already on disk.**

- **Option A (v1):** one row per orchestrator, `children` empty, with an
  aggregate line ("2 subagents finished") derived from the `agents/` files.
- **Option B (upgrade):** render those files as nested child rows.

The renderer always draws "parent + children[]", so A is literally B with an
empty array — flipping it on is data, not a rewrite. A collapsed group inherits
the red dot if any child needs action.

**Why B is not on by default.** Two measured problems:

1. **Only a stop event exists.** There is no `SubagentStart` carrying an
   `agent_id`, so a child row can only appear once the subagent has *finished*
   — useless for a live monitor. A live count can be approximated by counting
   `PreToolUse` events with `tool_name` of `Task`/`Agent` and subtracting
   `SubagentStop`s, but the two cannot be correlated by id.
2. ~~**Internal agents fire it too.**~~ **Filtered.** Claude Code emits
   `SubagentStop` for its own background agents, not only ones you spawned, and
   their text is not part of the visible conversation — observed live as child
   rows reading like the user's own suggested prompts. Every internal agent
   seen so far reports `agent_type: ""`, so `AgentGrouper` hides children with
   an empty type.

   It is a heuristic, not a guarantee: a genuine subagent reporting no type is
   hidden too. The files stay on disk regardless, and
   `defaults write SkinTerminal showsInternalAgents -bool YES` restores them
   without a rebuild.

Resolve the first before enabling B (§10).

---

## 5. UI

**Menu-bar icon** (`NSStatusItem`): always present; badges/changes when any
session needs action. Opens the panel.

**Free-floating panel** (`NSPanel`):
- `.nonactivatingPanel` + `isFloatingPanel = true` so clicking it never steals
  focus from the terminal.
- Toggleable **Always on top** (`level = .floating` vs `.normal`) and
  **Show on all Spaces** (`collectionBehavior` includes `.canJoinAllSpaces`
  vs `.moveToActiveSpace`; always include `.fullScreenAuxiliary`).
- **Remember panel position** across launches (save frame to UserDefaults).

**Rows** (vertical stack; WinAmp-style):
- Each row: status dot + **name** + **latest message** + avatar.
- `rowMaxHeight` ~100px (themeable).
- Long messages **marquee auto-scroll only when they overflow** (static
  otherwise).
- Group rows: `▼` expanded / `▶` collapsed / no triangle for plain sessions.

**Row interaction:**
| Target | Action |
|---|---|
| Row body | Jump to that terminal tab (tty + AppleScript); clears red dot |
| Row body, no tty | Jump disabled; fall back to revealing `cwd` in Finder |
| Expand triangle (groups only) | Toggle children |
| Child sub-row | Jump to orchestrator's terminal (same tty) |
| Right-click (optional v1) | Menu: jump / copy path / rename / dismiss |
| Collapsed group w/ needy child | Parent shows red dot |

**Ordering:** needs-action pinned top, then most-recently-active (`ts`
descending). Define a 0-session empty state.

---

## 6. Theming (v1 = global only)

- One active **global theme**, chosen in Settings, applied to every row.
- Themes live in `Themes/<name>/` with a `theme.json` manifest. See
  `docs/THEMING.md` for every key.
- **Everything optional:** each color/image/video has a code default
  (`DefaultTheme`). A theme overrides only what it sets; an empty `{}` is valid.
- **Avatar per state** (idle/working/needsInput/done), each an **image OR
  video** (author's choice of key). Supported: `.mov`/`.mp4` (H.264/HEVC),
  animated `.gif`/`.apng`. Not `.webm`.
- **Colors** block = the palette (`needsAction` is the red-dot color, etc.).
- **Hot reload:** watch the active theme folder; re-apply on change.
- **Per-project theming is explicitly OUT for v1** (deferred). If revisited,
  it slots in as higher-priority lookup steps ahead of the global theme, so
  v1's "always global" is just the bottom of a future chain — no rewrite.

**Video-in-panel caveat:** looping video in an always-on panel costs GPU.
Consider capping to GIF/APNG in v1 or make it a setting; decide at build time.

---

## 7. Integration

- **`TerminalFocuser`** — jump-to-tab via AppleScript (`NSAppleScript` or
  `osascript`), matching on the `tty` field of the session's latest line.
  Strong support for **iTerm2**; weaker for **Terminal.app**. First automation
  triggers a one-time macOS Automation permission prompt.
  - The tty is resolved **by the script, not the app**: `cc-notify` walks up
    its own process tree until it finds a process with a controlling terminal
    (the `claude` process holds it). The app just reads the field.
  - `tty` may be `null` — a session started outside a terminal, or a walk that
    failed. Treat jump-to-tab as **best-effort**: a null tty degrades one row's
    click action, never the row itself.
- **`HookInstaller`** (optional) — first-run helper that runs the equivalent of
  `Scripts/install-hooks.sh`: installs `cc-notify` and **merges** the hook
  entries into `~/.claude/settings.json`, with backup + user consent. Merging
  is mandatory — users have existing hooks on these same events, and Claude
  Code runs all of them. Never overwrite the `hooks` block.

---

## 8. Persisted state (outside temp files)

Kept in UserDefaults / Application Support, NOT in the session files (which
hooks append to constantly):
- Panel frame (position/size)
- Float toggles (on-top, all-Spaces)
- Selected theme name
- Renames: `{ session_id → nickname }`

**Renames are an override, not the primary naming path.** The name resolution
order is: **user rename → `session_title` → `basename(cwd)`**. Since
`session_title` is already the name you set inside Claude, most sessions never
need a rename at all.

---

## 9. Suggested build order

1. **Info.plist + app bundle** with `LSUIElement=true`; app launches as an
   accessory (menu-bar only).
2. **Models** (`Session`, `SessionEvent`, `SessionState`, `Theme`) — decode the
   §3 line format. Fixture files for this already exist: install the hooks and
   use your own real sessions.
3. **Monitoring** — the file⇔row engine + purge, driven by the folder. This is
   testable with hand-written `.jsonl` files and zero hook dependency.
4. **UI**: panel + rows rendering from the store; float toggles; marquee;
   status dot; avatar (start with drawn default).
5. **Theming**: loader + hot reload + `DefaultTheme` fallbacks; wire avatar
   states to images/video.
6. **Jump-to-tab** (`TerminalFocuser`), Terminal.app first if that is your
   daily driver, iTerm second.
7. **Settings window**; **rename**; optional right-click menu; optional
   `HookInstaller`.
8. **Packaging**: `build-dmg.sh`, README with install note + theming guide.

> The original order put hook verification at step 6. That work is **done** —
> `cc-notify` is written against measured payloads and verified by replaying
> real captures. Install the hooks first and the rest of the build has live
> data from step 2 onward.

---

## 10. Verification flags (don't guess — confirm)

**Resolved:**

1. ~~Hook payload field names~~ — measured; see `docs/HOOK-PAYLOADS.md`.
2. ~~Per-subagent identifier exists?~~ — **yes**, `agent_id` on `SubagentStop`.
   Option B is possible; §4 explains why it is not yet on by default.
3. ~~Terminal.app tab focus reliability~~ — **confirmed working**. Clicking a
   row jumps to the right Terminal.app tab, matched on tty. Verified by hand on
   macOS 26 with the tty resolved by `cc-notify`'s process-tree walk, which
   also confirms that walk end to end. iTerm2's path is written but untested.

**Open:**

3. **Permission-request `Notification`.** Only `notification_type:
   "idle_prompt"` has been observed, captured under `permission_mode: auto`
   where permission prompts do not fire. Confirm the type string for a real
   permission request, then decide whether it styles differently from idle.
4. ~~Distinguishing real subagents from internal ones~~ — **handled
   heuristically.** Empty `agent_type` is treated as internal and hidden (§4).
   Still worth revisiting if a payload ever exposes something definitive; the
   raw files are kept so the rule can be re-evaluated against real data.
5. **Live subagent tracking.** No start-side event carries an `agent_id`, so
   children only appear on completion. Decide whether an approximate live count
   is worth it, or whether B waits for a start event.
6. **Video avatar cost** in an always-on panel — measure; cap to GIF/APNG if
   needed. §6.
7. **iTerm2 tab focus** — the script is written but has never run against
   iTerm2. §7.
