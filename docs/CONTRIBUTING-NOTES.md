# Notes for anyone reading the history

This repository is largely AI-assisted, and its commit history says so —
279 of its commits carry a `Co-Authored-By: Claude` trailer. That is left in
place deliberately. It is a real git convention, it is true, and removing it
from a public repository to look otherwise would misrepresent how the project
was built.

What is **not** kept is the `Claude-Session:` URL those commits used to carry.
It resolves for one account and nobody else, so in a public history it is a
dead link that invites a question it cannot answer. A `commit-msg` hook strips
it — `.git/hooks/commit-msg`, installed locally, since hooks do not travel with
a clone.

Commits made before 2026-09-12 still carry the URL. The history was left
unrewritten on purpose: 377 commits would all change hash to remove a line
that leaks nothing, and several commit messages cite other commits by hash.
