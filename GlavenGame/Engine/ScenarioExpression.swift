import Foundation

/// A small, safe, pure-Swift evaluator for the expression language used in
/// Gloomhaven Secretariat scenario data: rule `round` conditions (`"R % 2 == 0 || C > 2"`),
/// spawn counts (`"F"`), figure-rule values (`"(2xC)+L-2"`), hp filters (`"HP < H"`) and
/// bracketed entity values (`"[X/2{$math.ceil}]"`).
///
/// It replaces `NSPredicate(format:)` / `NSExpression(format:)`, which raise uncatchable
/// Objective-C exceptions on input such as `%`. Every entry point returns `nil` on any
/// lexing, parsing or evaluation error and never traps.
///
/// Grammar (lowest to highest precedence, JavaScript semantics):
/// ```
/// expr           := or
/// or             := and ( ("||" | "or") and )*
/// and            := equality ( ("&&" | "and") equality )*
/// equality       := comparison ( ("==" | "!=" | "===" | "!==") comparison )*
/// comparison     := additive ( ("<" | ">" | "<=" | ">=") additive )*
/// additive       := multiplicative ( ("+" | "-") multiplicative )*
/// multiplicative := unary ( ("*" | "/" | "%" | "x") unary )*
/// unary          := ("!" | "not" | "-" | "+") unary | primary
/// primary        := number | variable | "true" | "false" | "(" expr ")" | "[" expr "]"
/// ```
/// - A lowercase `x` between two operands is multiplication (`2xC`, `HxC`, `Cx(3+L)`);
///   uppercase identifiers (`R`, `C`, `L`, `H`, `X`, `F`, `HP`, ...) are variables.
/// - Booleans are numbers (`true` = 1, `false` = 0); a value is truthy when non-zero.
/// - Division or modulo by zero, unknown variables and non-finite results are errors (`nil`).
enum ScenarioExpression {

    // MARK: - AST

    indirect enum Node: Equatable {
        case number(Double)
        case variable(String)
        case unary(UnaryOperator, Node)
        case binary(BinaryOperator, Node, Node)
    }

    enum UnaryOperator: Equatable {
        case negate, plus, not
    }

    enum BinaryOperator: Equatable {
        case add, subtract, multiply, divide, modulo
        case equal, notEqual, less, greater, lessOrEqual, greaterOrEqual
        case and, or
    }

    /// Maximum nesting depth accepted by the parser (guards against stack exhaustion).
    static let maxDepth = 64

    // MARK: - Public API

    /// Parses `source` into an expression tree, or returns `nil` if it is not well formed.
    static func parse(_ source: String) -> Node? {
        guard let tokens = tokenize(source), !tokens.isEmpty else { return nil }
        var parser = Parser(tokens: tokens)
        guard let node = parser.parseExpression(depth: 0), parser.isAtEnd else { return nil }
        return node
    }

    /// All variable names referenced by `node`.
    static func variables(in node: Node) -> Set<String> {
        switch node {
        case .number: return []
        case .variable(let name): return [name]
        case .unary(_, let operand): return variables(in: operand)
        case .binary(_, let lhs, let rhs): return variables(in: lhs).union(variables(in: rhs))
        }
    }

