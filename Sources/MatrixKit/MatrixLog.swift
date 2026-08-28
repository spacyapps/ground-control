// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation
import os

/// MatrixKit's own logger. The app has `Log.theming`, but this target does not
/// depend on the app — a bad formula is a theme-author problem either way, and
/// it lands in the same subsystem so `log show` picks up both.
enum MatrixLog {
    static let log = Logger(subsystem: "com.spacyapps.groundcontrol", category: "matrix")
}
