import Foundation

/// The shapes the analyser can run.
///
/// Random noise reads as static: your eye sees "something is happening" and
/// nothing more. A recognisable pattern is legible — you notice it change, and
/// changing patterns give the panel a personality without pretending to convey
/// data it does not have.
///
/// Each case is a pure function of position and time returning 0…1, so the
/// shapes are testable and the view only has to scale them by energy.
enum VisualizerPattern: CaseIterable {
    /// One sine travelling left to right.
    case wave
    /// Rings spreading out from the middle.
    case ripple
    /// A bright band running along the row.
    case chase
    /// Tall in the middle, breathing in and out.
    case pyramid
    /// Ramps that climb and drop, marching sideways.
    case sawtooth
    /// Mirrored halves, opening and closing.
    case butterfly
    /// Mostly flat, with a pulse that crosses now and then.
    case heartbeat
    /// The classic jittery spectrum, kept because sometimes it suits.
    case spectrum

    /// Height for one bar, 0…1. `position` is 0…1 across the row.
    func shape(position: CGFloat, phase: CGFloat) -> CGFloat {
        let value: CGFloat
        switch self {
        case .wave:
            value = 0.5 + 0.5 * sin(position * 6.5 - phase * 2)

        case .ripple:
            let distance = abs(position - 0.5) * 2
            value = 0.5 + 0.5 * sin(distance * 9 - phase * 3)

        case .chase:
            let head = (phase * 0.28).truncatingRemainder(dividingBy: 1)
            var gap = abs(position - head)
            gap = min(gap, 1 - gap)          // wrap, so it never stutters at the edge
            value = exp(-(gap * gap) / 0.012)

        case .pyramid:
            let peak = 1 - abs(position - 0.5) * 2
            value = peak * (0.55 + 0.45 * sin(phase * 1.6))

        case .sawtooth:
            let ramp = (position * 3 - phase * 0.5).truncatingRemainder(dividingBy: 1)
            value = ramp < 0 ? ramp + 1 : ramp

        case .butterfly:
            let mirrored = abs(position - 0.5) * 2
            value = 0.5 + 0.5 * sin(mirrored * 7 + phase * 2)

        case .heartbeat:
            let beat = (phase * 0.5).truncatingRemainder(dividingBy: 1)
            let pulse = exp(-(pow(beat - position * 0.35, 2)) / 0.004)
            value = 0.12 + 0.88 * pulse

        case .spectrum:
            let slow = sin(position * 7 + phase)
            let fast = sin(position * 17 - phase * 1.7)
            value = 0.55 + 0.30 * slow + 0.15 * fast
        }
        return min(1, max(0, value))
    }

    /// How much per-bar jitter suits this shape. Deliberate patterns want to
    /// stay clean; the spectrum wants noise.
    var jitter: ClosedRange<CGFloat> {
        switch self {
        case .spectrum: return 0.45...1.0
        case .chase, .heartbeat: return 0.92...1.0
        default: return 0.80...1.0
        }
    }

    /// Seconds before switching. Long enough to read the shape, short enough
    /// that the panel never looks stuck.
    static func nextDuration() -> TimeInterval { .random(in: 9...16) }

    static func next(avoiding previous: VisualizerPattern) -> VisualizerPattern {
        allCases.filter { $0 != previous }.randomElement() ?? .wave
    }
}
