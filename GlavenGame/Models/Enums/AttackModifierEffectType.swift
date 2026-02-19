import Foundation

enum AttackModifierEffectType: String, Codable, CaseIterable {
    case attack, range, pierce, target
    case condition, element, elementHalf, elementConsume
    case heal, shield, retaliate
    case push, pull, area
    case summon, swing, changeType, or_ = "or", custom
    case specialTarget, refreshItem, refreshSpent
    case sufferDamage, recover, bless, curse
}
