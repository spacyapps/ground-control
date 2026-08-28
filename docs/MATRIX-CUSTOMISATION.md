# Matrix customisation

> **Status: design, nothing built.** Settled across a design session on
> 2026-08-27. This is the spec to build against, not a description of code that
> exists. The `matrix` block today is colours plus `messages` and nothing here
> is wired up yet.
>
> Kept as the plan, with the open questions closed at the bottom.

---

## Why

The analyser in the title bar is the most alive part of the panel, and the least
customisable. A theme can recolour it and give it a voice; it cannot change how
it *moves*. Every theme gets the same eight patterns, the same ballistics, the
same reaction curve. This is about letting a theme own the motion too — and,
further out, letting the machine's owner drive it from their own data.

## The constraint everything hangs off

**The analyser has two clocks.**

- A **24 fps render loop** — smoothing, fast-attack/slow-release, peak drift, the
  LED grid draw. This is what gives it the "real analyser" feel. It must stay
  native and in-process. Nothing external runs here; one hung script and the
  panel freezes.
- A **slow input signal** — "what are my sessions doing" — which changes on human
  timescales, a few times a second at most.

Customisation is cheap and safe on the slow clock, expensive and dangerous on
the fast one. That split drives the whole design.

**Second constraint: themes are pure data.** They are downloadable, some are
sold, and they go through notarisation. Executable code must never travel
*inside* a theme package — it is a malware vector and a signing problem. So there
are two audiences with two delivery mechanisms:

| Audience | Customises with | Travels in | Notes |
|---|---|---|---|
| Theme author | manifest keys, math formulas | the theme folder | declarative, sandboxed, sellable |
| Machine owner | scripts, native plugins | local config | executable, opt-in, never bundled — same as `cc-notify` hooks |

## The pipeline

Every frame, the meter is produced in four stages. Each tier plugs into a
different stage, which is why they stack rather than collide.

| Stage | Produces | Owned by |
|---|---|---|
| 1. Pick the shape | target height per bar, 0…1 | **Tier 2** formula · or the `patterns` list · or the 8 built-ins |
| 2. Scale by activity | amplitude | **Tier 1** `sensitivity` + working count |
| 3. Animate | eased levels + peak markers | **Tier 1** `fall`, `jitter` |
| 4. Colour and draw | pixels | Tier 0 colours, hot ramp on alarm |

Tier 1 is the instrument. Tier 2 is the note. A `needsInput` formula (stage 1)
still runs through the theme's `fall` and `jitter` (stage 3); `sensitivity`
still bends the working amplitude whatever shape produced it.

## The tiers

- **Tier 0 — today.** Six colours plus a `messages` array.
- **Tier 1 — manifest knobs.** Named levels for the instrument's feel, and a
  subset of which built-in patterns rotate. No code, travels in the theme.
- **Tier 2 — pattern formulas.** A small pure-math expression language, one
  formula per session state. New *shapes* without a plugin runtime, sandboxed by
  being pure math, stays in the theme so a paid theme can have a signature
  analyser. **This is the sweet spot** — most "I want my own equaliser" is this.
- **Tier 3 — script hooks.** The `cc-notify` pattern inverted: a user-configured
  script GC invokes on the *slow clock only*, handed session state as JSON on
  stdin, returning an energy target, a bar-height array, or a message line. The
  "py files" idea. Powerful (can read git, hit an API, run a real FFT), but
  never per-frame, always with a timeout and fail-open to the native model,
  strictly user-scoped config. **Build only on real demand**, and reuse the
  `cc-notify` architecture wholesale.
- **Tier 4 — native driver plugin.** A `VisualizerDriver` protocol in a
  dylib/Swift package. Full speed, in-process, unsandboxed, ABI-fragile, a
  build step. **Document the protocol so a fork is clean; do not build the
  loader.**

Staging: Tier 1 first (cheap, safe, covers most demand), Tier 2 next (best
ratio), Tier 3 only if someone actually wants external data, Tier 4 as
documentation.

## The combined manifest block (Tier 1 + 2)

Every key optional. An absent `matrix`, or today's colours-only block, behaves
**exactly** as it does now.

```jsonc
"matrix": {
  // Colours (Tier 0, unchanged)
  "low": "#39ff14", "high": "#39c5ff", "alarm": "#ff2d55",
  "unlit": "#26263219", "text": "#e6e6ec", "peak": "#e6e6ec",
  "messages": ["SYSTEM ONLINE", "NEURAL LINK", "STANDING BY"],

  // The instrument: global feel (Tier 1)
  "feel": {
    "fall":        "slow",     // still | slow | medium | fast  — release & peak ballistics
    "jitter":      "calm",     // none | calm | lively | chaotic
    "sensitivity": "steady",   // mellow | steady | twitchy     — working count -> amplitude
    "speed":       "medium"    // slow | medium | fast          — how fast phase advances
  },

  // Which built-in shapes rotate — used only where no formula overrides (Tier 1)
  "patterns":    ["wave", "ripple", "pyramid"],  // subset of the 8; omit = all 8
  "patternHold": "medium",                        // short | medium | long

  // Per-state shapes (Tier 2, all optional)
  "shape": {
    "working":    "0.5 + 0.5*sin(pos*7 - phase*2)",
    "needsInput": "step(0.8, 0.5 + 0.5*sin(phase*6))",
    "done":       "pyramid(pos) * decay(0.6)",
    "idle":       "0"
  },

  // Sleep display (Tier 1)
  "sleep": { "face": "-  ‿  -", "zzz": true }
}
```

