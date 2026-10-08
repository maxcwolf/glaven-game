import Foundation

/// Evaluates dynamic value expressions from Gloomhaven (Secretariat-format) data.
///
/// Every expression form found in the bundled monster / scenario / character data is
/// supported:
/// - plain integers: `"3"`
/// - character-count / level formulas: `"8xC"`, `"1+C"`, `"(10xC)/2"`, `"10xC/2"`,
///   `"(7+L)xC"`, `"Cx(3+L)"`, `"15+5xL"`, `"8+Lx2"`, `"4+C+(2xL)"`
/// - bracketed expressions with an optional rounding function:
///   `"[2+(LxC/2){$math.floor}]"`, `"[X/2{$math.ceil}]"`, `"[Hx2]"`
/// - free variables defined by the card itself, e.g. Dark Rider `"3+X"` (X = hexes moved
///   this turn) or Merciless Overseer `"V"` (V = number of Vermling Scouts present).
///
/// Grammar: `+ - * /` with normal precedence, unary minus, parentheses, and `x` / `×`
/// (lower-case) as multiplication. Single upper-case letters are variables:
/// - `C` = character count (clamped to a minimum of 2, as Gloomhaven Secretariat does)
/// - `L` = level, `P` = prosperity, `R` = round
/// - any other letter (`X`, `V`, `H`, ...) is looked up in `variables`; an unknown
///   variable evaluates to 0 so a card-specific value degrades to its base number
///   (Dark Rider `"3+X"` → 3) instead of crashing or yielding 0.
///
/// Rounding: unless a `{$math.*}` function says otherwise the result is rounded **down**
/// (Gloomhaven's default), e.g. Bloated Regent `"13xC/2"` at C=3 → 19.
/// Unparseable input (e.g. free text) evaluates to 0.
///
/// - Parameters:
///   - value: The value to evaluate (Int passthrough, or String expression)
///   - level: Current game/monster level (`L`)
///   - characterCount: Number of active characters (`C`, minimum 2)
///   - round: Current round number (`R`)
///   - prosperity: Party prosperity level (`P`)
///   - variables: Values for card-specific variables (e.g. `["X": hexesMoved]`). Keys are
///     single upper-case letters; they override the built-in `C`/`L`/`P`/`R` if present.
/// - Returns: The evaluated integer result
func evaluateEntityValue(_ value: IntOrString, level: Int = 1, characterCount: Int = 2,
                         round: Int = 0, prosperity: Int = 0,
                         variables: [String: Int] = [:]) -> Int {
    switch value {
    case .int(let n):
        return n
    case .string(let expr):
        return evaluateEntityExpression(expr, level: level, characterCount: characterCount,
                                        round: round, prosperity: prosperity, variables: variables)
    }
}

func evaluateEntityValue(_ value: Int) -> Int {
    return value
}

/// Evaluates a raw expression string. See `evaluateEntityValue(_:level:characterCount:round:prosperity:variables:)`.
func evaluateEntityExpression(_ raw: String, level: Int = 1, characterCount: Int = 2,
                              round: Int = 0, prosperity: Int = 0,
                              variables: [String: Int] = [:]) -> Int {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != "-" else { return 0 }

    // Fast path: plain integer
    if let plainInt = Int(trimmed) { return plainInt }

    let (expression, funcName) = splitEntityExpression(trimmed)

    var env: [Character: Double] = [
        "C": Double(max(2, characterCount)),
        "L": Double(level),
        "P": Double(prosperity),
        "R": Double(round)
    ]
    for (key, val) in variables {
        guard key.count == 1, let ch = key.first else { continue }
        env[ch] = Double(val)
    }

    var parser = EntityExpressionParser(expression, variables: env)
    guard var value = parser.parse(), value.isFinite else { return 0 }

    if let funcName {
        value = applyEntityMathFunction(funcName, to: value)
    }
    // Tiny epsilon guards against binary floating-point noise (e.g. 2.9999999 → 3).
    value = (value + 1e-9).rounded(.down)
    guard value.isFinite, abs(value) < Double(Int32.max) else { return 0 }
    return Int(value)
}

/// Returns the set of variable letters (e.g. `["C"]`, `["X"]`, `["V"]`) referenced by the value.
/// Useful for detecting card-specific variables (`X`, `V`, `H`) that the caller must supply.
func entityValueVariables(_ value: IntOrString) -> Set<String> {
    guard case .string(let raw) = value else { return [] }
    let (expression, _) = splitEntityExpression(raw)
    var result = Set<String>()
    for ch in expression where ch.isUppercase && ch.isLetter {
        result.insert(String(ch))
    }
    return result
}

