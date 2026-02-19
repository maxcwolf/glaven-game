import Foundation

enum AttackModifierValueType: String, Codable, CaseIterable {
    case `default` = "default"
    case plus, minus, multiply
}
