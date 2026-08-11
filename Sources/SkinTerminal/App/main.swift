// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak

import AppKit

// Entry point. `.accessory` is what makes this a menu-bar app with no Dock
// icon — the runtime equivalent of LSUIElement, and it works for `swift run`
// as well as a bundled .app (docs/SPEC.md §1).
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let delegate = AppDelegate()
application.delegate = delegate
application.run()