    /// Evaluates a parsed tree. Returns `nil` on unknown variables, division by zero or
    /// non-finite results.
    static func evaluate(_ node: Node, variables: [String: Double]) -> Double? {
        switch node {
        case .number(let value):
            return value
        case .variable(let name):
            return variables[name]
        case .unary(let op, let operand):
            guard let value = evaluate(operand, variables: variables) else { return nil }
            switch op {
            case .negate: return -value
            case .plus: return value
            case .not: return isTruthy(value) ? 0 : 1
            }
        case .binary(let op, let lhsNode, let rhsNode):
            // Short-circuit logical operators (JavaScript semantics).
            if op == .and || op == .or {
                guard let lhs = evaluate(lhsNode, variables: variables) else { return nil }
                if op == .and && !isTruthy(lhs) { return 0 }
                if op == .or && isTruthy(lhs) { return 1 }
                guard let rhs = evaluate(rhsNode, variables: variables) else { return nil }
                return isTruthy(rhs) ? 1 : 0
            }
            guard let lhs = evaluate(lhsNode, variables: variables),
                  let rhs = evaluate(rhsNode, variables: variables) else { return nil }
            let result: Double
            switch op {
            case .add: result = lhs + rhs
            case .subtract: result = lhs - rhs
            case .multiply: result = lhs * rhs
            case .divide:
                guard rhs != 0 else { return nil }
                result = lhs / rhs
            case .modulo:
                guard rhs != 0 else { return nil }
                result = lhs.truncatingRemainder(dividingBy: rhs)
            case .equal: result = lhs == rhs ? 1 : 0
            case .notEqual: result = lhs != rhs ? 1 : 0
            case .less: result = lhs < rhs ? 1 : 0
            case .greater: result = lhs > rhs ? 1 : 0
            case .lessOrEqual: result = lhs <= rhs ? 1 : 0
            case .greaterOrEqual: result = lhs >= rhs ? 1 : 0
            case .and, .or: return nil // handled above
            }
            return result.isFinite ? result : nil
        }
    }

    /// Parses and evaluates `source` to a number, or `nil` on any error.
    static func number(_ source: String, variables: [String: Int] = [:]) -> Double? {
        guard let node = parse(source) else { return nil }
        return evaluate(node, variables: variables.mapValues(Double.init))
    }

    /// Parses and evaluates `source` as a condition (non-zero is true), or `nil` on any error.
    static func condition(_ source: String, variables: [String: Int] = [:]) -> Bool? {
        guard let value = number(source, variables: variables) else { return nil }
        return isTruthy(value)
    }

    /// Evaluates an integer value expression as used for counts, damage and hit points.
    ///
    /// Accepts plain integers (`"3"`), plain expressions (`"(2xC)+L-2"`) and the bracketed
    /// entity-value form with an optional math function (`"[X/2{$math.ceil}]"`,
    /// `"[LxC/2{$math.max:1}]"`). Results are truncated toward zero like `Int(Double)`.
    /// Returns `nil` on any error or if the result does not fit comfortably in an `Int`.
    static func integerValue(_ source: String, variables: [String: Int] = [:]) -> Int? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let plain = Int(trimmed) { return plain }

        var expression = trimmed
        var function: String?
        if let open = trimmed.firstIndex(of: "["), let close = trimmed.lastIndex(of: "]"), open < close {
            let inner = String(trimmed[trimmed.index(after: open)..<close])
            if let braceOpen = inner.firstIndex(of: "{"), let braceClose = inner.lastIndex(of: "}"),
               braceOpen < braceClose {
                expression = String(inner[inner.startIndex..<braceOpen])
                function = String(inner[inner.index(after: braceOpen)..<braceClose])
            } else {
                expression = inner
            }
        }