Named levels, not raw numbers — an author (or an image model writing the theme)
knows "slow", not `0.012`. Same reasoning as the single-colour ramp control.

## The formula language (Tier 2)

Pure math. No assignment, no loops, no branching beyond `step` / `min` / `max`.
Bounded evaluation. A parse error drops **that one formula** and logs — the panel
falls back, never breaks.

- **Variables:** `pos` (0…1 across the row), `phase` (monotonic time), `energy`
  (0…1 now), `bar` (index), `count` (total bars)
- **Functions:** `sin cos abs min max floor pow sqrt exp`, `step(t, x)`,
  `pulse(centre, width, x)`, `wrap(x)`
- **The 8 built-ins are callable** — `wave(pos)`, `ripple(pos)`, `pyramid(pos)` …
  so a formula can lean on one and bend it
- **`decay(seconds)`** — valid only in `shape.done`: 1.0 at the finish edge,
  ramps to 0 over that span. This is the transient mechanism.

Whatever a formula returns is clamped to 0…1 by stage 4 regardless, so a bad
range is ugly, not fatal.

### The eight built-ins

| Name | Character |
|---|---|
| `wave` | one travelling sine crest, ~1 wave across |
| `ripple` | concentric rings expanding from the centre |
| `chase` | one bright column sweeping across and wrapping |
| `pyramid` | triangle, tall in the middle, breathing in and out |
| `sawtooth` | ramps that climb and snap back, marching sideways |
| `butterfly` | mirrored halves, wings opening and closing |
| `heartbeat` | flat floor with a pulse that crosses on a beat |
| `spectrum` | two frequencies, one fast — classic jittery noise |

## Per-state shapes and the resolution model

Four formulas, keyed by session state, plus a rule for combining them when
sessions disagree.

| State | Its formula is for | Amplitude | Lifetime |
|---|---|---|---|
| `idle` | the resting texture (usually flat / the sleep face) | ~0 | continuous |
| `working` | the continuous driver — the spectrum you watch | `sensitivity(count)` | **continuous, no cap** — the motion is a true signal; killing it would lie |
| `needsInput` | what "stop and look" looks like in motion | full | **escalate then sustain** — strobe for ~15s (theme-tunable), then fall to the persistent lit red floor until answered |
| `done` | a one-shot flourish when a turn finishes | decays per `decay()` | bounded by its own decay span |

### Rules

- **Priority, every frame:** `needsInput` > `working` > `idle`. Highest present
  wins outright. No queue, no memory.
- **Ramp** is hot if *any* `needsInput` is present, else normal.
- **`done` is not a priority rung — it is an edge.** A `working → finished`
  transition fires a decaying bloom, added on top of whatever the priority
  winner drew. **One slot:** a second finish re-triggers it, never stacks.
  **Suppressed entirely while any `needsInput` is present** — hard cut, not a
  decay-out.
- **Answering `needsInput` is not a `done`.** No bloom when an alarm clears; it
  just uncovers what is beneath.
- **Everything eases** via `feel.fall`. The one thing that *cuts*: an alarm
  appearing.
- **"At rest"** (→ schedule the sleep message, stop the render timer) =
  `energy < .01 && all levels < .01 && all peaks < .01`. Not just the bars —
  peak markers fall on their own slower schedule and freeze mid-air as stray
  dashes if you stop on the bars alone. The code already learned this.

### Working-shape fallback chain

Most specific wins:

```
shape.working formula  ->  patterns list rotation  ->  all 8 built-ins
```

Setting both `shape.working` and `patterns` → formula honoured, list ignored,
logged at load.

### Scenario table

`█` lit `·` dark, bottom row is the floor. Priority winner in bold.

