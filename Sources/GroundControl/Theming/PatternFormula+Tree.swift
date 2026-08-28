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
                return function.apply(arguments.map { $0.evaluate(context) })
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

        func apply(_ args: [Double]) -> Double {
            switch self {
            case .sin:   return Foundation.sin(args[0])
            case .cos:   return Foundation.cos(args[0])
            case .abs:   return Swift.abs(args[0])
            case .floor: return args[0].rounded(.down)
            case .sqrt:  return args[0] < 0 ? 0 : args[0].squareRoot()
            case .exp:   return Foundation.exp(args[0])
            case .min:   return Swift.min(args[0], args[1])
            case .max:   return Swift.max(args[0], args[1])
            // step(t, x): 1 once x reaches t, else 0.
            case .step:  return args[1] >= args[0] ? 1 : 0
            // pulse(centre, width, x): a triangular bump, 1 at the centre, 0 at
            // ±width. Predictable — no tails to reason about.
            case .pulse:
                let distance = Swift.abs(args[2] - args[0])
                return args[1] <= 0 ? 0 : Swift.max(0, 1 - distance / args[1])
            // wrap(x): the fractional part, so a growing phase stays 0…1.
            case .wrap:  return args[0] - args[0].rounded(.down)
            }
        }
    }
}
