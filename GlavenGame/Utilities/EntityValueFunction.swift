import Foundation

/// Evaluates dynamic value expressions from Gloomhaven data.
/// Expressions like "[xC]", "[L*2{$math.ceil}]" are evaluated with variable substitution.
/// - Parameters:
///   - value: The value to evaluate (Int passthrough, or String expression)
///   - level: Current game/monster level
///   - characterCount: Number of active characters
///   - round: Current round number
///   - prosperity: Party prosperity level
/// - Returns: The evaluated integer result
func evaluateEntityValue(_ value: IntOrString, level: Int = 1, characterCount: Int = 2, round: Int = 0, prosperity: Int = 0) -> Int {
    switch value {
    case .int(let n):
        return n
    case .string(let expr):
        return evaluateExpression(expr, level: level, characterCount: characterCount, round: round, prosperity: prosperity)
    }
}

func evaluateEntityValue(_ value: Int) -> Int {
    return value
}

private func evaluateExpression(_ raw: String, level: Int, characterCount: Int, round: Int, prosperity: Int) -> Int {
    guard !raw.isEmpty, raw != "-" else { return 0 }

    // Try parsing as plain integer first
    if let plainInt = Int(raw) { return plainInt }

    // Extract expression and optional function from [expression{function}] format
    var expression = raw
    var funcName: String? = nil

    // Match pattern: [expression{function}]
    if let openBracket = raw.firstIndex(of: "["),
       let closeBracket = raw.lastIndex(of: "]") {
        let inner = String(raw[raw.index(after: openBracket)..<closeBracket])

        if let openBrace = inner.firstIndex(of: "{"),
           let closeBrace = inner.lastIndex(of: "}") {
            expression = String(inner[inner.startIndex..<openBrace])
            funcName = String(inner[inner.index(after: openBrace)..<closeBrace])
        } else {
            expression = inner
        }
    }

    // Variable substitution
    let C = max(2, characterCount)
    expression = expression.replacingOccurrences(of: "x", with: "*")
    expression = expression.replacingOccurrences(of: "C", with: "\(C)")
    expression = expression.replacingOccurrences(of: "L", with: "\(level)")
    expression = expression.replacingOccurrences(of: "P", with: "\(prosperity)")
    expression = expression.replacingOccurrences(of: "R", with: "\(round)")

    // Evaluate arithmetic using NSExpression
    let nsExpr = NSExpression(format: expression)
    guard let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
        return 0
    }
    var value = result.doubleValue

    // Apply math function if present
    if let funcName = funcName {
        let cleaned = funcName.replacingOccurrences(of: "$", with: "")
        let parts = cleaned.split(separator: ":")
        let fn = String(parts[0])
        let funcArg = parts.count > 1 ? Double(parts[1]) : nil

        switch fn {
        case "math.ceil": value = ceil(value)
        case "math.floor": value = floor(value)
        case "math.max": if let a = funcArg { value = max(value, a) }
        case "math.min": if let a = funcArg { value = min(value, a) }
        case "math.maxCeil": if let a = funcArg { value = ceil(max(value, a)) }
        case "math.minCeil": if let a = funcArg { value = ceil(min(value, a)) }
        case "math.maxFloor": if let a = funcArg { value = floor(max(value, a)) }
        case "math.minFloor": if let a = funcArg { value = floor(min(value, a)) }
        default: break
        }
    }

    return Int(value)
}
