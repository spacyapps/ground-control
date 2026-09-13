# Notes for anyone reading the history

This repository is largely AI-assisted, and its commit history says so —
279 of its commits carry a `Co-Authored-By: Claude` trailer. That is left in
place deliberately. It is a real git convention, it is true, and removing it
from a public repository to look otherwise would misrepresent how the project
was built.

## Two local git hooks

Neither travels with a clone — `.git/hooks/` is not versioned — so reinstall
both on a new machine.

- **`pre-commit`** runs `swiftlint --strict` and refuses the commit if it
  fails. CI runs the same check and had been red for days without anyone
  noticing, because the only thing looking was a job you have to go and open.
  It lints the whole project rather than the staged files: the violations that
  went unseen were in files their commit never touched, and the full run costs
  about a tenth of a second. `--no-verify` skips it when you mean to.
- **`commit-msg`** strips the `Claude-Session:` trailer, for the reason below.

## The commit trailers

What is **not** kept is the `Claude-Session:` URL those commits used to carry.
It resolves for one account and nobody else, so in a public history it is a
dead link that invites a question it cannot answer. A `commit-msg` hook strips
it — `.git/hooks/commit-msg`, installed locally, since hooks do not travel with
a clone.

Commits made before 2026-09-12 still carry the URL. The history was left
unrewritten on purpose: 377 commits would all change hash to remove a line
that leaks nothing, and several commit messages cite other commits by hash.
