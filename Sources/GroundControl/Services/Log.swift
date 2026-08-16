// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation
import os

/// Thin `os.Logger` wrapper so call sites stay short and subsystem-consistent.
enum Log {
    private static let subsystem = "app.groundcontrol"

    static let monitoring = Logger(subsystem: subsystem, category: "monitoring")
    static let theming = Logger(subsystem: subsystem, category: "theming")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let integration = Logger(subsystem: subsystem, category: "integration")
}
