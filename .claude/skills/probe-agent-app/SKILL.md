---
name: probe-agent-app
description: >-
  Use when working out whether a new agent CLI or desktop app can feed Ground
  Control — does it fire local hooks, and if not, what does it write locally
  that a watcher could read. Covers the method, the traps that already cost
  time, and how to re-run the Grok Bot investigation quickly.
---

# Probing an agent app for a Ground Control signal

The question is always the same: **can GC tell, from this machine, when one of
this app's sessions is working / done / waiting on you?** Two ways it can:
lifecycle **hooks** it runs, or **state files** it writes that a watcher reads.
Work through both, in order, and write down what you find.

The verified conclusions for each app already examined live in
`docs/LIMITATIONS.md`; the full Grok Bot record is `docs/GROK-BOT-INTEGRATION.md`.
Read those before re-deriving anything.

## 1. Hooks first — cheapest if it works

The pattern is `Scripts/probe-cursor-hooks.sh`: register an **observe-only**
hook for *every* lifecycle event the app might have, into whatever config file
it reads, then run turns and read the log. The probe prints nothing on stdout,
so it returns no decision and cannot block or slow the agent; it exits 0 always.

To adapt it to a new app, change two things and nothing else
(`agent-cli-hook-landscape` memory: hook payloads vary on exactly those two
axes):

- **the event names** — the `EVENTS=(…)` list
- **the config path** — Claude/Grok read `~/.claude/settings.json`; Cursor and
  its forks read `~/.cursor/hooks.json`; Codex `~/.codex/hooks.json`; Gemini
  `~/.gemini/settings.json`

Then: restart the app (these read the config at launch, not per turn), run the
turns from §3, and `--show`. **An empty log after a real tool-using turn means
the app does not run local hooks** — Grok Bot carries Cursor's whole hooks
engine in its bundle and still never reads a local `hooks.json`, because its
agent runs in the cloud.

Always `--uninstall` when done.

## 2. State files — the fallback

Find the app's data dirs (`~/.<app>`, `~/Library/Application Support/<App>`).
Snapshot them, then watch for writes:

- Many of these caches are **plaintext JSON** even when the filenames are
  opaque. Grok Bot's are base32 of a slice key
  (`base64.b32decode(name.upper() + padding)`).
- Watch with a poll loop on `stat -f %m`, not `fswatch` (may be absent).
  **bash 3.2 has no associative arrays** — track seen mtimes in a temp file.
- **Filter aggressively.** A "composer draft" / input-box slice rewrites on
  every keystroke and will drown the signal and get a Monitor auto-killed.
- Snapshot the interesting file *while a prompt sits unanswered* — that is the
  only way to learn which field, if any, means "blocked" (for Grok Bot,
  `awaitingUserResponse` looked like it and was a red herring; the real tell
  was `lastEntry.sessionPreview.kind == "widget_options"`).

## 3. Run turns of increasing weight

Each reveals a different thing. Do them in order:

| Turn | What it tells you |
|---|---|
| plain chat, no tools | does *anything* fire / get written per turn |
| reads a file **and** runs a shell command | do tool events fire; does local exec engage |
| one that makes the agent ask your permission | which event / field carries "waiting on you" |
| a real research task, 30 s+ | does state update mid-turn (a "working" heartbeat) or only at the end — and does the agent **defer** and go silent (Grok Bot went quiet for 3m49s mid-task; "quiet" is then indistinguishable from "done") |

## 4. Verify against the real thing before trusting a shape

`verify-cli-payloads-before-coding` memory — two integrations were written from
docs and silently did nothing. Point a throwaway test at the live cache/log and
print what the parser actually produces. Only then write the adapter.

When the app's own model explains its internals (Grok Bot did, asked directly),
it is informed but **not authoritative** — treat it as a lead to confirm, not a
fact.

## 5. Traps that already bit

- `withSymbolConfiguration(paletteColors:)` is the reliable way to tint an SF
  Symbol drawn by hand; `.draw()` on a template image does not pick up the fill
  colour.
- Pixel-sampling a rendered `NSView` in a test: the rep is **2× on Retina**, so
  `colorAt(x:)` takes device pixels — compute sample points from
  `rep.pixelsWide`, not the view's point size.
- `AvatarView` always paints a background plate, so an alpha-threshold pixel
  count measures the plate, not the face — compare colours or composited images
  instead.

## Re-monitoring Grok Bot

- `./Scripts/watch-grokbot-cache.sh` — follow roster + transcript writes live;
  `--dump` prints the current roster once.
- `Scripts/probe-cursor-hooks.sh` still works for a fresh hooks check if a Grok
  Bot update ever wires the engine up.
- The integration itself: `Sources/GroundControl/Monitoring/GrokBot*.swift`,
  design in `docs/GROK-BOT-GROUPING.md`.
