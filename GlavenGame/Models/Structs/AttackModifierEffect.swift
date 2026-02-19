import Foundation

struct AttackModifierEffect: Codable, Hashable {
    var type: AttackModifierEffectType
    var value: IntOrString?
    var hint: String?
    var effects: [AttackModifierEffect]?
    var icon: Bool?
}
