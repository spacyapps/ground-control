// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// A corner decoration's list of images, played end to end and looping.
///
/// Each entry holds the timeline for its own natural length — a gif's whole
/// loop, a still for a fixed beat — so the hand-off from one to the next lands
/// where the artwork already repeats, not on a cut mid-frame. Built once per
/// theme; `sample(at:)` is a pure lookup against a clock the view keeps.
struct DecorationSequence {
    let images: [BackgroundImage]
    private let spans: [TimeInterval]
    private let total: TimeInterval

    /// `stillBeat` is how long a non-animated entry occupies the timeline.
    init(_ images: [BackgroundImage], stillBeat: TimeInterval) {
        self.images = images
        spans = images.map { image in
            guard let animated = AnimatedImage.load(image), animated.isAnimated else { return stillBeat }
            return animated.duration * Double(animated.frames.count)
        }
        total = spans.reduce(0, +)
    }

    /// The entry showing at `clock`, and how far into its own timeline — so a
    /// gif entry starts from frame zero each time its turn comes round.
    func sample(at clock: TimeInterval) -> (image: BackgroundImage, into: TimeInterval)? {
        guard let first = images.first else { return nil }
        guard images.count > 1, total > 0 else { return (first, clock) }

        var offset = clock.truncatingRemainder(dividingBy: total)
        for (index, span) in spans.enumerated() {
            if offset < span { return (images[index], offset) }
            offset -= span
        }
        return (first, 0)
    }
}
