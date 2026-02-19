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
}
