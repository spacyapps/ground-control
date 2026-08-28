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
struct PatternFormula: Equatable {
    let source: String
    private let root: Node

    static func == (lhs: PatternFormula, rhs: PatternFormula) -> Bool {
        lhs.source == rhs.source
    }

    /// Everything an expression can read while it runs.
    struct Context {
        var pos: Double
        var phase: Double
        var energy: Double
        var bar: Double
        var count: Double
    }

    /// Parses, or logs and returns nil. `key` names the manifest field for the
    /// log line ("matrix.shape.working").
    static func parse(_ source: String, key: String = "matrix.shape") -> PatternFormula? {
        do {
            var parser = Parser(source)
            let root = try parser.parseExpression()
            try parser.expectEnd()
            return PatternFormula(source: source, root: root)
        } catch {
            Log.theming.notice(
                "Theme \(key, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    func value(_ context: Context) -> Double {
        root.evaluate(context)
    }

    /// The per-frame constants captured once, so the render loop pays for them
    /// per frame rather than per bar. `height(pos:bar:)` is then the only thing
    /// that runs 60-odd times a tick, and it returns a clamped 0…1.
    struct Sampler {
        fileprivate let formula: PatternFormula
        fileprivate let phase: Double
        fileprivate let energy: Double
        fileprivate let count: Double

        func height(pos: Double, bar: Int) -> CGFloat {
            let value = formula.value(Context(
                pos: pos, phase: phase, energy: energy, bar: Double(bar), count: count
            ))
            return CGFloat(Swift.max(0, Swift.min(1, value)))
        }
    }

    func sampler(phase: CGFloat, energy: CGFloat, count: Int) -> Sampler {
        Sampler(formula: self, phase: Double(phase), energy: Double(energy), count: Double(count))
    }

    // MARK: - Tree

    fileprivate indirect enum Node {
        case number(Double)
        case variable(Variable)
        case unary(Double, Node)                    // scale (−1 for negation)
        case binary(Operator, Node, Node)
        case function(Function, [Node])
        case pattern(VisualizerPattern, Node)       // built-in shape at an x

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
            }
        }
    }

