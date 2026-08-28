// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Resolves the Tier-1 analyser knobs from named levels to concrete numbers.
///
/// The manifest speaks in words — `"fall": "slow"` — because that is what a
/// theme author, or the model writing the theme, can reason about; nobody knows
/// what `0.012` looks like. The numbers those words mean live here, in one
/// table, so the vocabulary and its meaning cannot drift apart.
///
/// Every key is independent and optional. An unknown word logs and keeps the
/// standard value. An absent `feel` is exactly today's analyser — the standard
/// values below are lifted straight from what `VisualizerView` was hardcoding.
///
/// See docs/MATRIX-CUSTOMISATION.md.
enum MatrixFeel {
    /// The tuned constants the visualiser runs on. Concrete, not named — the
    /// word→number step has already happened.
    struct Resolved: Equatable {
        var release: CGFloat               // slow-release lerp toward a falling target
        var peakFall: CGFloat              // peak-marker descent per tick
        var phaseStep: CGFloat             // phase-clock advance per tick
        var energyFloor: CGFloat           // amplitude with one session working
        var energyPerSession: CGFloat      // added per further working session
        var jitter: ClosedRange<CGFloat>?  // nil -> each pattern keeps its own
        var patternHold: ClosedRange<TimeInterval>
        var sleepFace: String
        var sleepZzz: Bool

        static let standard = Resolved(
            release: 0.12,
            peakFall: 0.012,
            phaseStep: 0.09,
            energyFloor: 0.45,
            energyPerSession: 0.20,
            jitter: nil,
            patternHold: 9...16,
            sleepFace: "-  ‿  -",
            sleepZzz: true
        )
    }

    static func resolve(_ matrix: ThemeManifest.Matrix?) -> Resolved {
        var out = Resolved.standard
        applyFall(matrix?.feel?.fall, to: &out)
        applySpeed(matrix?.feel?.speed, to: &out)
        applySensitivity(matrix?.feel?.sensitivity, to: &out)
        applyJitter(matrix?.feel?.jitter, to: &out)
        applyPatternHold(matrix?.patternHold, to: &out)
        if let face = matrix?.sleep?.face, !face.isEmpty { out.sleepFace = face }
        if let zzz = matrix?.sleep?.zzz { out.sleepZzz = zzz }
        return out
    }

    // fall -> how the bars settle: release lerp and peak descent move together,
    // since both are "how much does it hang".
    // still  -> snap, almost no ballistics       fast   -> quick, still analyser-like
    // slow   -> a long lazy descent              medium -> the shipped feel (unchanged)
    private static func applyFall(_ level: String?, to out: inout Resolved) {
        switch level?.lowercased() {
        case nil, "medium": break
        case "still":       out.release = 0.50; out.peakFall = 0.050
        case "slow":        out.release = 0.06; out.peakFall = 0.006
        case "fast":        out.release = 0.25; out.peakFall = 0.025
        case let other?:    warn("matrix.feel.fall", other)
        }
    }

    // speed -> phase-clock rate: how fast a wave travels across the row.
    private static func applySpeed(_ level: String?, to out: inout Resolved) {
        switch level?.lowercased() {
        case nil, "medium": break
        case "slow":        out.phaseStep = 0.05
        case "fast":        out.phaseStep = 0.16
        case let other?:    warn("matrix.feel.speed", other)
        }
    }

    // sensitivity -> working-count to amplitude.
    // mellow  -> needs a busy panel before the bars really move
    // steady  -> the shipped curve
    // twitchy -> one working session already looks busy
    private static func applySensitivity(_ level: String?, to out: inout Resolved) {
        switch level?.lowercased() {
        case nil, "steady": break
        case "mellow":      out.energyFloor = 0.35; out.energyPerSession = 0.12
        case "twitchy":     out.energyFloor = 0.60; out.energyPerSession = 0.28
        case let other?:    warn("matrix.feel.sensitivity", other)
        }
    }

    // jitter -> per-bar noise, an absolute range overriding each pattern's own.
    // Omitted keeps every pattern's built-in feel.
    // none -> perfectly clean            chaotic -> the old spectrum shimmer, everywhere
    private static func applyJitter(_ level: String?, to out: inout Resolved) {
        switch level?.lowercased() {
        case nil:        break
        case "none":     out.jitter = 1.0...1.0
        case "calm":     out.jitter = 0.90...1.0
        case "lively":   out.jitter = 0.75...1.0
        case "chaotic":  out.jitter = 0.45...1.0
        case let other?: warn("matrix.feel.jitter", other)
        }
    }

    // patternHold -> seconds a shape holds before the next.
    private static func applyPatternHold(_ level: String?, to out: inout Resolved) {
        switch level?.lowercased() {
        case nil, "medium": break
        case "short":       out.patternHold = 5...9
        case "long":        out.patternHold = 16...28
        case let other?:    warn("matrix.patternHold", other)
        }
    }

    private static func warn(_ key: String, _ value: String) {
        Log.theming.notice(
            "Theme \(key, privacy: .public): unknown value \(value, privacy: .public)"
        )
    }
}
