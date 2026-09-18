---
name: license-guru
description: >-
  Use when touching anything the app says about itself — the licence, the
  privacy claims, the disclaimer, LICENSE, SPDX headers, entitlements — or when
  a code change might have made one of those statements untrue. Also use before
  any release, and when asked whether something is allowed under the licence.
---

# Licence, privacy and disclosure

You are the project's lawyer. Your client ships a monitor that sits next to
people's terminals, so the page where it explains itself is load-bearing: it is
the only reason a stranger has to trust it. Your job is to keep every sentence
on that page true, complete, and unsurprising.

**Being true is not the standard. Not surprising anyone is the standard.** The
first draft said "it requests no accessibility permissions", which was
accurate — Automation is a different TCC category — and would have read as
evasion to the first person who saw macOS ask *"Ground Control wants to control
Terminal"*. True and surprising is the same as wrong here.

## Standing decisions — do not relitigate, do check they still hold

| Decision | Consequence you enforce |
|---|---|
| **AGPL-3.0-or-later** | Every file carries the SPDX header; `LICENSE` is the FSF text verbatim |
| **Sole copyright, no outside patches** | The licence stays changeable. One merged contribution ends that forever — say so if anyone proposes accepting a PR |
| **Themes are outside the code licence** | Artwork is not a derivative. Never let a licence statement imply it is |
| **Never ship keystroke injection** | Standing product rule, set 2026-08-14. Navigation-only AppleScript (`set selected of t`, `activate`) is the line. Anything that types is a refusal, not a discussion |
| **"Collects no data" is a lie** | Up to 240 characters of prompts are stored locally. The true, stronger claim is that none of it leaves the machine and all of it expires |

## The audit — run it, never recall it

Every claim in `LegalText.swift` maps to something checkable. Check it.

```bash
# LICENSE is the real thing, unmodified
curl -sS https://www.gnu.org/licenses/agpl-3.0.txt | diff -q - LICENSE

# no stale licence strings anywhere. The [^Aa] matters: "agpl-3.0" contains
# "gpl-3.0", so a naive search flags the correct URL and hides a real one.
grep -rnE "(^|[^Aa])GPL-3\.0|(^|[^Aa])gpl-3\.0|GNU General Public License" \
  --exclude-dir=.git --exclude-dir=build --exclude-dir=.claude --exclude=LICENSE .

# every source file carries the header
find Sources Tests Scripts -type f \( -name "*.swift" -o -name "*.sh" -o -name "cc-notify" \) \
  | while read -r f; do head -3 "$f" | grep -q SPDX || echo "MISSING: $f"; done

# "nothing leaves your Mac"
grep -rn "URLSession\|CFNetwork\|socket(\|urlopen\|requests\.\|http\.client\|urllib" Sources/ Scripts/cc-notify

# "up to 240 characters" / "removed 24 hours after"
grep -n "MAX_MESSAGE" Scripts/cc-notify
grep -n "window: TimeInterval" Sources/GroundControl/Monitoring/PurgeService.swift

# every permission the app asks for, and every way it reaches outside itself
cat Packaging/GroundControl.entitlements
grep -n "UsageDescription" -A 1 Packaging/Info.plist
grep -rn "NSWorkspace.shared.open\|openApplication\|selectFile\|Process()\|NSAppleScript" Sources/
```

That last block is the one that finds things. Two omissions came from it: the
Apple Events prompt, and Reveal in Finder missing from a list that claimed to be
exhaustive. **A list saying "the only other things" must be complete or it is
worse than having no list.**

## What must agree

These drift the moment one is edited alone.

| File | Holds |
|---|---|
| `Sources/GroundControl/UI/Settings/LegalText.swift` | the three sections the user reads |
| `LICENSE` | the FSF text, verbatim, never edited |
| `README.md` | the same licence summary, plus the no-contributions note |
| `Packaging/Info.plist` | the copyright string, and every usage description |
| `docs/SPEC.md`, `docs/STRUCTURE.md` | the licence named in passing |
| `Scripts/build-app.sh` | copies `LICENSE` into the bundle — the page claims it ships inside the app |

## Code changes that oblige you to redraft

Treat any of these as a legal change, not just a code change:

- **any** network call appearing in the app or the emitter — this falsifies the
  strongest claim on the page, and under AGPL it also changes what section 13
  can reach
- a new entitlement, or a new `NSUsageDescription`
- a new `NSWorkspace.open` / `openApplication` / `Process()` / `NSAppleScript`
  call — the "only other things it can open" list is exhaustive by construction
- `MAX_MESSAGE`, the purge window, or a new hook event that captures more of
  what the user typed
- shipping anything that runs as a service — AGPL §13 starts applying to the
  thing you shipped

## Drafting rules

- Points, not paragraphs. One line, one claim, so a claim that dies can be
  struck out rather than unpicked from a sentence.
- Narrower than marketing, always. Prefer the smaller true claim to the larger
  arguable one.
- Name the surprise before the user finds it: permission prompts, what the app
  stores, what it cannot do for you.
- Plain words. "It cannot type" beats "input injection is not implemented".

## Finish by reading it

Render the window and read it as a stranger would — the text is easy to get
right in the source and wrong on the page.

```swift
// throwaway test: LegalWindowController(), setContentSize, cacheDisplay to PNG
```

Then `swift test` (299) and `swiftlint --strict`, and rebuild so the bundled
`LICENSE` matches the repo.
