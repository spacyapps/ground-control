# Project Structure

SkinTerminal is a Swift Package Manager executable (AppKit, `LSUIElement`
menu-bar app). One responsibility per file; group by feature/layer, not by
"all views here, all models there" mega-folders. When a file passes ~400
lines, split it.

```
SkinTerminal/
├── Package.swift                 # SPM manifest — deps, executable target, resources
├── .swiftlint.yml                # lint rules (root; nested configs allowed later)
├── .gitignore                    # excludes build/, DerivedData/, secrets, xcuserdata
├── README.md                     # landing page: what it is, build, screenshots
├── LICENSE                       # MIT
│
├── Sources/SkinTerminal/
│   ├── App/                      # lifecycle & wiring
│   │   ├── main.swift            # entry point, sets .accessory activation policy
│   │   ├── AppDelegate.swift     # NSApplicationDelegate, boots the coordinator
│   │   └── AppCoordinator.swift  # owns/connects the subsystems (composition root)
│   │
│   ├── Models/                   # plain value types, no UIKit/AppKit imports
│   │   ├── SessionEvent.swift    # decoded line from a .jsonl file (see SPEC §3)
│   │   ├── Session.swift         # a live session (latest event + children[])
│   │   ├── AgentEvent.swift      # decoded line from agents/<id>.jsonl
│   │   ├── SessionState.swift    # enum: idle / working / needsInput / done
│   │   └── Theme.swift           # decoded theme.json (colors, assets, avatar, layout)
│   │
│   ├── Monitoring/               # the file<->row engine
│   │   ├── SessionStore.swift    # source of truth: [Session], publishes changes
│   │   ├── FolderWatcher.swift   # DispatchSource/FSEvents on the sessions folder
│   │   ├── SessionFileParser.swift # reads a .jsonl file -> SessionEvent(s)
│   │   ├── AgentGrouper.swift    # agents/*.jsonl -> children, keyed by session_id
│   │   └── PurgeService.swift    # deletes files untouched > window (timer)
│   │
│   ├── Theming/                  # skin engine
│   │   ├── ThemeLoader.swift     # find themes, decode manifest, apply fallbacks
│   │   ├── ThemeStore.swift      # active theme + hot-reload watcher
│   │   ├── AssetResolver.swift   # state -> image/video/drawn-default
│   │   └── DefaultTheme.swift    # code-side fallbacks for every key
│   │
│   ├── UI/
│   │   ├── Panel/
│   │   │   ├── FloatingPanel.swift        # NSPanel: nonactivating, levels, spaces
│   │   │   ├── PanelController.swift       # show/hide, position persistence
│   │   │   └── PanelBackgroundView.swift   # themed background (color or image)
│   │   ├── Rows/
│   │   │   ├── SessionRowView.swift        # one row: name + message + dot + avatar
│   │   │   ├── GroupRowView.swift          # orchestrator + collapsible children
│   │   │   ├── MarqueeLabel.swift          # auto-scroll on overflow
│   │   │   ├── StatusDotView.swift         # red dot / themed image
│   │   │   └── AvatarView.swift            # image or looping video per state
│   │   ├── MenuBar/
│   │   │   ├── StatusItemController.swift  # NSStatusItem, badge on needs-action
│   │   │   └── StatusMenu.swift            # right-click / dropdown menu
│   │   └── Settings/
│   │       ├── SettingsWindowController.swift
│   │       └── SettingsView.swift          # theme picker, float toggles
│   │
│   ├── Integration/              # talking to the outside world
│   │   ├── TerminalFocuser.swift # AppleScript jump-to-tab (iTerm + Terminal)
│   │   └── HookInstaller.swift   # optional: write cc-notify + settings.json
│   │
│   ├── Services/                 # cross-cutting helpers
│   │   ├── Preferences.swift     # UserDefaults wrapper (renames, panel frame, toggles)
│   │   ├── Paths.swift           # canonical folder locations (sessions dir, themes)
│   │   └── Logger.swift          # os.Logger wrapper
│   │
│   ├── Extensions/               # small, focused extensions (one type per file)
│   │   ├── NSColor+Hex.swift
│   │   └── URL+Sessions.swift
│   │
│   └── Resources/                # bundled assets (default avatar, icon)
│       └── (built-in default avatar images, menu-bar icon)
│
├── Themes/
│   └── default/theme.json        # reference theme (ships in-repo, copyable)
│
├── Scripts/
│   ├── cc-notify                 # the hook emitter (python3; reads payload on stdin)
│   ├── install-hooks.sh          # MERGES hook entries into ~/.claude/settings.json
│   └── build-dmg.sh              # create-dmg packaging  [not written yet]
│
├── Tests/SkinTerminalTests/      # unit tests mirror the source tree
│   ├── SessionFileParserTests.swift
│   ├── ThemeLoaderTests.swift
│   └── PurgeServiceTests.swift
│
├── docs/
│   ├── STRUCTURE.md              # this file
│   ├── THEMING.md                # theme authoring guide
│   ├── HOOK-PAYLOADS.md          # measured hook payloads — the data SPEC rests on
│   └── SPEC.md                   # the full build brief
│
└── .github/workflows/
    └── ci.yml                    # build + swiftlint on push/PR
```

## Layering rules (keep dependencies pointing one way)

```
UI ─┐
    ├─► Monitoring ─► Models
Integration ─┘        ▲
Theming ─────────────┘
Services ◄─ everyone (leaf utilities, depend on nothing app-specific)
```

- **Models** import nothing app-specific (no AppKit). Pure, testable.
- **Monitoring / Theming** depend on Models + Services only. No UI imports.
- **UI** depends on everything below it, never the reverse.
- **App/** is the only place that wires concrete instances together
  (composition root); nothing else news-up its own dependencies.

This is what keeps files modular and the graph testable — Monitoring and
Theming can be unit-tested with no window on screen.

## The app reads; it does not probe

Everything environment-shaped is resolved by `Scripts/cc-notify` and written
into the `.jsonl` line: the session id, the display name, and the tty. The app
never shells out to discover a terminal, never parses Claude's transcripts, and
never reads `~/.claude/`. Its whole input is one folder of JSON lines.

That boundary is what keeps `Monitoring` unit-testable from fixture files, and
it means a Claude Code update can only ever break the *script* — one file, no
Swift changes. See `docs/HOOK-PAYLOADS.md` for what the script relies on.
