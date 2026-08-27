# Publishing this repo

Written 2026-08-16, before the first push. Not urgent — the repo has no remote
and nothing here is time-sensitive. It exists so the reasoning is not
reconstructed from memory on the day it matters.

## Already done

These were finished on 2026-08-16 and need no repeating.

- **The unicorn theme is out of the repo and out of its history.** A public repo
  carrying only an AGPL `LICENSE` reads as licensing everything in it under the
  AGPL, which grants redistribution — and that artwork is meant to be sold.
  Removed with `git filter-repo --path ExtraThemes --invert-paths`, which took
  the repo from 174 commits to 172 and dropped 14 objects.
- **Extra themes live outside the repository**, at
  `~/Documents/Projects/GroundControlThemes`, with their own private git
  history. `EXTRA_THEMES=1 ./Scripts/build-app.sh` finds them there via
  `EXTRA_THEMES_DIR`; `Scripts/package-theme.sh` packages one for sale.
  `ExtraThemes/` stays in `.gitignore` as a guard against it coming back.
- **`Themes/spacyAppsLunarAvatar/LICENSE`** reserves the artwork while leaving
  `theme.json` free to copy. README and the Settings page had claimed for weeks
  that themes are licensed separately; this made it true where someone checks.
- **Secrets scanned across all history** — no keys, no Team ID, no signing
  identity, nothing in `.gitignore`'s "never commit" list ever committed.
- **`.github/pull_request_template.md`** states the no-patches policy before
  someone writes a patch rather than after.
- Backup of the pre-rewrite repo: `~/Desktop/avaterm-backup-before-history-rewrite.tar.gz`.

## Before pushing

**The commit author is already dealt with.** Done 2026-08-16, after the first
push but while the repo was still private and unforked — 178 commits rewritten
from `walter.mak@gmail.com` and `waltermak@WWW-MakBook-Air-2.local` to
`spacyapps@gmail.com`, then force-pushed. The working tree was diffed against a
backup to prove only metadata moved.

`user.email` is now set on this repo and on the private themes one. It
was unset globally, which is why 119 commits had an address git derived from
the machine name — worth setting globally too, or the next new repo repeats it.

**Do not rewrite history again once the repo is public.** A force-push then
breaks every clone and fork, and looks like an incident.

**Re-run the licence audit.** `/license-guru`, or by hand: `LICENSE` identical
to the FSF text, every file carrying an SPDX header, no networking API anywhere,
and the Settings page matching what the code does.

## Creating the repo

1. **Private first.** Under the personal account, which is already named
   `spacyapps` — no organisation. An org would need that name freed up first,
   which means renaming the personal account and breaking every link into it,
   and it would buy nothing: there are no collaborators and the account name is
   already the brand. A single repo can be transferred into an org later,
   keeping its stars, issues and a redirect, so waiting costs nothing.

   ```bash
   gh repo create spacyapps/ground-control --private --source=. --remote=origin
   git push -u origin main
   ```

   Then read it on the web as a stranger would: file tree, rendered README,
   the licence GitHub detects, what the first screenful says. **Flip to public
   only once that looks right** — a repo published by accident cannot be
   unpublished, because it is cloned and cached within minutes.

2. **Settings → General.** Done 2026-08-26: description, topics
   (`macos`, `swift`, `appkit`, `claude-code`, `opencode`, `menubar`,
   `developer-tools`) and homepage (`spacyapps.com/apps/ground-control`, the
   product page — not the site root) all set via `gh repo edit`. Wiki and
   Projects both off. **Issues stays on** — bug reports and theme submissions
   are the channel that is actually wanted.

3. **Then flip it public.** The one step with no way back.

## Still open, as of the 2026-08-26 audit

Everything in "Creating the repo" above is done except the flip itself. What's
left before that flip is worth pulling the trigger on:

- **The first GitHub Release doesn't exist yet.** The README already tells
  people to download from Releases — true once this exists, misleading until
  then. Tag it, attach the notarised zip from `Scripts/build-zip.sh` and the
  theme zip from `Scripts/package-theme.sh`, per item 6 below. Not urgent
  while private; blocking once public.
