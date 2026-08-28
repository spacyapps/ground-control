// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// A theme-supplied bar-height formula: parsed once, evaluated per bar per frame.
///
/// **Pure math only.** No assignment, no loops, no branching beyond the `step`,
/// `min` and `max` functions. That is the whole safety story — a stranger's
/// formula can compute a number and do nothing else, so running it 24 times a
/// second is fine. There is no sandbox to escape because there is nothing here
/// but arithmetic.
///
/// A parse error is the theme author's to see, not the panel's to crash on:
/// `parse` returns nil and logs, and the caller falls back to the built-in
/// patterns (docs/MATRIX-CUSTOMISATION.md).
///
/// Vocabulary:
/// - variables `pos` (0…1 across the row), `phase` (monotonic time), `energy`
///   (0…1 now), `bar` (index), `count` (total bars)
/// - functions `sin cos abs min max floor pow sqrt exp`, `step(t, x)`,
///   `pulse(centre, width, x)`, `wrap(x)`
/// - the eight built-in shapes, callable by name — `wave(pos)`, `ripple(pos)` …
///   — each evaluated at the current phase
public struct PatternFormula: Equatable {
    public let source: String
    private let root: Node

    public static func == (lhs: PatternFormula, rhs: PatternFormula) -> Bool {
        lhs.source == rhs.source
    }

    /// Everything an expression can read while it runs.
    public struct Context {
        public var pos: Double
        public var phase: Double
        public var energy: Double
        public var bar: Double
        public var count: Double
        /// Seconds since the finish edge, for `decay()` in a done formula. Zero
        /// everywhere else, where `decay()` is a parse error anyway.
        public var decayElapsed: Double

        public init(
            pos: Double,
            phase: Double,
            energy: Double,
            bar: Double,
            count: Double,
            decayElapsed: Double = 0
        ) {
            self.pos = pos
            self.phase = phase
            self.energy = energy
            self.bar = bar
            self.count = count
            self.decayElapsed = decayElapsed
        }
    }

    /// Parses, or logs and returns nil. `key` names the manifest field for the
    /// log line ("matrix.shape.working"). `allowsDecay` is set only for the
    /// done state — `decay()` is meaningless anywhere else.
    public static func parse(
        _ source: String,
        key: String = "matrix.shape",
        allowsDecay: Bool = false
    ) -> PatternFormula? {
        do {
            var parser = Parser(source, allowsDecay: allowsDecay)
            let root = try parser.parseExpression()
            try parser.expectEnd()
            return PatternFormula(source: source, root: root)
        } catch {
            MatrixLog.log.notice(
                "Theme \(key, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    public func value(_ context: Context) -> Double {
        root.evaluate(context)
    }

    /// The per-frame constants captured once, so the render loop pays for them
    /// per frame rather than per bar. `height(pos:bar:)` is then the only thing
    /// that runs 60-odd times a tick, and it returns a clamped 0…1.
    public struct Sampler {
        fileprivate let formula: PatternFormula
        fileprivate let phase: Double
        fileprivate let energy: Double
        fileprivate let count: Double
        fileprivate let decayElapsed: Double

        public func height(pos: Double, bar: Int) -> CGFloat {
            let value = formula.value(Context(
                pos: pos,
                phase: phase,
                energy: energy,
                bar: Double(bar),
                count: count,
                decayElapsed: decayElapsed
            ))
            return CGFloat(Swift.max(0, Swift.min(1, value)))
        }
    }

    public func sampler(
        phase: CGFloat, energy: CGFloat, count: Int, decayElapsed: TimeInterval = 0
    ) -> Sampler {
        Sampler(
            formula: self,
            phase: Double(phase),
            energy: Double(energy),
            count: Double(count),
            decayElapsed: decayElapsed
        )
    }
}
