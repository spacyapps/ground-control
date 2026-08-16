// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// What the app tells you about itself, in Settings.
///
/// Every claim here was checked against the code before it was written, and the
/// wording is deliberately narrower than the marketing version. "Collects no
/// data" would be untrue — the app records a couple of hundred characters of
/// your prompts so a row can say what a session is doing. What is true, and
/// stronger, is that none of it leaves the machine and all of it expires.
///
/// Points rather than paragraphs: each line is one claim, which is how it gets
/// read and how it gets checked. A claim that stops being true can then be
/// struck out on its own instead of unpicked from the middle of a sentence.
///
/// If any of this stops being accurate, this file is wrong and must change with
/// the code. It is the one place in the project where a stale comment is a
/// false statement to a user rather than a note to a developer.
enum LegalText {
    static let privacyTitle = "What this app does, and does not do"

    static let privacy = """
        - **Nothing leaves your Mac.** No network connections of any kind: no \
        account, no telemetry, no crash reporting, no analytics, and no server \
        to send anything to.
        - **It does not watch you.** No keystrokes recorded, no screenshots \
        taken, nothing read from other applications' windows. It requests no \
        accessibility permissions.
        - **It reads what your agent already publishes.** Coding assistants \
        can run a command of your choosing when something happens — a \
        documented feature, configured in their own settings files. Ground \
        Control registers there, with your permission.
        - **What gets written.** One line per event: the session's folder and \
        name, its state, which terminal or editor it belongs to, and up to 240 \
        characters of the prompt or question so the row can say what is \
        happening. Enough to draw a row, and no more.
        - **It is deleted after a day.** Session files live in your system's \
        temporary folder and are removed 24 hours after their last activity. \
        Nothing is archived, and there is no history to mine.
        - **It does not act on your behalf.** It never types into your \
        terminal, never answers a prompt for you, and never runs a command \
        your agent proposed. Clicking a row brings that terminal or editor to \
        the front — that is the whole of it.
        - **The only other things it can open** are your themes folder, the \
        SpacyApps website, and the hook installer, each only when you choose \
        it from a menu.
        - **You can check every line of this.** The app is open source, and \
        the script it installs is a few hundred lines of readable Python at \
        ~/.groundcontrol/bin/cc-notify.
        """

    static let licenceTitle = "Licence"

    static let licence = """
        - Ground Control is free software, licensed under the **GNU Affero \
        General Public License, version 3 or later**.
        - You may use it for anything, study how it works, change it, and \
        share it — including commercially.
        - The condition is reciprocal: if you distribute the app or a modified \
        version, you must pass on the same freedoms and make your source \
        available under the same licence.
        - **Affero adds one thing to that:** if you run a modified version as \
        a network service, the people using it over the network must be \
        offered its source too. Ordinary use of this app on your own Mac is \
        unaffected — it makes no network connections at all.
        - The full text ships inside the app and is also at \
        gnu.org/licenses/agpl-3.0.html.
        - **Themes are not covered by it.** Artwork carries whatever licence \
        its author gives it, which is not necessarily this one — check with \
        whoever made a theme before redistributing it.
        - Copyright © 2026 Walter Mak.
        """

    static let disclaimerTitle = "Disclaimer"

    static let disclaimer = """
        - **There is no warranty.** This program is distributed in the hope \
        that it will be useful, but WITHOUT ANY WARRANTY — without even the \
        implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR \
        PURPOSE. See the GNU Affero General Public License for more detail.
        - **It is a monitor, not a safety system.** Ground Control reports \
        what your coding assistant tells it, when it tells it. A row may be \
        wrong, late, or missing.
        - **Some assistants never announce that they are waiting**, so those \
        rows never turn red at all. Do not rely on this to catch anything that \
        matters.
        - **It does not supervise your agent.** It cannot stop a command, undo \
        a change, or judge whether something should have happened. Whatever \
        your assistant does, it does with the permissions you gave it, and the \
        responsibility for that stays with you.
        - **Ground Control is not affiliated** with Anthropic, Cursor, xAI, \
        Google, or any other maker of the tools it observes. Product names \
        belong to their owners and are used only to say what works with what.
        """
}
