# Group Grok CLI subagents — architecture

**Status: built 2026-09-10** (branch `grok-subagent-grouping`). Verified live
against real subagents, in the app, on screen. Signal facts live in
`docs/HOOK-PAYLOADS.md` ("Follow-up, same evening") and
`docs/LIMITATIONS.md`; read those first for the raw investigation.

---

## What it does — today

- A Grok CLI session's `spawn_subagent` children appear nested under their
  parent row, with a disclosure arrow — the same "N subagents" treatment
  Claude Code's real subagents already get.
- Each child shows its own live state and message while it is still running,
  and turns to "Finished" once done.
- A child whose own row has already self-deleted (Grok's version of
  `SessionEnd`) is still recoverable for up to 30 minutes, reconstructed from
  a small file Grok leaves behind — so a fast subagent that finishes between
  two panel refreshes is not lost.
- No Grok CLI running, or `spawn_subagent` never called → no group, no cost.
- Off switch: `Preferences.showsGrokSubagentGrouping` (on by default).

## What it does *not* do — deliberately

- No live tracking through a hook — there isn't one. This is read-only file
  discovery, the same shape as the Grok Bot integration, not a hook adapter.
- No nested subagents-of-subagents — Grok's own depth limit is exactly 1
  (`docs/user-guide/16-subagents.md`: "a subagent cannot spawn its own
  subagents"), so `AgentRow` never needs a recursive shape here.
- No recursive directory watch of `~/.grok/sessions/` — only sessions GC
  already knows are live get their `subagents/` folder checked. There is no
  unbounded tree to watch.

---

## The real constraint

Two things were believed true and turned out false, both corrected the same
evening:

1. **`SubagentStart`/`SubagentStop` do not fire for `spawn_subagent`.** They
   were the plan — Grok has them and Claude doesn't, and `cc-notify`'s
   `handle_subagent()` was written to receive them. A live test showed
   neither ever arrives. Each subagent is its own fully independent
   top-level Grok session instead: own `session_id`, own hook lifecycle, own
   flat row, self-deletes on completion like any session.
2. **The obvious next idea — a timing/cwd/tty heuristic correlating a
   `spawn_subagent` `PreToolUse` with the next session sharing the same
   terminal — was designed, reviewed, and then superseded before being
   built**, once a broader filesystem scan turned up something better: Grok
   already writes the exact link to disk itself.

`<parent_session_dir>/subagents/<child_session_id>/meta.json` — confirmed
against every subagent spawned across three separate test runs that evening,
all correct, including ones spawned *before* this file was ever noticed.
Fixed-size, ~1KB, not the parent's 500KB+ transcript. It carries:

```json
{
  "subagent_id": "01a08ece-eaa4-70f3-aba6-3ab33f7ad06b",
  "parent_session_id": "01a08ebd-881e-7193-8cc1-7f9e1dbc693c",
  "child_session_id": "01a08ece-eaa4-70f3-aba6-3ab33f7ad06b",
  "subagent_type": "explore",
  "description": "Count LOC by extension",
  "status": "completed",
  "started_at": "2026-09-11T05:33:30.178233Z",
  "completed_at": "2026-09-11T05:34:00.612107Z",
  "duration_ms": 30434
}
```

`status` is `"running"` from the moment of spawn (confirmed live, not just
inferred), then `"completed"`. A sibling `output.json` holds the subagent's
final result text — not read by GC today, but there if ever wanted.

This is still an **undocumented, no-contract Grok-internal file** — the same
fragility class as Grok Bot's roster cache. `GrokSubagentMeta`'s decode is
tolerant (a malformed or missing file is simply skipped, never crashes), the
same discipline `GrokBotRoster` already uses.

---

## What it fits into

| Piece | Role | Reused as-is? |
|---|---|---|
| `Session` / `AgentRow` (`Models/`) | parent + children shape | **yes** — same model Grok Bot's group and Claude's `AgentGrouper` both already target |
| `SessionAggregator` | merge layer | **extended, not replaced** — the fold happens in `recombine()`, on top of `SessionStore`'s own output |
| `SessionStore` | file⇔row invariant for hook-driven sessions | **untouched** — Grok subagent children are never written into it, never removed from it; the aggregator just declines to show a child's flat row once it knows the child is one |
| `GrokBotWatcher` / `GrokBotRoster` | nearest real precedent | pattern reused: read an undocumented Grok-owned file, tolerant of drift, builds `AgentRow` directly from a foreign source rather than wrapping an `AgentEvent` |
| `AgentGrouper` | Claude's own hook-based grouping | **untouched, a sibling** — nothing here shares code with it; Claude's subagents keep working exactly as before |
| `Preferences` (`showsGrokBot`, `showsInternalAgents`) | no-rebuild toggle pattern | reused for `showsGrokSubagentGrouping` |

**The generic seam is `SessionAggregator.recombine()`, not `SessionStore`.**
Same principle as the Grok Bot design: a foreign source converges on the
existing row model one layer above the file⇔row invariant, never inside it.

---

## Design

```
 sessions/*.jsonl                    ~/.grok/sessions/<cwd>/<parent>/subagents/*/meta.json
      │ (FolderWatcher, polled)              │ (read on every recombine(), no watcher —
      ▼                                       │  a handful of ~1KB files, cheap enough
 SessionStore                                 │  to just re-read)
  → [Session] (hook-driven, flat)             ▼
      │                              GrokSubagentReader.childrenBySession(...)
      │                               → [String: [AgentRow]], keyed by parent id
      └──────────────┬────────────────────────┘
                     ▼  SessionAggregator.recombine():
                        - drop any Session whose id is a known child
                        - attach matching children to their parent Session
                        - SessionStore.sorted(...)
                     ▼
              the panel's session list
```

- **`GrokSubagentMeta`** — decodes one `meta.json`. `state` maps `"completed"`
  → `.done`, anything else (including the confirmed `"running"`) → `.working`
  — the safe direction, since an unrecognised status just reads as busy a
  little longer rather than flipping a live subagent to looking finished.
- **`GrokSubagentReader.childrenBySession(liveSessions:now:sessionsRoot:)`** —
  pure, tested. For every live `source == "grok"` session, lists its own
  `subagents/` folder. For each child found:
  - **If the child's own row is still live** (found by id in the same
    `liveSessions` list), the `AgentRow` uses **that row's** `state`,
    `message`, `needsAction`, `lastActivity` — never `meta.json`'s, because
    `meta.json` carries no alarm signal at all, and Grok is the one CLI here
    that alarms independent of `permission_mode: auto`
    (`docs/LIMITATIONS.md`, "Grok asks two different ways"). Trusting
    `meta.json` alone while a child is still running would silently drop a
    real alarm.
  - **Otherwise** (the child's own row already self-deleted), the row is
    reconstructed entirely from `meta.json` — message `"Finished"` or
    `"Working…"`, `needsAction` always `false` (nothing to recover an alarm
    from once the row is gone).
  - Either way, the **label** always comes from `meta.json`'s `description`
    — a live row just reads the session's own name (`"lunararray"`, say),
    never the task. Only this file says what the subagent was actually for.
  - A recovered (no live row) child older than `showFinishedFor` (30
    minutes, matching `AgentGrouper`'s own constant for Claude's finished
    children) is dropped — `meta.json` has no purge of its own, so without a
    cutoff a parent would accumulate every subagent it ever spawned, for as
    long as the parent session itself stays live.
- **`SessionAggregator.recombine()`** — computes `childIDs` (every id that
  appeared as *someone's* child) and excludes those from the flat list
  outright, then attaches each parent's children. A child is never shown
  both flat and nested; there is no timing window where it could be, since
  the fold is fully re-derived from disk on every `recombine()`, not from
  any state carried between calls.

### Why this instead of the two options considered and dropped

1. **A transcript-tailer**, reading Grok's own `updates.jsonl` for a
   `subagent_spawned` event it also carries. Rejected once `meta.json` was
   found: same link, ~1KB instead of 500KB+, no need for real offset-tracked
   tailing, no new unbounded-directory-tree class to watch.
2. **A timing/cwd/tty heuristic**, correlating a `spawn_subagent`
   `PreToolUse` with the next session sharing the same terminal within a
   short window. Fully designed, reasoned through, deliberately **not
   built** — `meta.json` dominates it in every case: exact instead of
   best-effort, and it never has a silent-miss failure mode the way a missed
   correlation window does.

---

## Failure modes — part of the shape

| Case | Behaviour |
|---|---|
| No Grok CLI running | no `subagents/` folder ever checked → no cost |
| `spawn_subagent` never called | empty `subagents/` folder or none at all → no children |
| `meta.json` missing or malformed | that one child is skipped, never crashes; other children in the same folder are unaffected |
| Child's own row self-deletes mid-check | next `recombine()` simply falls back to the `meta.json`-only path — no error, no gap in the group |
| A recovered child ages past 30 minutes | quietly dropped, same as Claude's own finished subagents |
| The `meta.json` shape drifts in a future Grok release | fields decode as absent where possible; a genuinely broken file is skipped rather than shown wrong. No visible "can't read status" row yet, unlike Grok Bot's roster — worth adding if this file's shape ever actually moves |

---

## Irreversible / careful

- **`SessionStore`'s file⇔row invariant is untouched.** The fold happens
  entirely in the aggregator's merged copy; `SessionStore.remove()` and the
  24h purge behave exactly as before, on exactly the files they always saw.
- **No new watcher, no new poll timer.** `GrokSubagentReader` is a pure
  function, re-run on every existing `recombine()` tick (already driven by
  `SessionStore`'s and `GrokBotWatcher`'s own timers) — nothing new to start,
  stop, or leak.

---

## Verified live, 2026-09-10

- Two subagents spawned, staggered (~30s / ~1min): both appeared nested
  under their parent with a disclosure arrow, correct labels from
  `meta.json`, correct live state from their own rows.
- A third, older subagent (spawned in an earlier test, its own row already
  self-deleted) appeared in the *same* group as "Finished" — the recovery
  path, confirmed on real data, not just a test fixture.
- `meta.json`'s `status` field confirmed to read `"running"` from the moment
  of spawn, resolving what had been an open question.

## Rough build order (for the record)

1. `GrokSubagentMeta` — decode + `state`/`lastActivity`/`agentRow(overriding:)`.
2. `GrokSubagentReader.childrenBySession` — pure map, tested against fixture
   folders (11 tests: shape, live-vs-recovered, sort order, the history
   cutoff, percent-encoding, malformed input).
3. Wire into `SessionAggregator.recombine()` — fold, not a new producer.
4. `Preferences.showsGrokSubagentGrouping`.
5. Build, sign, launch, verify against a real running Grok session.
