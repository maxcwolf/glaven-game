import Foundation

/// Represents a single enhancement applied to an ability card action.
struct Enhancement: Codable, Hashable, Identifiable {
    var id = UUID()
    var cardId: Int          // Which ability card
    var actionHalf: String   // "top" or "bottom"
    var actionIndex: Int     // Index within that half's actions
    var slotIndex: Int       // Which enhancement slot on that action
    var action: EnhancementAction // What enhancement was applied
    var inherited: Bool = false

    enum CodingKeys: String, CodingKey {
        case cardId, actionHalf, actionIndex, slotIndex, action, inherited
    }

    init(cardId: Int, actionHalf: String, actionIndex: Int, slotIndex: Int, action: EnhancementAction, inherited: Bool = false) {
        self.cardId = cardId
        self.actionHalf = actionHalf
        self.actionIndex = actionIndex
        self.slotIndex = slotIndex
        self.action = action
        self.inherited = inherited
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cardId = try container.decode(Int.self, forKey: .cardId)
        actionHalf = try container.decode(String.self, forKey: .actionHalf)
        actionIndex = try container.decode(Int.self, forKey: .actionIndex)
        slotIndex = try container.decode(Int.self, forKey: .slotIndex)
        action = try container.decode(EnhancementAction.self, forKey: .action)
        inherited = try container.decodeIfPresent(Bool.self, forKey: .inherited) ?? false
    }
}

/// The possible enhancement actions that can be applied to a slot.
enum EnhancementAction: String, Codable, Hashable, CaseIterable {
    // Numeric boosts
    case plus1 = "plus1"
    // Area
    case hex = "hex"
    // Jump
    case jump = "jump"
    // Negative conditions
    case poison, wound, muddle, immobilize, disarm, curse
    case bane, brittle, impair, chill, infect, rupture
    // Positive conditions
    case strengthen, bless, regenerate, ward, dodge
    case empower, safeguard
    // Elements
    case fire, ice, air, earth, light, dark, wild

    var displayName: String {
        switch self {
        case .plus1: return "+1"
        case .hex: return "Hex"
        case .jump: return "Jump"
        case .wild: return "Any Element"
        default:
            return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var isCondition: Bool {
        isNegativeCondition || isPositiveCondition
    }

    var isNegativeCondition: Bool {
        switch self {
        case .poison, .wound, .muddle, .immobilize, .disarm, .curse,
             .bane, .brittle, .impair, .chill, .infect, .rupture:
            return true
        default: return false
        }
    }

    var isPositiveCondition: Bool {
        switch self {
        case .strengthen, .bless, .regenerate, .ward, .dodge,
             .empower, .safeguard:
            return true
        default: return false
        }
    }

    var isElement: Bool {
        switch self {
        case .fire, .ice, .air, .earth, .light, .dark, .wild:
            return true
        default: return false
        }
    }
}