| # | Sessions now | Edge this frame | Winner | `done` bloom? | What shows |
|---|---|---|---|---|---|
| 1 | 3 idle | — | **idle** | no | flat → delay → sleep face → message sweep |
| 2 | 1 working | — | **working** | no | `shape.working`, amp = sensitivity(1) |
| 3 | 3 working | — | **working** | no | same shape, amp = sensitivity(3), taller |
| 4 | 1 working, 2 idle | — | **working** | no | working shape; idles ignored |
| 5 | 2 working, 1 idle | C: working→done | **working** | yes | spectrum continues + one bloom through it |
| 6 | all idle (last worker left) | A: working→done | **idle** | yes | bars ease down, bloom over the settle → flat → sleep |
| 7 | 1 working | B & C finish same frame | **working** | one | working shape + a single bloom (slot refreshed) |
| 8 | all idle | B & C finish same frame | **idle** | one | ease down, single bloom, → flat |
| 9 | 1 needsInput, 2 working | A → needsInput | **needsInput** | no | strobe seizes, full + hot; workers ignored |
| 10 | 1 needsInput, 1 working | C: working→done | **needsInput** | suppressed | pure alarm strobe; the finish spark is discarded |
| 11 | 1 working (was 1 nI + 1 w) | A answered | **working** | no | ramp cools, bars ease from strobe back to `shape.working` |
| 12 | 1 idle (was only session, nI) | A answered → idle | **idle** | no | ease to flat; no bloom (answering ≠ done) |
| 13 | all idle | A (ex-nI, resumed) later finishes | **idle** | yes | normal bloom when it genuinely finishes its turn |
| 14 | 1 needsInput (held >15s) | escalation window elapsed | **needsInput** | no | strobe decays to motionless lit red floor, still hot |
| 15 | 1 needsInput on red floor | B → needsInput (new) | **needsInput** | no | strobe restarts (per-edge escalation) → settles again |
| 16 | 2 needsInput | A answered | **needsInput** | no | still one hot strobe/floor for B; no re-escalation |
| 17 | all idle (was 1 nI + 1 w) | A answered **and** B finishes, same frame | **idle** | yes | no needsInput present this frame → bloom allowed |
| 18 | 1 working (was idle, bloom mid-decay) | C → working | **working** | (finishing) | working shape takes over; leftover bloom decays additively on top |
| 19 | 1 needsInput (was idle, bloom mid-decay) | D → needsInput | **needsInput** | cut | bloom hard-cut, strobe seizes instantly |
| 20 | 1 working (was idle, message sweeping) | C → working | **working** | no | message keeps scrolling, bars run under it with the wake |

## Worked example: `swell` (an ocean wave)

The built-in `wave` is a *sine* — repeating, symmetric. An ocean wave is one
swell: gentle back, steep face, a crest that rolls through and resets. It is not
a primitive, it is a **composition**, and it is the flagship formula example
because building it exercises `wrap`, `max`, `exp` and asymmetry in one go.

```
·············███········   long gentle slope building from behind
··········██████········
·······██████████·······   tall crest — the renderer's peak marker
····█████████████·······     sits on top as the whitecap
██████████████████······   then a cliff, then flat water ahead
```

```
head = wrap(phase * 0.15)              // crest position, loops across
back = max(0, head - pos) * 0.7        // small coefficient -> gentle slope behind
face = max(0, pos - head) * 4.0        // big coefficient -> steep drop ahead
      exp(-((back + face)^2) / 0.05)
```

`back` is zero ahead of the crest, `face` is zero behind it, so adding them gives
one asymmetric hump. Swap the coefficients and the wave breaks the other way.

**Decision (2026-08-27):** ship `swell` as this worked example in `THEMING.md`,
**not** as a ninth built-in — the eight stay clean as distinct families, and a
composition teaches the language better than another abstract sample.
`spacyAppsAquariumTheme` is the natural first consumer: set its `shape.working`
to `swell` once Tier 2 exists. Do not touch the aquarium theme before then —
there is nothing for it to hook into.

## Back-compat

Every key optional. The default theme and every existing theme are untouched: no
`shape`, no `feel` → the eight patterns rotate on the current ballistics with
the current sleep face, exactly as today.

## Documentation obligations

Per the theme-change rule, the `feel` levels and the formula vocabulary land in
three places or they drift:

- `docs/THEMING.md` — the explanation, with the `swell` worked example
- `Sources/GroundControl/Theming/ThemePromptText.swift` /
  `ThemeFramePrompt.swift` — the instruction, phrased for whoever generates the
  theme
- each theme's own `PROMPT` files — so regenerating repeats the choice

## Open questions — closed 2026-08-27

1. **A new alarm while another is already settled on the red floor** (row 15) →
   **re-escalates.** Escalation is per-edge; a second thing needing you is news.
   When it settles again, both are just "needs you".
2. **Same-frame alarm-clear + finish edge** (row 17) → **the bloom fires.** No
   `needsInput` is present *that* frame and we keep no memory. The bloom's timing
   depends on frame boundaries when two edges land together; that is acceptable.
3. **A finish that happens under an alarm** (row 10 vs 13) → **the flourish is
   lost.** No deferred bloom when the alarm clears — deferring reintroduces
   memory. A lost celebration is fine.
4. **`sensitivity(count)` as workers finish one by one** → amplitude eases down
   *and* each finish blooms: two easings the same direction. Confirmed this
   reads as "winding down", not a muddle.