// MARK: - Private helpers

/// Splits `"[expr{$math.fn:arg}]"` into `("expr", "$math.fn:arg")`. Strings without
/// brackets are returned unchanged with no function.
private func splitEntityExpression(_ raw: String) -> (expression: String, function: String?) {
    var expression = raw
    var funcName: String?
    if let openBracket = raw.firstIndex(of: "["),
       let closeBracket = raw.lastIndex(of: "]"),
       openBracket < closeBracket {
        let inner = String(raw[raw.index(after: openBracket)..<closeBracket])
        if let openBrace = inner.firstIndex(of: "{"),
           let closeBrace = inner.lastIndex(of: "}"),
           openBrace < closeBrace {
            expression = String(inner[inner.startIndex..<openBrace])
            funcName = String(inner[inner.index(after: openBrace)..<closeBrace])
        } else {
            expression = inner
        }
    }
    return (expression, funcName)
}

private func applyEntityMathFunction(_ funcName: String, to input: Double) -> Double {
    var value = input
    let cleaned = funcName.replacingOccurrences(of: "$", with: "")
    let parts = cleaned.split(separator: ":")
    guard let first = parts.first else { return value }
    let fn = String(first)
    let funcArg = parts.count > 1 ? Double(parts[1]) : nil

    switch fn {
    case "math.ceil": value = ceil(value)
    case "math.floor": value = floor(value)
    case "math.max": if let a = funcArg { value = max(value, a) }
    case "math.min": if let a = funcArg { value = min(value, a) }
    case "math.maxCeil": if let a = funcArg { value = ceil(max(value, a)) } else { value = ceil(value) }
    case "math.minCeil": if let a = funcArg { value = ceil(min(value, a)) } else { value = ceil(value) }
    case "math.maxFloor": if let a = funcArg { value = floor(max(value, a)) } else { value = floor(value) }
    case "math.minFloor": if let a = funcArg { value = floor(min(value, a)) } else { value = floor(value) }
    default: break
    }
    return value
}

/// Small recursive-descent arithmetic parser. Never throws or traps: any malformed input
/// makes `parse()` return nil (unlike `NSExpression(format:)`, which raises an uncatchable
/// Objective-C exception on bad input such as `"3+"`).
private struct EntityExpressionParser {
    private let chars: [Character]
    private var pos = 0
    private let variables: [Character: Double]

    init(_ text: String, variables: [Character: Double]) {
        self.chars = Array(text.filter { !$0.isWhitespace })
        self.variables = variables
    }

    mutating func parse() -> Double? {
        guard !chars.isEmpty, let value = parseExpression() else { return nil }
        return pos == chars.count ? value : nil
    }

    private var current: Character? { pos < chars.count ? chars[pos] : nil }

    // expression := term (('+' | '-') term)*
    private mutating func parseExpression() -> Double? {
        guard var lhs = parseTerm() else { return nil }
        while let op = current, op == "+" || op == "-" {
            pos += 1
            guard let rhs = parseTerm() else { return nil }
            lhs = op == "+" ? lhs + rhs : lhs - rhs
        }
        return lhs
    }

    // term := factor (('*' | 'x' | '×' | '/') factor)*
    private mutating func parseTerm() -> Double? {
        guard var lhs = parseFactor() else { return nil }
        while let op = current, op == "*" || op == "x" || op == "×" || op == "/" {
            pos += 1
            guard let rhs = parseFactor() else { return nil }
            if op == "/" {
                guard rhs != 0 else { return nil }
                lhs /= rhs
            } else {
                lhs *= rhs
            }
        }
        return lhs
    }

    // factor := ('+' | '-') factor | number | VARIABLE | '(' expression ')'
    private mutating func parseFactor() -> Double? {
        guard let ch = current else { return nil }
        if ch == "-" || ch == "+" {
            pos += 1
            guard let inner = parseFactor() else { return nil }
            return ch == "-" ? -inner : inner
        }
        if ch == "(" {
            pos += 1
            guard let inner = parseExpression(), current == ")" else { return nil }
            pos += 1
            return inner
        }
        if ch.isASCII, ch.isNumber || ch == "." {
            let start = pos
            while let c = current, c.isASCII, c.isNumber || c == "." { pos += 1 }
            return Double(String(chars[start..<pos]))
        }
        if ch.isASCII, ch.isUppercase {
            pos += 1
            // Unknown card-specific variables (X, V, H...) default to 0.
            return variables[ch] ?? 0
        }
        return nil
    }
}
