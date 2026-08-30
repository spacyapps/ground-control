# Security

## Reporting

Email **spacyapps@gmail.com** with "Ground Control security" in the subject.
Please don't open a public issue for anything exploitable. There's no bounty —
this is a solo project — but every report gets a reply and a fix.

## What Ground Control can and can't do

Ground Control is a menu-bar monitor. Its whole job is to read a folder of
`.jsonl` files that agent CLIs write, and to raise the terminal you click on.

- **No network.** The app opens no sockets, makes no HTTP requests, and has no
  listener. There is no telemetry, no update check, no remote configuration.
  Grep the source for `URLSession` — there are no hits.
- **No sandbox, and one entitlement.** The app is not App Sandboxed: it reads
  `$TMPDIR/groundcontrol/` and it drives Terminal and iTerm2 over Apple Events,
  neither of which a sandboxed app can do. The only entitlement is
  `com.apple.security.automation.apple-events`. macOS still prompts you the
  first time it scripts each app (TCC), and the only apps it ever scripts are
  iTerm2 and Terminal — the AppleScript it runs is two fixed templates in
  `Sources/GroundControl/Integration/TerminalFocuser.swift`, matching a tab by
  its tty and selecting it.
- **The input is untrusted and treated that way.** The `.jsonl` files live in a
  world-touchable temp folder, so anything reachable from them is validated
  against its real shape before use: session and agent ids must be
  `[A-Za-z0-9_-]` (they become filenames), a `tty` must be a `/dev/…` device
  path (it goes into an AppleScript string), and files past a generous size cap
  are not read. The assistant's message text is shown in a label and never
  reaches an execution path.
- **The hook installer merges, and backs up first.** `install-hooks.sh` edits
  `~/.claude/settings.json`, `~/.cursor/hooks.json` and the opencode config
  with `json.load` / `json.dump` — not text substitution — and copies each file
  to a timestamped `.bak-` before touching it. Your existing hooks are kept.
- **`cc-notify` reads the process tree, narrowly.** To name the app that owns a
  session it walks up its own parent chain with `ps -o ppid=,tty=,comm= -p
  <pid>` — parent pid, controlling tty, command name, one ancestor at a time.
  It does not read arguments, environment, open files or memory, and never
  looks at another user's processes.

## The formula evaluator

Themes can supply small maths expressions for the title-bar analyser
(`docs/MATRIX-CUSTOMISATION.md`). These are parsed by a hand-written recursive
descent parser in `Sources/MatrixKit/` — **not** `NSExpression` or any
`eval`-like facility. It accepts arithmetic and a fixed whitelist of pure
functions (`sin`, `sqrt`, `wrap`, `pulse`, …); there is no assignment, no
loop, no branching beyond a `step`, and the parser is depth-limited so a
deeply nested expression is a parse error, not a stack overflow.

## Themes

A theme is a folder of images and a `theme.json` you may have been handed by
someone else. It can't run code (see the formula note above) and can't reach
the network. Treat installing one the way you'd treat any folder of files from
another person — from people you trust.
