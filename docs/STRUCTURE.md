# Project Structure

GroundControl is a Swift Package Manager executable (AppKit, `LSUIElement`
menu-bar app). One responsibility per file; group by feature/layer, not by
"all views here, all models there" mega-folders. When a file passes ~400
lines, split it.

```
GroundControl/
├── Package.swift                 # SPM manifest — no dependencies; target + resources
├── .swiftlint.yml                # lint rules (root; nested configs allowed later)
├── .gitignore                    # excludes build/, DerivedData/, secrets, xcuserdata
├── README.md                     # landing page: what it is, build, screenshots
├── LICENSE                       # AGPL-3.0-or-later
│
├── Sources/GroundControl/
│   ├── App/                      # lifecycle & wiring
│   │   ├── main.swift            # entry point, sets .accessory activation policy
│   │   ├── AppDelegate.swift     # NSApplicationDelegate, boots the coordinator
│   │   └── AppCoordinator.swift  # owns/connects the subsystems (composition root)
│   │
│   ├── Models/                   # plain value types, no AppKit imports
│   │   ├── SessionEvent.swift    # decoded line from <session_id>.jsonl
│   │   ├── AgentEvent.swift      # decoded line from agents/<id>.jsonl
│   │   ├── Session.swift         # a live session (latest event + children[])
│   │   ├── SessionState.swift    # enum: idle / working / needsInput / done
│   │   ├── ElapsedFormatter.swift # "3m" / "2h"; also decides when idle is stale
│   │   └── ThemeManifest.swift   # decoded theme.json — all-optional, pure data
│   │
│   ├── Monitoring/               # the file<->row engine
│   │   ├── SessionStore.swift    # source of truth: [Session], publishes changes
│   │   ├── FolderWatcher.swift   # DispatchSource on a directory, debounced
│   │   ├── SessionFileParser.swift # last decodable line of a .jsonl file
│   │   ├── AgentGrouper.swift    # agents/*.jsonl -> children, keyed by session
│   │   └── PurgeService.swift    # deletes files untouched > window (timer)
│   │
│   ├── Theming/                  # skin engine (may import AppKit; no UI)
│   │   ├── Theme.swift           # resolved theme the UI reads — no optionals
│   │   ├── DefaultTheme.swift    # code-side fallbacks for every key
│   │   ├── ThemeLoader.swift     # find themes, decode manifest, apply fallbacks
│   │   ├── ThemeStore.swift      # active theme + hot-reload watcher
│   │   ├── AssetResolver.swift   # manifest -> resolved avatar/background URLs
│   │   ├── DrawnAvatar.swift     # built-in per-state faces (SF Symbols)
│   │   ├── BackgroundImage.swift # resolved background + nine-slice cap insets
│   │   ├── BackgroundRenderer.swift # draws a background into any size box
│   │   ├── AnimatedImage.swift   # multi-frame GIF/APNG decoding
│   │   ├── ImageKeyer.swift      # chroma key / checkerboard -> real alpha, de-spilled
│   │   ├── SkinCheck.swift       # would this overlay skin hide the panel?
│   │   ├── Brand.swift           # the app's own mark and website link
│   │   ├── ThemeBrief.swift      # answers gathered by the theme builder
│   │   ├── ThemePromptBuilder.swift # brief -> LLM prompt + starter manifest
│   │   ├── ThemePromptText.swift # the prompt's fixed prose
│   │   └── ThemeScaffold.swift   # creates a theme folder ready for artwork
│   │
│   ├── UI/
│   │   ├── Panel/
│   │   │   ├── FloatingPanel.swift        # NSPanel: nonactivating, levels, spaces
│   │   │   ├── PanelController.swift      # show/hide, position persistence
│   │   │   ├── PanelBackgroundView.swift  # themed surface: title bar + list
│   │   │   ├── TitleBarView.swift         # themed strip, drag handle, analyser
│   │   │   ├── CornerMarkView.swift       # what the two corner marks share
│   │   │   ├── CloseMarkView.swift        # the ✕ — above any skin (see below)
│   │   │   ├── ResizeGripView.swift       # the ↔ — the only resize on a shaped panel
│   │   │   ├── HintView.swift             # the panel's own tooltip; AppKit's never show
│   │   │   ├── SkinOverlayView.swift      # window.overlay: the skin drawn in front
│   │   │   ├── SkinInterior.swift         # what a frame encloses vs what is outside it
│   │   │   ├── VisualizerView.swift       # WinAmp-style analyser, driven by state
│   │   │   ├── VisualizerPattern.swift    # the shapes it sweeps through
│   │   │   ├── MatrixFont.swift           # 5-row letterforms for the analyser
│   │   │   ├── MatrixMessages.swift       # what it spells, theme words included
│   │   │   └── SessionListView.swift      # the scrolling stack of rows
│   │   ├── Rows/
│   │   │   ├── SessionRowView.swift       # one row: dot + name + message + avatar
│   │   │   ├── GroupRowView.swift         # one subagent child row
│   │   │   ├── MarqueeLabel.swift         # auto-scroll on overflow only
│   │   │   ├── StatusDotView.swift        # drawn dot or themed badge
│   │   │   └── AvatarView.swift           # image / animated GIF / looping video
│   │   ├── MenuBar/
│   │   │   ├── StatusItemController.swift # NSStatusItem, badge on needs-action
│   │   │   └── StatusMenu.swift           # right-click menu
│   │   └── Settings/
│   │       ├── SettingsWindowController.swift
│   │       ├── SettingsView.swift             # theme picker, toggles, advanced
│   │       ├── StarfieldView.swift            # the settings chrome, drawn not shipped
│   │       ├── ThemePreviewView.swift         # live sample: artwork + all four faces
│   │       └── ThemeBuilderWindowController.swift # questions -> LLM prompt
│   │
│   ├── Integration/              # talking to the outside world
│   │   └── TerminalFocuser.swift # AppleScript jump-to-tab (iTerm + Terminal)
│   │
│   ├── Services/                 # cross-cutting helpers
│   │   ├── Preferences.swift     # UserDefaults wrapper
│   │   ├── Paths.swift           # canonical folder locations
│   │   └── Log.swift             # os.Logger wrapper
│   │
│   ├── Extensions/               # small, focused extensions
│   │   └── NSColor+Hex.swift
│   │
│   └── Resources/                # the app's own mark (themes draw their own —
│       ├── logo-glyph.png        # see DrawnAvatar for the built-in faces)
│       └── logo-lockup.png       # Themes/ is copied in by build-app.sh too
│
├── Themes/
│   ├── default/theme.json        # reference palette (ships in-repo, copyable)
│   ├── example-avatars/          # working avatar theme: 3 stills + a GIF
│   └── spacyAppsLunarAvatar/     # the full set: avatars + shaped skin
│
├── ExtraThemes/                 # demo weight, bundled only with EXTRA_THEMES=1
│   └── spacyAppsUnicornOverlord/ # a frame drawn in front of the rows
│
├── Scripts/                     # cc-notify and install-hooks.sh are also copied
│   │                             # into the .app, so a dmg needs no checkout
│   ├── cc-notify                 # hook emitter (python3, reads Claude + Grok)
│   ├── cc-notify.zip             # the emitter alone, for a machine without the repo
│   ├── install-hooks.sh          # MERGES hook entries into ~/.claude/settings.json
│   ├── theme-preview.sh          # one fake row per state, for theming
│   ├── make-icon.sh              # logo -> AppIcon.icns
│   ├── build-app.sh              # assembles + signs GroundControl.app
│   └── build-dmg.sh              # dmg: signed, notarised, stapled
│
├── Tests/GroundControlTests/     # unit tests mirror the source tree; the
│                                 # theming ones render offscreen and inspect
│                                 # pixels, because "tested but never seen" has
│                                 # been wrong here more than once
│
├── docs/
│   ├── STRUCTURE.md              # this file
│   ├── ARCHITECTURE.md           # how a hook event becomes a row (start here)
│   ├── SPEC.md                   # the full build brief
│   ├── THEMING.md                # theme authoring guide
│   ├── THEME-DELIVERY.md         # proposal: shipping themes outside the app
│   ├── HOOK-PAYLOADS.md          # measured hook payloads — the data SPEC rests on
│   └── LIMITATIONS.md            # what is verified vs assumed; other-CLI status
│
├── Packaging/
│   ├── Info.plist                # bundle id, version, LSUIElement
│   ├── GroundControl.entitlements # hardened runtime + apple-events
│   └── AppIcon.icns
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

## What a theme may not paint over

Panel views stack in one deliberate order: **marks, then skin, then panel.**
`CloseMarkView` and `ResizeGripView` are added after `SkinOverlayView`, so a
theme can cover its own rows — that is what `window.overlay` is for — but never
the only ways to close and resize the window. A theme that tucked its content
behind its frame used to take both controls with it.

The same instinct runs through `SkinCheck` and `Theme.warnings`: an overlay skin
whose middle would hide the panel is demoted to a background and *says so* in
Settings, and a manifest that will not parse says that too rather than quietly
showing the built-in theme.
