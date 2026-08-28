// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation

/// Turning formula text into a `Node` tree. Hand-written recursive descent —
/// small enough to read, and it keeps the vocabulary a hard whitelist.
extension PatternFormula {
    enum ParseError: Error {
        case empty
        case unexpected(String)
        case unknownName(String)
        case wrongArgumentCount(String)
        case decayNotAllowed
        case trailing(String)
        case tooDeep
    }

    /// Precedence, low to high:
    /// `+ -`  →  `* /`  →  unary `-`  →  `^` (right-assoc)  →  primary.
    ///
    /// Unary binds looser than `^` so `-2^2` is `-(2^2)`, the school reading;
    /// the exponent itself is a unary, so `2^-3` still parses.
    struct Parser {
        private let tokens: [Token]
        private let allowsDecay: Bool
        private var index = 0
        private var depth = 0

        init(_ source: String, allowsDecay: Bool = false) {
            tokens = Lexer.tokens(source)
            self.allowsDecay = allowsDecay
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

            if name == "decay" {
                guard allowsDecay else { throw ParseError.decayNotAllowed }
                guard arguments.count == 1 else { throw ParseError.wrongArgumentCount(name) }
                return .decay(arguments[0])
            }
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

    enum Token: Equatable {
        case number(Double)
        case name(String)
        case symbol(String)
    }

    enum Lexer {
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
