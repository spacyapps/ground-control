---
name: theme-change
description: >-
  Use when changing a theme's artwork or manifest in Themes/, or when changing
  how theming works. Covers what to re-measure, and the three places a new rule
  has to be written down so the next theme does not repeat the mistake.
---

# Changing a theme

Two halves. The first is measurable and `ThemeIntegrityTests` already enforces
it. The second is judgement, and is why this file exists.

## 1. Re-measure — never carry numbers over

New artwork means every number in the manifest is suspect. They are all in
**artwork pixels**, and caps are drawn **1:1 in points**, so redrawing at a
different size silently invalidates the lot.

```
swift Scripts/fit-frame-art.swift <art> <out> 450
```

It resizes and prints where the ornament ends and the cap that joins most
cleanly. Then `swift test --filter ThemeIntegrityTests`, which checks caps clear
the ornament, the silhouette holds across frames, the loop closes, and keying
left no residue.

If a check fails, fix the manifest — do not widen the threshold. Each one is a
bug that already cost an evening.

## 2. Ask whether this taught us a rule

If the change revealed something a theme author could not have known, it belongs
in **three places**, and they drift apart the moment one is updated alone:

| Where | What goes there |
|---|---|
| `docs/THEMING.md` | the explanation, with the numbers that made it obvious |
| `Sources/GroundControl/Theming/ThemeFramePrompt.swift` | the instruction, phrased for whoever generates the artwork |
| `<theme>/PROMPT-1-moods.md` and `PROMPT-2-frame.md` | the brief in two stages, so regenerating repeats the fix rather than rediscovering it |

Rules learned this way so far: caps are points and must be re-measured after any
redraw; corner ornaments point *outward*, away from the opening; an animation's
silhouette must be pixel-identical across frames and its loop must close.

**Check the prompt actually says it.** The prompt is assembled from several
pieces; reading the source is not the same as reading what the model receives.
Render it and look — one bad number in there was still teaching `capInsets: 75`
long after the code was fixed.

## 3. Mirror, rebuild, and mind the emitter

`Themes/` in the repo is what ships; `~/Library/Application Support/GroundControl/Themes/`
is what runs. `ThemeSeeder` never overwrites an existing folder, so a change
made in one is invisible to the other until copied.

If `Scripts/cc-notify` changed too, rebuild **before** relying on the result:
`HookUpdater` replaces the installed emitter with the one inside the app at
launch, so a stale build silently reinstalls an older script.