        guard var value = number(expression, variables: variables) else { return nil }
        if let function {
            guard let applied = applyMathFunction(function, to: value) else { return nil }
            value = applied
        }
        guard value.isFinite, abs(value) < 1e12 else { return nil }
        return Int(value)
    }

    // MARK: - Helpers

    static func isTruthy(_ value: Double) -> Bool {
        value != 0 && !value.isNaN
    }

    /// Applies a GHS math function such as `$math.ceil`, `$math.max:2`. Unknown functions are errors.
    private static func applyMathFunction(_ raw: String, to value: Double) -> Double? {
        let cleaned = raw.replacingOccurrences(of: "$", with: "")
        let parts = cleaned.split(separator: ":", maxSplits: 1).map(String.init)
        guard let name = parts.first else { return nil }
        var argument: Double?
        if parts.count > 1 {
            guard let parsed = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            argument = parsed
        }
        switch (name, argument) {
        case ("math.ceil", _): return value.rounded(.up)
        case ("math.floor", _): return value.rounded(.down)
        case ("math.round", _): return value.rounded()
        case ("math.max", let a?): return max(value, a)
        case ("math.min", let a?): return min(value, a)
        case ("math.maxCeil", let a?): return max(value, a).rounded(.up)
        case ("math.minCeil", let a?): return min(value, a).rounded(.up)
        case ("math.maxFloor", let a?): return max(value, a).rounded(.down)
        case ("math.minFloor", let a?): return min(value, a).rounded(.down)
        default: return nil
        }
    }

    // MARK: - Lexer

    enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case op(String)
        case openParen
        case closeParen
    }

    private static let multiCharOperators = ["===", "!==", "==", "!=", "<=", ">=", "&&", "||"]
    private static let singleCharOperators: Set<Character> = ["+", "-", "*", "/", "%", "<", ">", "!"]

    /// Splits `source` into tokens, or returns `nil` on an unexpected character.
    static func tokenize(_ source: String) -> [Token]? {
        let chars = Array(source)
        var tokens: [Token] = []
        var i = 0

        func previousIsOperand() -> Bool {
            switch tokens.last {
            case .number, .identifier, .closeParen: return true
            default: return false
            }
        }

        func nextNonSpaceStartsOperand(after index: Int) -> Bool {
            var j = index + 1
            while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
            guard j < chars.count else { return false }
            let c = chars[j]
            return c.isASCII && (c.isNumber || c.isUppercase || c == "(" || c == "[" || c == ".")
        }

        while i < chars.count {
            let c = chars[i]

            if c == " " || c == "\t" || c == "\n" || c == "\r" {
                i += 1
                continue
            }

            if c.isASCII && (c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isASCII && chars[i + 1].isNumber)) {
                var j = i
                var seenDot = false
                while j < chars.count, chars[j].isASCII, chars[j].isNumber || (chars[j] == "." && !seenDot) {
                    if chars[j] == "." { seenDot = true }
                    j += 1
                }
                guard let value = Double(String(chars[i..<j])) else { return nil }
                tokens.append(.number(value))
                i = j
                continue
            }

            if c.isASCII && (c.isLetter || c == "_") {
                // Lowercase `x` between two operands is multiplication: 2xC, HxC, Cx(3+L).
                if c == "x" && previousIsOperand() && nextNonSpaceStartsOperand(after: i) {
                    tokens.append(.op("*"))
                    i += 1
                    continue
                }
                var j = i + 1
                if c.isUppercase {
                    // Uppercase variable names (R, C, L, HP, ...) stop at a lowercase letter so
                    // that `HxC` lexes as H x C.
                    while j < chars.count, chars[j].isASCII,
                          chars[j].isUppercase || chars[j].isNumber || chars[j] == "_" {
                        j += 1
                    }
                } else {
                    while j < chars.count, chars[j].isASCII,
                          chars[j].isLetter || chars[j].isNumber || chars[j] == "_" {
                        j += 1
                    }
                }
                let word = String(chars[i..<j])
                switch word.lowercased() {
                case "true": tokens.append(.number(1))
                case "false": tokens.append(.number(0))
                case "and": tokens.append(.op("&&"))
                case "or": tokens.append(.op("||"))
                case "not": tokens.append(.op("!"))
                default: tokens.append(.identifier(word))
                }
                i = j
                continue
            }

            if c == "(" || c == "[" {
                tokens.append(.openParen)
                i += 1
                continue
            }
            if c == ")" || c == "]" {
                tokens.append(.closeParen)
                i += 1
                continue
            }

            if let op = multiCharOperators.first(where: { matches($0, chars, at: i) }) {
                tokens.append(.op(op))
                i += op.count
                continue
            }
            if singleCharOperators.contains(c) {
                tokens.append(.op(String(c)))
                i += 1
                continue
            }

            return nil
        }
        return tokens
    }

    private static func matches(_ op: String, _ chars: [Character], at index: Int) -> Bool {
        let opChars = Array(op)
        guard index + opChars.count <= chars.count else { return false }
        for k in 0..<opChars.count where chars[index + k] != opChars[k] { return false }
        return true
    }

    // MARK: - Parser

    private struct Parser {
        let tokens: [Token]
        var position = 0

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        var isAtEnd: Bool { position >= tokens.count }

        private var current: Token? { isAtEnd ? nil : tokens[position] }

        private mutating func consumeOperator(_ candidates: [String]) -> String? {
            if case .op(let op)? = current, candidates.contains(op) {
                position += 1
                return op
            }
            return nil
        }

        mutating func parseExpression(depth: Int) -> Node? {
            guard depth < ScenarioExpression.maxDepth else { return nil }
            return parseOr(depth: depth)
        }

        private mutating func parseOr(depth: Int) -> Node? {
            guard var lhs = parseAnd(depth: depth) else { return nil }
            while consumeOperator(["||"]) != nil {
                guard let rhs = parseAnd(depth: depth) else { return nil }
                lhs = .binary(.or, lhs, rhs)
            }
            return lhs
        }

        private mutating func parseAnd(depth: Int) -> Node? {
            guard var lhs = parseEquality(depth: depth) else { return nil }
            while consumeOperator(["&&"]) != nil {
                guard let rhs = parseEquality(depth: depth) else { return nil }
                lhs = .binary(.and, lhs, rhs)
            }
            return lhs
        }

        private mutating func parseEquality(depth: Int) -> Node? {
            guard var lhs = parseComparison(depth: depth) else { return nil }
            while let op = consumeOperator(["==", "!=", "===", "!=="]) {
                guard let rhs = parseComparison(depth: depth) else { return nil }
                lhs = .binary(op.hasPrefix("!") ? .notEqual : .equal, lhs, rhs)
            }
            return lhs
        }

        private mutating func parseComparison(depth: Int) -> Node? {
            guard var lhs = parseAdditive(depth: depth) else { return nil }
            while let op = consumeOperator(["<", ">", "<=", ">="]) {
                guard let rhs = parseAdditive(depth: depth) else { return nil }
                let kind: BinaryOperator
                switch op {
                case "<": kind = .less
                case ">": kind = .greater
                case "<=": kind = .lessOrEqual
                default: kind = .greaterOrEqual
                }
                lhs = .binary(kind, lhs, rhs)
            }
            return lhs
        }

        private mutating func parseAdditive(depth: Int) -> Node? {
            guard var lhs = parseMultiplicative(depth: depth) else { return nil }
            while let op = consumeOperator(["+", "-"]) {
                guard let rhs = parseMultiplicative(depth: depth) else { return nil }
                lhs = .binary(op == "+" ? .add : .subtract, lhs, rhs)
            }
            return lhs
        }

        private mutating func parseMultiplicative(depth: Int) -> Node? {
            guard var lhs = parseUnary(depth: depth) else { return nil }
            while let op = consumeOperator(["*", "/", "%"]) {
                guard let rhs = parseUnary(depth: depth) else { return nil }
                let kind: BinaryOperator
                switch op {
                case "*": kind = .multiply
                case "/": kind = .divide
                default: kind = .modulo
                }
                lhs = .binary(kind, lhs, rhs)
            }
            return lhs
        }

        private mutating func parseUnary(depth: Int) -> Node? {
            guard depth < ScenarioExpression.maxDepth else { return nil }
            if let op = consumeOperator(["!", "-", "+"]) {
                guard let operand = parseUnary(depth: depth + 1) else { return nil }
                switch op {
                case "!": return .unary(.not, operand)
                case "-": return .unary(.negate, operand)
                default: return .unary(.plus, operand)
                }
            }
            return parsePrimary(depth: depth)
        }

        private mutating func parsePrimary(depth: Int) -> Node? {
            guard let token = current else { return nil }
            switch token {
            case .number(let value):
                position += 1
                return .number(value)
            case .identifier(let name):
                position += 1
                return .variable(name)
            case .openParen:
                position += 1
                guard let inner = parseExpression(depth: depth + 1) else { return nil }
                guard case .closeParen? = current else { return nil }
                position += 1
                return inner
            case .closeParen, .op:
                return nil
            }
        }
    }
}
