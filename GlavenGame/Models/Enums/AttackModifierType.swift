import Foundation

enum AttackModifierType: String, Codable, CaseIterable {
    case plus0, plus1, plus2, plus3, plus4, plusX
    case minus1, minus2, minus1extra
    case double_ = "double"
    case null_ = "null"
    case bless, curse
    case townguard, wreck, success
    case imbue, advancedImbue
    case empower, enfeeble

    var displayValue: Int {
        switch self {
        case .plus0: return 0
        case .plus1: return 1
        case .plus2: return 2
        case .plus3: return 3
        case .plus4: return 4
        case .minus1, .minus1extra: return -1
        case .minus2: return -2
        case .double_: return 2
        case .null_: return 0
        default: return 0
        }
    }

    var isSpecial: Bool {
        switch self {
        case .bless, .curse, .empower, .enfeeble: return true
        default: return false
        }
    }
}
