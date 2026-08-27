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
    second paste, sent once these are right. There is an optional third paste
    at the end, for corner decorations — small, fixed pieces of art anchored
    to a corner of the panel, independent of the frame. Skip it entirely if
    you don't want one; most themes won't.

    | Stage | What happens | Ends when |
    |---|---|---|
    | 1 | **Four questions** — a reference picture · the character · each state's mark · the rendering | I answer |
    | 2 | You draw all four faces as **stills** and show them at real size | you show me |
    | 3 | I confirm, or send notes | **I say yes** |
    | 4 | You price the animation and ask; *only then* animate the two that move | **I say go ahead** |
    | 5 | You hand the four files back, and stop | — |

    Stage 1 is written out below — do not answer it from this table. Do not run
    ahead into the next stage either.

    **Expect two or three rounds at stage 3.** I will have notes, and the notes
    are the good part — they are where the thing stops looking like everybody
    else's. A revisit is the process working, not a failure of it.

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

    /// The two ways to make the frames, offered rather than chosen.
    ///
    /// This section has been written three ways in one evening: stills-only,
    /// then video-only, now both. Each absolute came from one person's most
    /// recent attempt, and neither survived the next one. They fail in
    /// different currencies — jitter against tokens — so the choice belongs to
    /// whoever is paying, and the honest thing is to say what each costs and
    /// let them answer.
    static let motionRoutes = """
        ### Ask me how to make it

        First ask what I already have. If there is already a clip or an
        animated file sitting on my machine, that settles it — check it
        against what GC plays and skip straight to the rules below, whichever
        route it came from.

        **GC plays two families of animated file, natively, no conversion
        required:** `.gif` / `.apng` (an animated image, decoded frame by
        frame) and `.mov` / `.mp4` / `.m4v` (a real video clip, played by the
        system player). Neither is the "right" one — which you end up with
        should follow from what you already have or can make, not from a rule
        here.

        If nothing exists yet, there are two ways to make something, and they
        go wrong differently. Put this to me and wait — do not pick for me:

        | | How | What goes wrong |
        |---|---|---|
        | **Frame by frame** | each frame drawn separately | it can jitter |
        | **Video** | animate the still, one continuous generation | it costs tokens |

        **Frame by frame jitters** because every frame is an independent
        drawing, so the subject shifts a little between them. That is survivable
        for a few frames of one small thing — a lamp blinking, a glint — and
        obvious on anything larger. It naturally ends as a `.gif`.

        **Video holds the subject still**, because it is one continuous
        generation rather than many separate ones. What it costs is a video
        generation, in real tokens, and a clip that does not loop by itself.
        Keep the result as a `.mov` — converting it down to a `.gif` afterwards
        is only worth doing if you'd rather have the smaller, shareable file
        and don't mind the conversion pass; GC does not require it.

        Say which you would use and why, then let me decide. If I have no
        preference: video where a whole character or object moves,
        frame-by-frame for a light, a glint, or a blink.

        **If I choose frame by frame**, the danger is drift, so:

        - **Lock the silhouette.** Identical outer bounds on every frame. Never
          generate a frame from the previous one — that is what drifts.
        - **Lock the position.** The subject sits in exactly the same place in
          every frame; only the part that moves, moves. Two or three pixels of
          travel reads as a bounce, and at this size a bounce is all anyone
          sees.

        **If I choose video**, the danger is a model adding motion nobody asked
        for, so tell it all of this:

        - **Fixed camera.** No pan, no zoom, no dolly, no parallax.
        - **The subject does not travel or change size.** Only the one thing
          meant to move.
        - **The background stays exactly as drawn**, nothing new enters frame.
        - **Then trim it to a loop yourself** — a clip ends where it ends.

        **Either way:** the last frame must be a legal step *into* the first,
        not merely similar to it. Play the last, the first and the second in
        sequence and it should look no different from any other three.
        Ping-ponged poses fail this — they look alike at the wrap and still
        jump. Choose the frame count and rate deliberately, 8-24 frames at
        roughly 10fps; three seconds at 30fps is 90 frames and an enormous file
        for motion nobody can see at this size.
        """

    /// How the frames themselves are made, once something is being animated.
    ///
    /// Part one's copy: the same two routes as part two, since an avatar and a
    /// frame are animated the same way and there is no second opinion to have.
    static func frameCraft(size: Int) -> String {
        """
        **The two rules that hold whichever way you make them, and both have
        gone wrong before:** every frame has identical outer bounds, and the
        character sits in exactly the same place in each — a face that drifts
        two or three pixels does not read as animation, it reads as a bounce,
        and at \(size)pt a bounce is all anyone will see.

        \(motionRoutes)
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

    /// **Part three: corner decorations, optional.** Entirely fixed prose —
    /// nothing here depends on the brief — so it lives with the rest of the
    /// constant text rather than in the builder. Kept deliberately short
    /// against part two's length: there is no nine-slice to teach and no
    /// silhouette to negotiate, just a handful of rules and a shape to copy.
    static let partThreeCornerDecorations = """
    # Part three — corner decorations (optional)

    Skip this whole section if you don't want one — most themes are done
    after part two. A corner decoration is a small, independent piece of
    art pinned to one corner of the panel: a mascot, a light, a prop. It
    has nothing to do with the frame, and none of part two's rules apply
    to it.

    **The rules, in full — this is the whole feature:**

    - **Up to four, one per corner** — `topLeft`, `topRight`,
      `bottomLeft`, `bottomRight` — each entirely optional.
    - **Drawn at its own pixel size, always.** No fitting into a box, no
      automatic Retina scaling. Draw it at the size you want it to
      actually occupy on screen.
    - **`scale` resizes it without a new drawing.** 1 is the file's real
      size; less shrinks it, more grows it. Trying a different size is a
      number to change here, not a new image to generate.
    - **`offset` moves it from its corner** — screen direction, `x`
      right, `y` down, the same at every corner. `{0,0}` means its own
      matching corner sits exactly on the window's.
    - **Image or video, your choice.** `image` takes a still or animated
      gif/apng, keyed with `removeBackground` the same way every other
      image asset is. `video` takes `.mov`/`.mp4`/`.m4v` — no keying
      available for video, so it needs real alpha or an already-clean
      background.
    - **Animates only while something is working**, same rule as the
      rest of the panel. A still corner is a complete, finished choice.

    ```json
    "cornerDecorations": {
      "bottomRight": {
        "image": "mascot.apng",
        "scale": 1,
        "offset": { "x": 0, "y": 0 }
      }
    }
    ```

    That's all of it. A fuller guide, with worked examples, will
    eventually live at groundcontrol.app/docs — it is not live yet, so
    do not try to fetch it. Ask me directly if you want more than what
    is written above.
    """
}
