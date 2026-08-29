# Group Grok Bot — architecture

**Status: built 2026-08-28** (branch `grok-bot-grouping`). Verified against the
real cache. Signal facts live in
[`GROK-BOT-INTEGRATION.md`](GROK-BOT-INTEGRATION.md); read that first.

**What shipped:** `Base32`, `GrokBotRoster` (parse + schema tolerance),
`GrokBotWatcher` (folder watch + the pure `roster → [Session]` map),
`SessionAggregator` (merges it beside `SessionStore`), `StatusDotView.Mark
.unknown` (the split dot), `AgentRow` direct init, `SessionEvent` synth init,
`Preferences.showsGrokBot`. 24 tests. No `SessionState` change.

---

## What it does — today

- One collapsible **Grok Bot** parent row. Expand → one child row per bot.
- Each bot is either **needs you** (red dot, alert) or **unknown** (a neutral
  mood — present, watching, no claim about done/idle).
- The collapsed parent inherits the red dot from any needy child. Same rule the
  subagent groups already use.
- Clicking the parent or a bot raises `Grok Bot.app` (`com.anysphere.sand`).
- Grok Bot not installed → no row, no cost.
- The cache format moves (it's undocumented, schema already v3) → the row
  degrades to "can't read status", visibly. Never crashes, never goes silent.

## What it does *not* do — deliberately

- No "working" / "done" / "idle" for a bot. `GROK-BOT-INTEGRATION.md` proves
  "done" is unknowable — a cloud turn can go silent for minutes mid-work. A
  heartbeat ("active in the last ~15s") *could* be added later; it earns little
  while "quiet" stays ambiguous.
- No channels (`isGroup: true` bots) in v1 — flatten members or skip.
- No per-bot avatar colour, no automations layer, no cloud RPC.

---

## The real constraint

GC exists to answer one question per row: *is it done, or does it need me?* For
Grok Bot, **"done" is unknowable** and **"needs me" rests on a single
undocumented field** (`lastEntry.sessionPreview.kind == "widget_options"`,
schema v3). So the design is shaped by three rules, in order:

1. **Be loud and correct about "needs you"** — the one thing we can read.
2. **Never render a mood we didn't measure.** No "idle", no "done" for a bot we
   can't parse. That is what `.unknown` is for.
3. **Fail visible, not silent.** A roster file that is present but the wrong
   shape must produce a row that says so — per `LIMITATIONS.md` →
   "Silence is the failure mode here".

Secondary: this is a **poll-a-JSON-file** integration, not an event stream.
Writes burst ~every 2 s during activity → debounce. The file is **per account**
→ there can be more than one.

---

## What it fits into

| Piece | Role | Reused as-is? |
|---|---|---|
| `Session` (`Models/Session.swift`) | parent row: `children: [AgentRow]`, `isGroup`, `needsAction` bubbles up from children, age-decayed `state` | **yes** — designed for "parent + children" (SPEC §4) |
| `AgentRow` (same file) | one child row | **almost** — needs a direct init (see friction) |
| `GroupRowView` / `SessionRowView` | renderers, "thin views, same list code" | **yes** |
| `SessionState` (`Models/SessionState.swift`) | 4 cases; exhaustive `switch` in `urgency`, `Theme.colors.color(for:)`, matrix mapping | **no** — gains `.unknown` |
| `AgentGrouper` (`Monitoring/`) | the **hook-subagent** producer: lists `agents/*.jsonl`, parses `AgentEvent`, keys by `sessionID`, Claude-specific `isInternal` | **untouched** — a sibling producer is added, not a branch here |
| `SessionStore` (`Monitoring/`) | source of truth for the panel; rebuilds `[Session]` from `sessionsRoot/*.jsonl` on every FolderWatcher tick + a 2 s poll backstop. **Invariant: file ⇔ row** (SPEC §2) — it never invents or drops a row, and `remove()` leans on that | **not touched** — see the merge note below |
| FolderWatcher (used by `ThemeStore` and `SessionStore`, debounced) | file-watch primitive | **yes** |
| `.application` jump destination + `host_id` resolution | "raise the app" for a tty-less row (the Cursor Composer path) | **yes** |
| `Preferences` (`showsInternalAgents`, `analyserTint`) | pattern for a no-rebuild toggle | pattern reused for `showsGrokBot` if wanted |

**The generic seam is the `Session` model, not `AgentGrouper`.** `AgentGrouper`
is generic in its *output* (`[String: [AgentRow]]`) but welded to the hook world
on input. Grok Bot converges on `Session`, one layer up.

---

## Design A — synthetic Session + children  *(recommended)*

```
 sessions/*.jsonl            sand-client-persistence/*.roster.last-roster
      │ (FolderWatcher)              │ (FolderWatcher, debounced)
      ▼                              ▼
 SessionStore                   GrokBotWatcher ──► GrokBotRoster
  → [Session] (hooks)            → [Session] (one synthetic parent,
      │                             children = [AgentRow] one per bot)
      └──────────────┬───────────────┘
                     ▼  merge layer: concat + SessionStore.sorted(_:)
              the panel's session list
                     ▼
           existing SessionRowView / GroupRowView
```

### The merge point

`SessionStore.reload()` builds `[Session]` from `sessionsRoot` and holds the
**file ⇔ row** invariant. A Grok Bot row has no file there, so **it does not go
into `SessionStore`** — that invariant is load-bearing (`remove()`, SPEC §2).

Instead, a thin **merge layer** owns both sources: it takes `SessionStore`'s
`onChange` output and `GrokBotWatcher`'s, concatenates, runs the existing
`SessionStore.sorted(_:)` (static, reusable), and hands the combined list to the
panel. Each producer stays honest to its own model; neither knows about the
other. This is where a future third source plugs in too.

Concretely: `AppCoordinator` today holds `store` and reads `store.sessions` /
`store.onChange` in ~8 places. Introduce a **`SessionAggregator`** that holds
`SessionStore` + `GrokBotWatcher`, exposes the same `.sessions` / `.onChange`
shape, and `AppCoordinator` swaps `store` → `aggregator` with almost no other
change. The aggregator is the named boundary; the producers are swappable behind
it.

- **`GrokBotWatcher`** (`Monitoring/`) — owns discovery, watching, debounce.
  Globs `*.blob`, base32-decodes names, keeps every `*.roster.last-roster`.
- **`GrokBotRoster`** — Codable model mirroring the blob. **All schema tolerance
  lives here**: known `schemaVersion` → parse; unknown/absent field it needs →
  a `.degraded(reason:)` result rather than a throw.
- **`GrokBotRoster → [Session]`** — a pure function. Synthetic parent:
  `id = "grokbot"` (real ids are UUIDs/hashes — no collision), `hostApp` = the
  Grok Bot bundle path, `name = "Grok Bot"`, `state` = `.unknown` unless a child
  needs you (then the dot bubbles up for free). **`lastActivity` = the max
  `updatedAt` across its bots** (not "now") so the group sorts by real recency,
  not always near the top. Children: one `AgentRow` per non-hidden bot,
  `state` = `.needsInput` if `sessionPreview.kind == "widget_options"` **or**
  `awaitingUserResponse != null` **or** a pending `local-tool-permission`, else
  `.unknown`. Roster present but zero bots → no parent row.
- **"Unknown" is a `StatusDotView.Mark`, not a `SessionState`.** Reread caught
  this: `SessionState` is `CaseIterable`, `Codable`, the wire enum `cc-notify`
  writes, and it drives the matrix, avatars, theme assets and `urgency` — a
  fifth case there widens a data contract for a rendering-only idea. The
  codebase **already** models confidence-in-the-state as a `Mark`
  (`.square` = "can't be trusted to report blocked"). "Unknown" is the same
  category and sits next to it: `Mark.unknown`, drawn as **half `idle` / half
  `done`** (no `working` — the ambiguity is only ever "resting or finished").
  A Grok bot's real `SessionState` stays honest: `.needsInput` when a card is
  pending, `.idle` otherwise — so the matrix stays inert and sorting uses
  `idle`'s urgency 0, both correct, with **zero** changes to `SessionState` or
  its switches. `Mark.forSource("grokbot") → .unknown`; a needy bot
  (`isProminent`) overrides to the solid round dot — we *do* know then.
- **`AgentRow` direct init** `(id, name, state, message, needsAction)` — ~10
  lines, since Grok bots have no `AgentEvent`. Also makes `AgentRow` reusable
  for the next non-hook source.

### Why A

It is the simple, boring baseline, and it reuses a model built for exactly this.
It defers the "N hosts" abstraction until there is a real third case to shape it
with, instead of one and a guess.

## Design B — a `PanelRow` protocol, `Session` and `GrokBotGroup` both conform

More correct for a future with many hosts. Rejected for now: it refactors the
whole render path and touches every view, to serve exactly one second case.
The skill's rule — don't build the abstraction for a caller you can't name.
A→B later is one render-path refactor, done with two real examples in hand.

**Revisit B when** a third grouped source lands (Grok CLI channels, multi-session
repos, opencode sub-sessions).

---

## Failure modes — part of the shape

| Case | Behaviour |
|---|---|
| Grok Bot not installed | no `sand-client-persistence/` → watcher silent → no row |
| roster schema moves / field renamed | parser returns `.degraded` → parent row, `state .unknown`, message *"Grok Bot: can't read status — update Ground Control?"*, logged once |
| roster present, JSON invalid | same `.degraded` path |
| multiple accounts | v1: merge all bots under one parent. Revisit if anyone actually has two |
| bot hidden (`isHiddenFromSidebar`) or a channel | dropped from children in v1 |
| Grok Bot quit, cache stale | `sand-session-marker.json` liveness → optional; worst case all bots read `.unknown`, which is honest |
| write burst (~2 s) | FolderWatcher debounce, 0.25–0.5 s |
| card answered inside Grok Bot | next roster write clears it, poll picks it up |

---

## Irreversible / careful

- **`SessionState` is untouched** (see the Mark decision above) — no wire-enum
  widening, no persistence question.
- **Synthetic `Session` through the existing logic.** `Session.state` age-decays
  to `.idle` off `latest.timestamp` for anything that isn't `.needsInput`. Since
  a quiet Grok bot's state genuinely *is* `.idle`, that decay is idempotent —
  nothing to exempt. The fabricated `SessionEvent` needs an explicit `name` so
  the parent isn't named after a path, and `timestamp` = max bot `updatedAt`
  (drives the sort).
- **Fixed id `"grokbot"`** — document the reserved id.

---

## Decisions

1. **Alert treatment — decided.** A bot that needs input gets its own red dot
   *and* triggers the full GC alarm, same as any needy session. The parent
   inherits the dot (via `needsAction` bubbling). A second bot going needy is a
   fresh escalation edge, like a second needy session today.
2. **`.unknown` dot — decided.** Half `idle` / half `done`, no `working` (the
   ambiguity is never "working"). Two wedges, or a flat 50/50 blend at the 6px
   child size if the split looks muddy. No new palette entry.
3. **`.unknown` urgency rank — default 0** (same as `idle`), matching the
   half-idle blend. Tweakable.

4. **Collapsed parent row — decided.** Dot (red if any bot needs you, else the
   blended `.unknown` shade) + "Grok Bot" + the message slot carries a count:
   `"3 bots · 1 waiting"`, or `"3 bots"` when none are needy. No fabricated
   last-line message. The panel's title-bar analyser is not per-row — it already
   aggregates every session's state, so a needy Grok bot drives the alarm
   through the existing path with nothing extra to wire.

---

## Rough build order

1. `StatusDotView.Mark.unknown` — half `idle` / half `done` wedge; solid round
   when `isProminent`. `Mark.forSource("grokbot") → .unknown`. `GroupRowView`
   sets `dot.mark` from the child. **No `SessionState` change.**
2. `AgentRow` direct init.
3. `GrokBotRoster` Codable model + schema-tolerance, from the captured fixtures.
4. `GrokBotRoster → [Session]` pure map. Tests: solo/idle, pending card,
   multi-bot, wrong-schema-degrades (prove it fails without the guard).
5. `GrokBotWatcher` (FolderWatcher + debounce + multi-file).
6. The merge layer: combine `SessionStore` + `GrokBotWatcher` outputs, re-sort
   with `SessionStore.sorted(_:)`, feed the panel. `SessionStore` untouched.
7. `Preferences.showsGrokBot` if a toggle is wanted.

Diagram: later.
