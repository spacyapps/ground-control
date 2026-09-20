# Grok Bot — integration notes

Everything learned probing xAI's **Grok Bot** desktop app on 2026-08-28, so the
next look is a read, not another evening. Nothing is built. `docs/LIMITATIONS.md`
carries the short "not supported" entry; this is the full record.

---

## Verdict

Grok Bot can give Ground Control a **clean "needs you" signal** and a **heartbeat
while a bot is actively emitting** — but **not** a reliable "done", sometimes for
minutes at a stretch. There are **no usable hooks**. The only local data is an
undocumented JSON cache.

Recommended shape if built: a grouped **Grok Bot** parent row, one child per bot,
each child either **needs you** (alert) or **unknown** (a designed neutral mood,
not a guessed "idle"). See [Design sketch](#design-sketch).

---

## What Grok Bot is

| | |
|---|---|
| Path | `/Applications/Grok Bot.app` (Electron, v0.30.0 as tested) |
| Bundle id | **`com.anysphere.sand`** — Anysphere, i.e. it is a **Cursor fork** |
| Also in the bundle | `cursor-machine-id`, `cursor-proclist` native module, `api2.cursor.sh`, `anysphere.cursor-mcp`, `~/.cursor/` as config root |
| Where the agent runs | an xAI **cloud desktop**, not this machine |
| Local bridge | `sand-local-exec-daemon` ("serving local exec over the gateway") — engages only when a bot runs a command *here*, after an in-app approval **and** a macOS TCC prompt |
| Config dir | `~/.grokbot/` (data root literal `.grokbot`); settings `~/.grokbot/settings.json` (MCP-focused, **no hooks key**) |
| Cloud agent store | `path` in the roster points at `/home/box/sand-data/agents/<id>/store.db` — a SQLite DB **on the cloud box**, not reachable locally |

---

## Hooks do not work — measured

The bundle carries Cursor's **entire hooks engine** —
`dist/local-exec-daemon/main.cjs` has the full event vocabulary
(`stop`, `afterAgentResponse`, `beforeSubmitPrompt`, `preToolUse`,
`sessionStart`, `beforeShellExecution`, …) and an explicit **Claude-Code
compatibility map** (`PreToolUse → preToolUse`, `Stop → stop`,
`SessionStart → sessionStart`, `UserPromptSubmit → beforeSubmitPrompt`;
`Notification` and `PermissionRequest` map to `null`).

`Scripts/probe-cursor-hooks.sh` was installed into `~/.cursor/hooks.json` (all 18
events), Grok Bot restarted, and **five turns** run:

| Turn | Probe hits |
|---|---|
| plain chat | 0 |
| inline decision card | 0 |
| local `ls ~/Desktop` (through the app approval + macOS TCC) | 0 |
| follow-up chat | 0 |
| long research turn | 0 |

**Grok Bot never consults a local `hooks.json`.** The engine is dormant code,
driven only by cloud-pushed `HooksConfigInfo` (a protobuf with `configured_steps`).
Local command approval is its own `~/.grokbot/local-tool-approvals.json` ledger,
written *after* approval — not a live "waiting" signal.

---

## The local cache

```
~/Library/Application Support/Grok Bot/sand-client-persistence/*.blob
```

Plaintext JSON. Filenames are **base32** of a slice key
(`base64.b32decode(name.upper() + padding)`). Decoded keys seen:

| Slice key (after `sand.client.slice.`) | Holds |
|---|---|
| `account.<acct>.roster.last-roster` | **the one that matters** — one row per bot |
| `account.<acct>.transcript.replicas.<conversationUUID>` | full transcript, one file per conversation |
| `account.<acct>.composer-drafts` | the message box draft — rewritten per keystroke, **ignore** |
| `account.<acct>.send-journal` | outgoing queue (`records: []` when idle) |
| `account.<acct>.selection.last-agent` | which bot is selected |
| `account.<acct>.sidebar.last-sections` | sidebar UI |
| `ui-layout`, `client-meta.account-slot` | UI / account plumbing |

`<acct>` is the account id, e.g. `google-oauth2%7Cuser_01KXVY…` (`%7C` is `|`).
**Multiple accounts → multiple roster files.** A watcher should glob `*.blob`,
decode names, and take every `*.roster.last-roster`.

Writes **burst** — roster + transcript can each be rewritten every ~2 s during an
active reply. Debounce.

---

## `roster.last-roster` field reference

Shape: `{ "schemaVersion": N, "value": { "rows": [ … ] } }`. **Tested at v3
(2026-08-28) and again at v4 (2026-09-19)** — the table below is v4, with the v3
difference called out. See "Schema v3 → v4" below before trusting any field.

| Field | Meaning / use |
|---|---|
| `id` | conversation/agent UUID — matches the `transcript.replicas.<id>` file and the cloud `store.db` path |
| `name` | display name (`"Researcher"`) — **the row label**, no empty-`cwd` guessing |
| `description` | one-liner ("Digs into any question across your tools and the web") |
| `avatarShape` / `avatarColor` | `"blob"` / `"magenta"` — could theme the row |
| `createdAt` | bot creation (ms) |
| `updatedAt` / `lastActivityAt` | **heartbeat** — advances on any bot output, including interim "on it…" notes. Recent movement ≈ active. Quiet ≈ **done *or* deferred** (see below) |
| `path` | `/home/box/sand-data/agents/<id>/store.db` — cloud box, not local |
| `lastEntry.kind` | **v4: this is the needs-you tell**, moved up from `sessionPreview`. `"text"` normally; `"widget_options"` is expected while a card waits, **unconfirmed under v4** — no card has been seen since the change |
| `lastEntry.text` | preview text of the last item. **Measured three times: it holds the last BOT message only.** A message *you* send advances the timestamps and leaves this untouched — see "Working, and who spoke last" |
| `lastEntry.sessionPreview.kind` | **v3 only. Gone in v4.** Was the same state machine now on `lastEntry.kind`: `"widget_options"` while a decision card is unanswered → `"widget_answered"` the instant it is tapped → back to `"text"` on the next reply |
| `lastMessageId` / `newestEntryId` | last transcript entry id |
| `hasUnread` / `unreadCount` | **focus-driven** — increments on a bot message while that bot's window is unfocused, resets to 0 on view. Not a clean "unseen" flag |
| `lastViewedAt` | when the user last looked |
| `awaitingUserResponse` | **stayed `null` through every test, including a live unanswered card and both approval prompts.** Reserved for a genuine mid-turn block (login wall / CAPTCHA on the cloud desktop — xAI docs: "Computer View State"). Never triggered; **unconfirmed** what a hard block writes. The bot, asked directly, said it does not set this itself and *"widgets may never set it"* — informed but not authoritative |
| `notificationsEnabled` / `notifyOnUpdatesEnabled` | per-bot notification prefs |
| `isHiddenFromSidebar` | user hid the row |
| `origin` | `"user"` |
| `isGroup` / `memberIds` | **channels** — a group room with multiple bots — vs a 1:1 chat (`false` / `[]`) |

---

## Schema v3 → v4 — measured 2026-09-19

The format moved, exactly where this document warned it would. **v4 broke the
alarm**: `GrokBotRoster` read `lastEntry.sessionPreview.kind`, which no longer
exists, so no Grok Bot row could turn red until the parser was taught both
shapes.

```
v3:  "lastEntry": { "sessionPreview": { "kind": "widget_options" }, … }
v4:  "lastEntry": { "kind": "text", "text": "On it — packing the profile…" }
```

| | v3 (2026-08-28) | v4 (2026-09-19) |
|---|---|---|
| needs-you tell | `lastEntry.sessionPreview.kind` | `lastEntry.kind` — wrapper gone |
| preview text | `lastEntry.text` | unchanged, and now known to be **bot messages only** |
| `awaitingUserResponse` | always null | still always null |
| new row fields | — | `harness`, `origin`, `lastViewedAt`, `lastMessageId`, `newestEntryId`, `isHiddenFromSidebar`, `notificationsEnabled`, `notifyOnUpdatesEnabled`, `voiceId` / `voiceLanguage` / `voiceSpeed` |
| slices on disk | roster, transcripts, drafts, send-journal, selection, sidebar | **identical** — no approvals or pending slice appeared |
| transcript schema | 1 | 1 |

Three things that look useful and are not:

- **`lastViewedAt`** reads like an "unseen" flag. It is not: on a bot actively
  waiting for an answer it sat *equal* to `lastActivityAt`. It marks rendering,
  not reading.
- **Auto-review** (Settings → Bot) makes Grok Bot ask before more actions. It
  writes nothing while it waits — approvals land in
  `~/.grokbot/local-tool-approvals.json` *after* the fact — so more prompts buy
  no signal and cost the user their automatic runs.
- **`sendAcceptanceV1`** in `connection.last-host-capabilities` is about
  acknowledging *outgoing* messages, not agent state. The `send-journal` slice
  is `records: []` unless a send is in flight.

Every `kind` value across every transcript on disk: `send-message`, `message`,
`agent`, `user-attachment`, `event`, `label`. **No approval or widget
vocabulary anywhere** — so nothing local describes a pending decision until one
is actually open.

## Working, and who spoke last — measured 2026-09-19

Three live turns, watched second by second. The heartbeat survives v4:

```
17:16:25  you send            updatedAt moves, lastEntry.text UNCHANGED
17:16:38  "On it — packing the full up-to-date Nami profile…"
17:16:51  "Sent 1 archive"
```

**`lastEntry` holds the last bot message only** — confirmed on three separate
sends. That gives two certainties from the roster alone, with no transcript
read:

| Roster says | Means |
|---|---|
| timestamps advanced, `lastEntry.text` unchanged | **you spoke, it has not answered** — working, certainly |
| `lastEntry.text` changed moments ago | it just emitted — working |
| `lastEntry.text` changed a while ago | done, waiting on you, **or tasked and not yet started** |

**Bot-to-bot delegation is visible, with a blind head start.** Nami was asked to
task Hitomi. Hitomi's row — untouched since the previous day — advanced on its
own at 17:20:46, with no user message to her. But Nami said "Sent" at 17:20:16:
for **thirty seconds** Hitomi was working and her row still read a day old.
Nothing marks a bot that has been tasked but has not spoken yet, and "you spoke
last" cannot cover it, because the user never spoke to her.

**Do not convert silence into "done" with a timer.** A cloud agent was measured
going quiet for **3 min 49 s** mid-task. Any working window shorter than that
will call a busy bot finished; any longer will call a finished bot busy. So:
claim *working* only while it is genuinely moving or while the user spoke last,
and otherwise claim nothing.


## "Needs you" signals

Three cases, in confidence order:

1. **Decision card pending** — `"widget_options"` as the *current* roster value.
   **Confirmed twice under v3**, at `lastEntry.sessionPreview.kind`. Under v4
   that wrapper is gone and the value should now be at `lastEntry.kind`, which
   is **unconfirmed** — no card has appeared since. Clears to `widget_answered`
   then `text` on answer. In the transcript the entry is
   `message.type == "widget"` (`{ prompt, options[], allowCustom, dismissOnMoveOn }`).
2. **Blocked on a local command** — the transcript carries
   `message.type == "local-tool-permission"`:
   `{ ask: { requestId, action: "run-command", target: "ls ~/Desktop", machineId } }`.
   Almost certainly surfaces in `lastEntry` / `sessionPreview` while pending —
   **exact roster shape unconfirmed** (only seen after the fact).
3. **Hard block (CAPTCHA / login)** — expected to set `awaitingUserResponse`.
   **Never triggered, unconfirmed.**

A watcher would alert on 1 and 2, and treat a non-null `awaitingUserResponse` as
3 for free.

---

## "Done" is not knowable

A long research turn watched live:

```
22:31:19  user asks
22:31:32  bot: "On it. Pulling memory bandwidth…"        (heartbeat)
22:31:45  bot: "This one's a longer pull. I'll come back…" (heartbeat)
22:31:45  ── SILENCE ──  no write of any kind
22:35:34  bot delivers the cited table, under a NEW requestId
```

**3 minutes 49 seconds** of dead air. The cloud agent ended the first request and
resumed later as a fresh one. For those ~4 minutes the roster file was
byte-identical to a finished turn. Entries carry **no `isStreaming`** — the cache
stores finalised messages, not token streams.

So a GC row can honestly show **active** (heartbeat moved recently) or
**needs you** — but "quiet" must render as **unknown**, never "done" or "idle".

---

## `transcript.replicas.<id>` format

`schemaVersion: 1`. `{ "schemaVersion": 1, "value": { "entries": [ … ] } }`.

Entry `kind`:

| kind | shape |
|---|---|
| `message` | user turn — `{ role: "user", content, richText, isStreaming, clientNonce, requestId }` |
| `send-message` | bot output — `{ id, message: { type: … }, timestampMs, requestId }` |
| `event` | app event — seen: `{ type: "automation-changed", action: "created", automationId, automationName }` |

`send-message` `message.type`:

| type | payload |
|---|---|
| `text` | `{ content }` |
| `widget` | `{ widget: { prompt, options[{label,value,style}], allowCustom, dismissOnMoveOn } }` |
| `local-tool-permission` | `{ ask: { requestId, action, target, machineId } }` |

A widget answer does **not** create its own entry — the bot's next `text` just
follows. `requestId` is shared within a request and **changes** when a deferred
turn resumes.

---

## Other local artifacts

| File | What |
|---|---|
| `~/.grokbot/local-tool-approvals.json` | granted approvals: `{ action, target, accountScope }` — written after the user allows |
| `~/.grokbot/local-tool-retirements.json` | retired approval ids |
| `~/.grokbot/local-exec-daemon.log` | daemon lifecycle ("started (pid …)", "desktop ownership lost, shutting down") |
| `~/.grokbot/local-exec-daemon-connection.json` | sealed blob (encrypted) |
| a local secrets file under Application Support | Grok Bot's own credentials — noted and left alone; not a signal Ground Control uses |
| `sand-session-marker.json` | `{ pid, appVersion, startedAtMs, crashSeen }` — app liveness |

**Automations** — Grok Bot has a scheduled-task layer (`automationId:
"ai-news-morning-brief"`). Not explored; a possible signal source of its own.

---

## The cloud RPC (dismissed)

`aiserver.v1.WatchGrokBotTranscripts` — a server-streaming gRPC method in
Cursor's private `aiserver.v1` namespace. Streams transcript entries from the
cloud, keyed by `agent_id` / `generation` / `after_updated_seq` cursors. Needs
the authenticated session; undocumented; no public schema; nothing online. It is
the cloud twin of the local roster/transcript cache — same data, harder to get.
Not worth reverse-engineering.

---

## Design sketch

**Not built.** For whenever it's wanted.

### Shape

- A grouped **Grok Bot** parent row (host `com.anysphere.sand`), one child per
  `roster.last-roster` row.
- Per child: **needs you** (any of the three signals) → alert. Otherwise →
  **unknown** — a designed neutral mood (name shown, neutral dot, calm/idle
  analyser), never a guessed "idle" or "done".
- Optionally **active** when the heartbeat moved in the last ~15 s.
- Click raises `Grok Bot.app` — no tty, an app not a terminal, same destination
  path as Cursor's Composer.
- Channels (`isGroup: true`) — a group inside the group, or flatten to members.

### Grouping is the real work

GC is flat today: one session, one row. A parent-with-children needs a group
model, persisted collapse state, a header rule (any child needs you → header
red), and a panel-height decision (group counts as 1 or N). Build it as
**grouped hosts** generically — Grok CLI channels and multi-session repos would
inherit it — but don't generalise past that until a second real case lands.

### Open decisions

1. **Whose alert.** Grok Bot fires its own OS notification for cards. GC's dot +
   panel and let Grok own the sound, or full GC alarm treatment?
2. **Analyser in the group.** Does the parent show the matrix, or just a count +
   worst-child status?
3. **Schema-drift guard.** The card alert rests on one undocumented field
   (`sessionPreview.kind`, schema already at v3). If xAI renames it the alert
   silently dies and every bot reads "unknown" forever. A roster file that
   parses but has an unexpected shape should surface "Grok Bot integration needs
   updating", per `LIMITATIONS.md` → "Silence is the failure mode here".

---

## How this was probed (to redo it)

1. `Scripts/probe-cursor-hooks.sh` → installs an observe-only hook for all 18
   events into `~/.cursor/hooks.json`; `--show` prints captures; `--uninstall`
   restores. **Result: never fired.**
2. A folder watcher on `sand-client-persistence/` printing every roster /
   transcript write with the decoded slice key and key fields. (bash 3.2 —
   no associative arrays.)
3. Run turns in a bot: a chat, an inline card (`"input prompt me again"`), a
   local command (`"run ls ~/Desktop on my machine"`), and a long research turn
   (`"search the web, multiple sources, cite them, comparison table, thorough"`).
4. Snapshot the roster blob *while a card is unanswered* — that is when
   `awaitingUserResponse` was proven to stay null.
