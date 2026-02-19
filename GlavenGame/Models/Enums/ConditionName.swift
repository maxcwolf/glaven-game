import Foundation

enum ConditionName: String, Codable, CaseIterable {
    // Negative conditions
    case stun, immobilize, disarm, wound, muddle, poison
    case invisible, curse, bane, brittle, impair, chill
    case infect, rupture
    // Positive conditions
    case strengthen, regenerate, ward, bless, dodge
    case empower, safeguard
    // Special/valued
    case shield, heal, retaliate
    case plague, enfeeble
    case poison_x, wound_x
    // Movement immunities
    case push, pull

    var isPositive: Bool {
        switch self {
        case .strengthen, .regenerate, .ward, .bless, .dodge, .empower, .safeguard:
            return true
        default:
            return false
        }
    }

    var isNegative: Bool {
        switch self {
        case .stun, .immobilize, .disarm, .wound, .muddle, .poison,
             .invisible, .curse, .bane, .brittle, .impair, .chill,
             .infect, .rupture, .plague, .enfeeble, .poison_x, .wound_x:
            return true
        default:
            return false
        }
    }
}