- **Re-run the licence audit** (already asked for above, repeating it here
  because it's easy to forget under "before pushing" when the push already
  happened): `/license-guru`, or by hand — `LICENSE` identical to the FSF
  text, every file carrying an SPDX header, no networking API anywhere, the
  Settings page matching what the code actually does.
- **Final "read it as a stranger" pass** — file tree, rendered README, the
  licence GitHub detects, what the first screenful says. Do this last, right
  before the flip, since it's the last chance to catch something before a
  clone makes it permanent.

## After it is public — not before

Both of these are unavailable on a free private repo, which is confusing enough
to be worth stating: the settings are missing rather than hidden.

4. **Social preview image.** Settings → General → Social preview. A private
   repo that has never had one does not offer the upload at all — GitHub only
   allows it on a private repo *that already had an image*. PNG/JPG/GIF, under
   1 MB, 1280x640 for best display. A screenshot of the panel wearing the lunar
   theme does more work here than any amount of README polish, because this is
   what renders wherever the link is posted.

5. **Branch ruleset on `main`.** Settings → Rules → Rulesets → New ruleset,
   target the default branch, tick **Block force pushes**. On a free personal
   account this is not enforced while the repo is private — GitHub says so in
   an amber banner. Check that banner is gone afterwards, or the rule exists
   without doing anything.

   It guards against one person: you. Nobody else can push. The realistic
   accident is a `git push --force` overwriting history, which is not
   hypothetical — this repo had its history rewritten on the day it was created.

6. **First release.** Tag whatever `CFBundleShortVersionString` reads in
   `Packaging/Info.plist` at the time (0.7.1 as of 2026-08-26 — check rather
   than trust this number, it moves). Attach both:
   - the notarised app zip from `Scripts/build-zip.sh`
   - the theme zip from
     `Scripts/package-theme.sh ~/Documents/Projects/GroundControlThemes/spacyAppsUnicornOverlord`

   The theme being a release asset rather than a repo file is the whole point of
   the separation above.

## The website

7. **Link to Releases, not to the repo.** The download button points at
   `/releases/latest`; a smaller "Source on GitHub" link points at the repo.
   Most visitors want the app. The source link is a trust signal, not a call to
   action.

8. **One line about the licence**, on the page: *"Free and open source,
   AGPL-3.0. Themes are sold separately."* That sentence carries the trust
   pitch, the donation pitch and the theme-shop setup at once.

9. **Funding last.** `.github/FUNDING.yml` is committed with its entries
   commented out. Fill it in once the site exists, so the Sponsor button and the
   website agree rather than contradicting each other. Full reasoning in
   `~/github/md files/groundcontrol-monetisation.md`; the settled steps:

   - **Ko-fi first.** 0% fee, no application, works even before the repo is
     public. `ko_fi:` in `FUNDING.yml`.
   - **GitHub Sponsors once public** — eligibility requires public
     open-source work, so this genuinely cannot happen before the flip.
     2FA → apply at github.com/sponsors → Stripe Connect → W-8BEN → a few
     days' review → `github:` in `FUNDING.yml`. Suggested tiers: **$5 / $15 /
     $50 one-time, nothing monthly** — a menu-bar utility isn't a
     subscription relationship. This also renders the supporters wall
     automatically; nothing to build on the site for it.
   - Both can run at once; the doc has the fee table.

10. **Where to sell themes — still genuinely open.** `Scripts/package-theme.sh`
    already produces the sellable artifact; no storefront is chosen yet.
    The monetisation doc's own fee table flags **Polar (~4%)** as "worth it
    once themes are sold from the same place [as donations]" — consolidating
    both revenue streams on one platform once Sponsors/Ko-fi are running is
    a reasonable default, but this is a real decision still to make, not
    settled the way the funding steps above are.

## Marketing — not addressed anywhere else, worth a placeholder

The monetisation doc covers *how this makes money*, not *how anyone hears about
it*. Nothing here is decided. Common channels for a niche macOS dev tool, for
when there's a public repo and a first release to point at: Show HN, r/macapps
and r/ClaudeAI, Product Hunt. Pick a moment worth spending a launch on rather
than posting the day it goes public — a repo with zero stars and no release
history reads worse than waiting a week.

## The rule underneath all of this

Everything above is reversible except publishing. Each step that cannot be
undone — going public, the first push, a history rewrite after that push —
happens once, in that order, and only after looking at the result of the step
before it.
