// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// The parsed expression and how it evaluates. Split from the public surface so
/// each file stays small; `internal` rather than `private` only for that.
extension PatternFormula {
    indirect enum Node {
        case number(Double)
        case variable(Variable)
        case unary(Double, Node)                    // scale (−1 for negation)
        case binary(Operator, Node, Node)
        case function(Function, [Node])
        case pattern(VisualizerPattern, Node)       // built-in shape at an x
        case decay(Node)                            // 1 at the finish edge -> 0 over `span`

        func evaluate(_ context: PatternFormula.Context) -> Double {
            switch self {
            case .number(let value):
                return value
            case .variable(let variable):
                return variable.read(context)
            case .unary(let scale, let operand):
                return scale * operand.evaluate(context)
            case .binary(let op, let lhs, let rhs):
                return op.apply(lhs.evaluate(context), rhs.evaluate(context))
            case .function(let function, let arguments):
                return function.apply(arguments, context)
            case .pattern(let pattern, let argument):
                let x = CGFloat(argument.evaluate(context))
                return Double(pattern.shape(position: x, phase: CGFloat(context.phase)))
            case .decay(let spanNode):
                let span = spanNode.evaluate(context)
                guard span > 0 else { return 0 }
                return Swift.max(0, 1 - context.decayElapsed / span)
            }
        }
    }

    enum Variable {
        case pos, phase, energy, bar, count

        static let all: [String: Variable] = [
            "pos": .pos, "phase": .phase, "energy": .energy, "bar": .bar, "count": .count
        ]

        func read(_ context: PatternFormula.Context) -> Double {
            switch self {
            case .pos:    return context.pos
            case .phase:  return context.phase
            case .energy: return context.energy
            case .bar:    return context.bar
            case .count:  return context.count
            }
        }
    }

    enum Operator {
        case add, subtract, multiply, divide, power

        func apply(_ lhs: Double, _ rhs: Double) -> Double {
            switch self {
            case .add:      return lhs + rhs
            case .subtract: return lhs - rhs
            case .multiply: return lhs * rhs
            // Divide-by-zero is 0, not a NaN that poisons the whole row for the
            // rest of the session.
            case .divide:   return rhs == 0 ? 0 : lhs / rhs
            case .power:    return pow(lhs, rhs)
            }
        }
    }

    /// The whitelisted functions. Anything not here is a parse error — that is
    /// the point, not a limitation to apologise for.
    enum Function {
        case sin, cos, abs, floor, sqrt, exp
        case min, max
        case step, pulse, wrap

        static let all: [String: Function] = [
            "sin": .sin, "cos": .cos, "abs": .abs, "floor": .floor,
            "sqrt": .sqrt, "exp": .exp, "min": .min, "max": .max,
            "step": .step, "pulse": .pulse, "wrap": .wrap
        ]

        var arity: ClosedRange<Int> {
            switch self {
            case .min, .max, .step: return 2...2
            case .pulse:            return 3...3
            default:                return 1...1
            }
        }

        /// Takes the argument `Node`s, not evaluated `Double`s, and pulls out
        /// only the ones it needs. The parser already checked the count, so the
        /// indices are safe — and there is no per-call `[Double]` allocated in
        /// the render loop, which `arguments.map { … }` used to do.
        func apply(_ args: [Node], _ context: PatternFormula.Context) -> Double {
            let first = args[0].evaluate(context)
            switch self {
            case .sin:   return Foundation.sin(first)
            case .cos:   return Foundation.cos(first)
            case .abs:   return Swift.abs(first)
            case .floor: return first.rounded(.down)
            case .sqrt:  return first < 0 ? 0 : first.squareRoot()
            case .exp:   return Foundation.exp(first)
            // wrap(x): the fractional part, so a growing phase stays 0…1.
            case .wrap:  return first - first.rounded(.down)
            case .min:   return Swift.min(first, args[1].evaluate(context))
            case .max:   return Swift.max(first, args[1].evaluate(context))
            // step(t, x): 1 once x reaches t, else 0.
            case .step:  return args[1].evaluate(context) >= first ? 1 : 0
            // pulse(centre, width, x): a triangular bump, 1 at the centre, 0 at
            // ±width. Predictable — no tails to reason about.
            case .pulse:
                let width = args[1].evaluate(context)
                let distance = Swift.abs(args[2].evaluate(context) - first)
                return width <= 0 ? 0 : Swift.max(0, 1 - distance / width)
            }
        }
    }
}
