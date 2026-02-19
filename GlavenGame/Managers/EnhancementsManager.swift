import Foundation

@Observable
final class EnhancementsManager {
    private let game: GameState
    var onBeforeMutate: (() -> Void)?

    init(game: GameState) {
        self.game = game
    }

    // MARK: - Available Actions for Slot Types

    static func availableActions(for slotType: EnhancementSlotType, actionType: ActionType, isSummon: Bool, edition: String) -> [EnhancementAction] {
        var actions: [EnhancementAction] = []

        switch slotType {
        case .square:
            actions.append(.plus1)
        case .circle:
            actions.append(.plus1)
            actions.append(contentsOf: elementActions)
        case .diamond:
            actions.append(.plus1)
            actions.append(contentsOf: negativeConditions(edition: edition))
        case .diamond_plus:
            actions.append(.plus1)
            actions.append(contentsOf: positiveConditions(edition: edition))
        case .hex:
            actions.append(.hex)
        case .any:
            actions.append(.plus1)
            actions.append(contentsOf: elementActions)
            actions.append(contentsOf: negativeConditions(edition: edition))
            actions.append(contentsOf: positiveConditions(edition: edition))
            if actionType == .move {
                actions.append(.jump)
            }
            actions.append(.hex)
        }

        return actions
    }

    private static var elementActions: [EnhancementAction] {
        [.fire, .ice, .air, .earth, .light, .dark, .wild]
    }

    private static func negativeConditions(edition: String) -> [EnhancementAction] {
        var conditions: [EnhancementAction] = [.poison, .wound, .muddle, .immobilize, .curse]
        if edition == "gh" {
            conditions.append(.disarm)
        }
        return conditions
    }

    private static func positiveConditions(edition: String) -> [EnhancementAction] {
        var conditions: [EnhancementAction] = [.strengthen, .bless, .regenerate]
        if edition == "fh" {
            conditions.append(.ward)
        }
        return conditions
    }

    // MARK: - Cost Calculation

    static func enhancementCost(
        action: EnhancementAction,
        slotType: EnhancementSlotType,
        actionType: ActionType,
        cardLevel: Int,
        previousEnhancements: Int,
        isMultiTarget: Bool,
        isLost: Bool,
        isPersistent: Bool,
        isSummon: Bool,
        edition: String
    ) -> Int {
        let isFH = edition == "fh"

        // Base cost
        var cost = baseCost(for: action, actionType: actionType, isSummon: isSummon, isFH: isFH)

        // Multi-target multiplier
        if isMultiTarget {
            cost *= 2
        }

        // FH: lost card discount
        if isFH && isLost {
            cost /= 2
        }

        // FH: persistent card multiplier
        if isFH && isPersistent {
            cost *= 3
        }

        // Level surcharge
        let levelSurcharge = isFH ? 15 : 25
        cost += max(0, cardLevel - 1) * levelSurcharge

        // Previous enhancements surcharge
        let enhancementSurcharge = isFH ? 50 : 75
        cost += previousEnhancements * enhancementSurcharge

        return max(0, cost)
    }

    private static func baseCost(for action: EnhancementAction, actionType: ActionType, isSummon: Bool, isFH: Bool) -> Int {
        if isSummon {
            return summonBaseCost(for: action, isFH: isFH)
        }
        return standardBaseCost(for: action, actionType: actionType, isFH: isFH)
    }

    private static func standardBaseCost(for action: EnhancementAction, actionType: ActionType, isFH: Bool) -> Int {
        switch action {
        case .plus1:
            switch actionType {
            case .move: return isFH ? 20 : 30
            case .attack: return isFH ? 35 : 50
            case .range: return isFH ? 20 : 30
            case .shield: return isFH ? 60 : 100
            case .retaliate: return isFH ? 40 : 100
            case .pierce: return isFH ? 15 : 30
            case .heal: return isFH ? 20 : 30
            case .push, .pull: return isFH ? 15 : 30
            case .teleport: return isFH ? 40 : 50
            case .target: return isFH ? 50 : 75
            default: return isFH ? 30 : 50
            }
        case .jump:
            return isFH ? 35 : 60
        case .hex:
            return isFH ? 80 : 200
        case .poison: return isFH ? 25 : 75
        case .wound: return isFH ? 25 : 75
        case .muddle: return isFH ? 25 : 50
        case .immobilize: return isFH ? 50 : 150
        case .disarm: return 150
        case .curse: return isFH ? 50 : 150
        case .bane: return 50
        case .brittle: return 25
        case .impair: return 50
        case .chill: return 25
        case .infect: return 25
        case .rupture: return 25
        case .strengthen: return isFH ? 50 : 100
        case .bless: return isFH ? 50 : 75
        case .regenerate: return isFH ? 25 : 40
        case .ward: return 50
        case .dodge: return 50
        case .empower: return 50
        case .safeguard: return 50
        case .fire, .ice, .air, .earth, .light, .dark: return isFH ? 60 : 100
        case .wild: return isFH ? 100 : 150
        }
    }

    private static func summonBaseCost(for action: EnhancementAction, isFH: Bool) -> Int {
        switch action {
        case .plus1:
            return isFH ? 40 : 100 // summon stats are more expensive
        case .poison, .wound: return isFH ? 30 : 100
        case .muddle: return isFH ? 30 : 75
        case .immobilize: return isFH ? 75 : 200
        case .strengthen: return isFH ? 75 : 150
        case .bless: return isFH ? 75 : 100
        case .regenerate: return isFH ? 30 : 50
        default: return standardBaseCost(for: action, actionType: .attack, isFH: isFH)
        }
    }

    // MARK: - Enhancement Operations

    func addEnhancement(_ enhancement: Enhancement, to character: GameCharacter) {
        onBeforeMutate?()
        character.enhancements.append(enhancement)
    }

    func removeEnhancement(_ enhancement: Enhancement, from character: GameCharacter) {
        guard !enhancement.inherited else { return }
        onBeforeMutate?()
        character.enhancements.removeAll { $0.cardId == enhancement.cardId && $0.actionHalf == enhancement.actionHalf && $0.actionIndex == enhancement.actionIndex && $0.slotIndex == enhancement.slotIndex }
    }

    /// Count of enhancements on a specific card.
    static func enhancementCount(on cardId: Int, in enhancements: [Enhancement]) -> Int {
        enhancements.filter { $0.cardId == cardId }.count
    }

    /// Get enhancement applied to a specific slot.
    static func enhancement(on cardId: Int, half: String, actionIndex: Int, slotIndex: Int, in enhancements: [Enhancement]) -> Enhancement? {
        enhancements.first {
            $0.cardId == cardId && $0.actionHalf == half && $0.actionIndex == actionIndex && $0.slotIndex == slotIndex
        }
    }
}
