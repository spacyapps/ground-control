// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import QuartzCore

extension CALayer {
    /// Freezes or resumes every animation on this layer and its sublayers.
    ///
    /// Setting `speed` to 0 alone would jump the animation on resume, because
    /// layer time keeps running while it is frozen. The standard remedy: freeze
    /// at the current layer time, and on resume start again from where it stopped.
    func setPaused(_ paused: Bool) {
        if paused {
            guard speed != 0 else { return }
            let frozenAt = convertTime(CACurrentMediaTime(), from: nil)
            speed = 0
            timeOffset = frozenAt
        } else {
            guard speed == 0 else { return }
            let frozenAt = timeOffset
            speed = 1
            timeOffset = 0
            beginTime = 0
            beginTime = convertTime(CACurrentMediaTime(), from: nil) - frozenAt
        }
    }
}
