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
- **`ExtraThemes/` is in `.gitignore`** and lives on disk untracked, with its
  own private git repository inside it. `EXTRA_THEMES=1 ./Scripts/build-app.sh`
  still finds it; `Scripts/package-theme.sh` still ships it.
- **`Themes/spacyAppsLunarAvatar/LICENSE`** reserves the artwork while leaving
  `theme.json` free to copy. README and the Settings page had claimed for weeks
  that themes are licensed separately; this made it true where someone checks.
- **Secrets scanned across all history** — no keys, no Team ID, no signing
  identity, nothing in `.gitignore`'s "never commit" list ever committed.
- **`.github/pull_request_template.md`** states the no-patches policy before
  someone writes a patch rather than after.
- Backup of the pre-rewrite repo: `~/Desktop/avaterm-backup-before-history-rewrite.tar.gz`.

## Before pushing

**Decide about the commit author.** Some commits carry
`waltermak@WWW-MakBook-Air-2.local`. It is harmless and it is a machine name
that becomes public. Cleaning it is another history rewrite — free now, never
again after the first push. Skipping it is a perfectly reasonable choice; just
make it deliberately.

```bash
git filter-repo --email-callback '
  return b"walter.mak@gmail.com" if b"local" in email else email'
```

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

2. **Settings → General.** Description: *"A macOS menu-bar app that shows which
   of your AI agent sessions need you."* Topics: `macos`, `swift`, `appkit`,
   `claude-code`, `menubar`, `developer-tools`. Disable Wiki and Projects.
   **Keep Issues on** — bug reports and theme submissions are the channel that
   is actually wanted.

3. **Then flip it public.** The one step with no way back.

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

6. **First release.** Tag `v0.5.0`. Attach both:
   - the notarised app zip from `Scripts/build-zip.sh`
   - the theme zip from `Scripts/package-theme.sh ExtraThemes/spacyAppsUnicornOverlord`

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
   website agree rather than contradicting each other. Reasoning and the
   Octobox numbers are in `~/github/md files/groundcontrol-monetisation.md`.

## The rule underneath all of this

Everything above is reversible except publishing. Each step that cannot be
undone — going public, the first push, a history rewrite after that push —
happens once, in that order, and only after looking at the result of the step
before it.
