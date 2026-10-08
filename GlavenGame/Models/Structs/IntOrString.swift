import Foundation

enum IntOrString: Codable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else {
            throw DecodingError.typeMismatch(IntOrString.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected Int or String"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }

    var intValue: Int {
        switch self {
        case .int(let v): return v
        case .string(let s): return Int(s) ?? 0
        }
    }

    var stringValue: String {
        switch self {
        case .int(let v): return "\(v)"
        case .string(let s): return s
        }
    }

    var isExpression: Bool {
        if case .string(let s) = self { return s.contains("[") }
        return false
    }

    /// True for any non-integer string value, bracketed or not (`"8xC"`, `"1+C"`, `"3+X"`).
    /// Such values must go through `evaluated(...)`; `intValue` returns 0 for them.
    var isFormula: Bool {
        if case .string(let s) = self { return Int(s) == nil }
        return false
    }

    /// Evaluates the value with `evaluateEntityValue` (C = max(2, characterCount), L = level,
    /// card-specific letters from `variables`, unknown letters = 0, result rounded down).
    func evaluated(level: Int = 1, characterCount: Int = 2, round: Int = 0, prosperity: Int = 0,
                   variables: [String: Int] = [:]) -> Int {
        evaluateEntityValue(self, level: level, characterCount: characterCount, round: round,
                            prosperity: prosperity, variables: variables)
    }
}