    fileprivate enum Variable {
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

    fileprivate enum Operator {
        case add, subtract, multiply, divide, power

        func apply(_ lhs: Double, _ rhs: Double) -> Double {
            switch self {
            case .add:      return lhs + rhs
            case .subtract: return lhs - rhs
            case .multiply: return lhs * rhs
            // A formula that divides by zero gets 0, not a NaN that poisons the
            // whole row for the rest of the session.
            case .divide:   return rhs == 0 ? 0 : lhs / rhs
            case .power:    return pow(lhs, rhs)
            }
        }
    }

    /// The whitelisted functions. Anything not here is a parse error — that is
    /// the point, not a limitation to apologise for.
    fileprivate enum Function {
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
            case .min, .max:    return 2...2
            case .step:         return 2...2
            case .pulse:        return 3...3
            default:            return 1...1
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
            // pulse(centre, width, x): a triangular bump, 1 at the centre,
            // 0 at ±width. Predictable — no tails to reason about.
            case .pulse:
                let distance = Swift.abs(args[2] - args[0])
                return args[1] <= 0 ? 0 : Swift.max(0, 1 - distance / args[1])
            // wrap(x): the fractional part, so a growing phase stays 0…1.
            case .wrap:  return args[0] - args[0].rounded(.down)
            }
        }
    }

    // MARK: - Parser

    enum ParseError: Error {
        case empty
        case unexpected(String)
        case unknownName(String)
        case wrongArgumentCount(String)
        case trailing(String)
        case tooDeep
    }

    /// Hand-written recursive descent. Precedence, low to high:
    /// `+ -`  →  `* /`  →  unary `-`  →  `^` (right-assoc)  →  primary.
    ///
    /// Unary binds looser than `^` so `-2^2` is `-(2^2)`, the school reading;
    /// the exponent itself is a unary, so `2^-3` still parses.
    fileprivate struct Parser {
        private let tokens: [Token]
        private var index = 0
        private var depth = 0

        init(_ source: String) {
            tokens = Lexer.tokens(source)
        }

        mutating func parseExpression() throws -> Node {
            guard !tokens.isEmpty else { throw ParseError.empty }
            return try parseAdditive()
        }

        mutating func expectEnd() throws {
            if index != tokens.count {
                throw ParseError.trailing(describe(peek))
            }
        }

        private mutating func parseAdditive() throws -> Node {
            var node = try parseMultiplicative()
            while let op = matchOperator(["+", "-"]) {
                let rhs = try parseMultiplicative()
                node = .binary(op == "+" ? .add : .subtract, node, rhs)
            }
            return node
        }

        private mutating func parseMultiplicative() throws -> Node {
            var node = try parseUnary()
            while let op = matchOperator(["*", "/"]) {
                let rhs = try parseUnary()
                node = .binary(op == "*" ? .multiply : .divide, node, rhs)
            }
            return node
        }

        private mutating func parseUnary() throws -> Node {
            if matchOperator(["-"]) != nil {
                return .unary(-1, try parseUnary())
            }
            if matchOperator(["+"]) != nil {
                return try parseUnary()
            }
            return try parsePower()
        }

        private mutating func parsePower() throws -> Node {
            let base = try parsePrimary()
            guard matchOperator(["^"]) != nil else { return base }
            let exponent = try parseUnary()   // right-assoc, and `2^-3` parses
            return .binary(.power, base, exponent)
        }

        private mutating func parsePrimary() throws -> Node {
            depth += 1
            defer { depth -= 1 }
            guard depth < 64 else { throw ParseError.tooDeep }

            guard let token = peek else { throw ParseError.unexpected("end of formula") }

            switch token {
            case .number(let value):
                advance()
                return .number(value)

            case .symbol("("):
                advance()
                let inner = try parseAdditive()
                try consumeSymbol(")")
                return inner

            case .name(let name):
                advance()
                if peek == .symbol("(") {
                    return try parseCall(named: name)
                }
                guard let variable = Variable.all[name] else {
                    throw ParseError.unknownName(name)
                }
                return .variable(variable)

            default:
                throw ParseError.unexpected(describe(token))
            }
        }

        private mutating func parseCall(named name: String) throws -> Node {
            try consumeSymbol("(")
            var arguments: [Node] = []
            if peek != .symbol(")") {
                repeat {
                    arguments.append(try parseAdditive())
                } while matchSymbol(",")
            }
            try consumeSymbol(")")

            if let function = Function.all[name] {
                guard function.arity.contains(arguments.count) else {
                    throw ParseError.wrongArgumentCount(name)
                }
                return .function(function, arguments)
            }
            if let pattern = VisualizerPattern(rawValue: name) {
                guard arguments.count == 1 else { throw ParseError.wrongArgumentCount(name) }
                return .pattern(pattern, arguments[0])
            }
            throw ParseError.unknownName(name)
        }

        // MARK: token helpers

        private var peek: Token? { index < tokens.count ? tokens[index] : nil }
        private mutating func advance() { index += 1 }

        private mutating func matchOperator(_ options: Set<String>) -> String? {
            if case .symbol(let value)? = peek, options.contains(value) {
                advance()
                return value
            }
            return nil
        }

        private mutating func matchSymbol(_ value: String) -> Bool {
            if peek == .symbol(value) { advance(); return true }
            return false
        }

        private mutating func consumeSymbol(_ value: String) throws {
            guard matchSymbol(value) else {
                throw ParseError.unexpected("expected '\(value)', found \(describe(peek))")
            }
        }

        private func describe(_ token: Token?) -> String {
            switch token {
            case .none:                return "end of formula"
            case .number(let value)?:  return "\(value)"
            case .name(let name)?:     return "'\(name)'"
            case .symbol(let value)?:  return "'\(value)'"
            }
        }
    }

    fileprivate enum Token: Equatable {
        case number(Double)
        case name(String)
        case symbol(String)
    }

    fileprivate enum Lexer {
        static func tokens(_ source: String) -> [Token] {
            var tokens: [Token] = []
            let characters = Array(source)
            var cursor = 0
            while cursor < characters.count {
                let character = characters[cursor]
                if character.isWhitespace {
                    cursor += 1
                } else if character.isNumber || character == "." {
                    var text = ""
                    while cursor < characters.count,
                          characters[cursor].isNumber || characters[cursor] == "." {
                        text.append(characters[cursor]); cursor += 1
                    }
                    tokens.append(.number(Double(text) ?? .nan))
                } else if character.isLetter || character == "_" {
                    var text = ""
                    while cursor < characters.count,
                          characters[cursor].isLetter || characters[cursor].isNumber
                          || characters[cursor] == "_" {
                        text.append(characters[cursor]); cursor += 1
                    }
                    tokens.append(.name(text.lowercased()))
                } else {
                    tokens.append(.symbol(String(character)))
                    cursor += 1
                }
            }
            return tokens
        }
    }
}
