// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The fixed prose of the theme prompt.
///
/// Deliberately terse. A model needs constraints, not explanation, and every
/// paragraph of background is a paragraph competing with the rules that
/// actually decide whether the result works.
///
/// Note the JSON examples carry no comments: JSON forbids them, and a model
/// shown commented JSON will emit commented JSON. The keys are described in
/// tables instead.
enum ThemePromptText {
    static let preamble = """
    Design a theme for **Ground Control**, a small macOS menu-bar panel listing
    my running AI agent sessions. Dark, compact, always on screen.

    A theme is one folder: a `theme.json` manifest plus the images it names.
    Every key is optional — anything omitted falls back to a built-in default.
    """

    /// Stated before the first section, because the top of a prompt is where the
    /// working method gets decided. Buried at the bottom it arrives after the
    /// model has already planned to do everything at once.
    static let howWeWork = """
    ## How I want to work

    **In stages, and stop at the end of each one.** This paste covers the
    avatars only — the four faces. The panel's frame and the manifest are a
    second paste, sent once these are right.

    | Stage | What happens | Ends when |
    |---|---|---|
    | 1 | **Four questions** — a reference picture · the character · each state's mark · the rendering | I answer |
    | 2 | You draw all four faces as **stills** and show them at real size | you show me |
    | 3 | I confirm, or send notes | **I say yes** |
    | 4 | *Only if I asked for motion:* you animate the two states that move | the loops close |
    | 5 | You hand the four files back, and stop | — |

    Stage 1 is written out below — do not answer it from this table. Do not run
    ahead into the next stage either. Stage 3 is where two or three rounds of
    notes happen; that is the process working, not a failure of it.

    **Stills before motion, always.** Anything animated gets drawn as a single
    still first and approved before it becomes frames. A silhouette that reads
    wrong costs one drawing to fix now and every frame to fix later.

    """

    /// Part one's opening questions.
    ///
    /// It used to have one line — *"ask before you start if anything is
    /// ambiguous"* — which a model satisfies by deciding nothing is. Measured:
    /// a real session asked nothing at all in part one, drew straight from the
    /// form text, and only started asking when part two arrived with four
    /// questions written out.
    ///
    /// So these are the four decisions a form field cannot carry: a reference
    /// beats any description, the character has to be agreed before it is drawn
    /// four times, each state needs a *mark* chosen by the person who will read
    /// it, and the rendering decides whether any of it survives 48px.
    ///
    /// Deliberately absent: the mood palette, and which states animate. Both
    /// are already fixed by rules that were expensive to learn, and reopening
    /// them invites back the yellow-needsInput problem.
    static func questions(for brief: ThemeBrief) -> String {
        let reference = brief.hasReferenceImage ? "" : """
            1. **Do you have a picture of this character?** Attach it if so —
               working from one image beats any description, and it is the only
               reliable way all four faces end up the same character rather than
               four cousins. If not, say so and I will design one.

            """
        return """
        ## Ask me these questions first

        Ask them all at once, then wait. Do not draw anything until I answer.
        If I say "you choose" to any of them, choose and tell me what you chose.

        **Anything I have already answered above, do not ask again.** Read my
        answer back in one line and ask me to confirm it. The form I filled in
        was a sketch made before I was thinking about this properly, so it is
        worth checking — but being asked a question I have visibly answered
        reads as not having been listened to.

        \(reference)\(brief.hasReferenceImage ? "1" : "2"). **Is this the character?**
           Describe it back to me in one line before you draw it four times —
           species or object, what it is wearing or made of, what it is doing.
           A wrong guess here costs all four faces.

        \(brief.hasReferenceImage ? "2" : "3"). **What does each state do?**
           The colour of each is already decided below and is not up for
           discussion. What I need from you is the **mark** — the one big thing
           that changes. For example: asleep with Zs, hunched over and busy, an
           arm raised waiting for me, a checkmark or a thumbs-up when finished.
           Name one per state, or say "you choose".

        \(brief.hasReferenceImage ? "3" : "4"). **How should it be drawn?**
           Flat vector, painted, pixel art, cel-shaded, 3D render, ink. This
           decides whether it survives being shrunk to \(brief.avatarSize)pt
           more than any other answer.
        """
    }

    static let paletteReference = """
    ## Keys

    | Key | Value |
    |---|---|
    | `colors.*` | `#rrggbb` or `#rrggbbaa` |
    | `avatar.states.{idle,working,needsInput,done}` | `{ "image": "file.png" }` |
    | `avatar.size` / `position` / `cornerRadius` | number, `left` or `right`, number |
    | `window.image` | filename of the skin |
    | `window.lockAspect` | `true` keeps proportions and rows scroll; `false` grows with sessions and the art slices |
    | `window.removeBackground` | `"auto"`, `"checkerboard"`, or a hex colour to key out |
    | `window.capInsets` | `{ top, left, bottom, right }` — only when `lockAspect` is false |
    | `layout.contentInset` | holds rows inside your border — panel points, 8–48 |
    | `matrix.messages` | array of phrases, 13 chars max, A–Z 0–9 `. - !` only |

    ## Colours

    | Key | Paints |
    |---|---|
    | `windowBackground` | the panel's base colour, painted under any artwork |
    | `titleBarBackground` / `titleBarText` | title strip |
    | `rowBackground` / `rowBackgroundAlt` | alternating rows — **give these alpha** so a background shows through |
    | `rowBackgroundHover` | row under the pointer |
    | `sessionName` / `message` / `messageDim` | row text |
    | `needsAction` | **the alarm** — must jump out |
    | `working` / `idle` / `accent` | state accents |
    | `divider` | hairlines |
    | `matrix.{low,high,alarm,unlit,text,peak}` | the title-bar analyser |

    Contrast matters more than prettiness: `needsAction` has to be visible
    across a room, and `messageDim` still has to be readable.
    """

    /// What each state has to look like, and what happens when one of the four
    /// colours is overruled — which is where the system fell over in practice:
    /// a yellow needsInput sat next to a gold working and nothing forbade it.
    static let moodColours = """
        | state | read it as | carry it with |
        |---|---|---|
        | idle | asleep, nothing wanted | **blue**, quiet — see below |
        | working | busy, leave it alone | **motion.** Any colour but the other three |
        | needsInput | **stop and look** | **red**, highest contrast of the four, plus a symbol |
        | done | finished well | **green**, calm but bright |

        **On idle: the tile recedes, the mark does not.** Taken as "make it all
        dim" you get a tile with nothing to see on a dark panel. The shipped
        station theme is a deep blue field with one huge bright sleep-mark on
        it — quiet overall, unmistakable at a glance.

        **If I overrule one of these, the others have to move too.** The system
        is that all four are instantly distinguishable, not that the colours are
        sacred — so if I ask for a yellow needsInput, working cannot stay gold.
        Say so and propose what working becomes.

        Red, green and blue are spoken for, and they are the three anyone reads
        instantly. There is no obvious fourth, so do not go looking for one:
        `working` is the state that moves, and motion carries it better than any
        hue could. Both existing themes landed on a neutral violet there and it
        reads perfectly.

        **The same character in all four.** Whatever it is appears in every
        state; only its pose, colour and surroundings change. Props may come and
        go, the character may not — four tiles that each star something different
        read as four themes.
        """
}
