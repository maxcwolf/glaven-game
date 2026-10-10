import Foundation

@Observable
final class EnhancementsManager {
    private let game: GameState
    var onBeforeMutate: (() -> Void)?

    init(game: GameState) {
        self.game = game
    }

    // MARK: - Available Actions for Slot Types

    /// What a slot can take (GH p.47). The data marks each slot with the kind of line it is on:
    /// a square on a line that only takes +1 (Range, a summon's stats), a circle on a main line
    /// (+1 or an element), a diamond on a main line that targets enemies (also a negative
    /// condition), a diamond with a plus on one that affects allies or the character (also
    /// Bless or Strengthen), a hex on an area. Jump goes on any Move line.
    static func availableActions(for slotType: EnhancementSlotType, actionType: ActionType, isSummon: Bool, edition: String) -> [EnhancementAction] {
        // A summon's stat line takes +1 and nothing else.
        if isSummon { return [.plus1] }
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
            actions.append(contentsOf: elementActions)
        case .diamond_plus:
            actions.append(.plus1)
            actions.append(contentsOf: positiveConditions(edition: edition))
            actions.append(contentsOf: elementActions)
        case .hex:
            actions.append(.hex)
        case .any:
            actions.append(.plus1)
            actions.append(contentsOf: elementActions)
            actions.append(contentsOf: negativeConditions(edition: edition))
            actions.append(contentsOf: positiveConditions(edition: edition))
            actions.append(.hex)
        }
        if actionType == .move, slotType != .hex {
            actions.append(.jump)
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
        // Gloomhaven's Enhancer sells Strengthen and Bless; Regenerate and Ward are Frosthaven's.
        var conditions: [EnhancementAction] = [.strengthen, .bless]
        if edition == "fh" {
            conditions.append(contentsOf: [.regenerate, .ward])
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
            return summonBaseCost(for: action, actionType: actionType, isFH: isFH)
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
            case .target: return 50
            default: return isFH ? 30 : 50
            }
        case .jump:
            return isFH ? 35 : 50
        case .hex:
            return isFH ? 80 : 200
        case .poison: return isFH ? 25 : 75
        case .wound: return isFH ? 25 : 75
        case .muddle: return isFH ? 25 : 50
        case .immobilize: return isFH ? 50 : 100
        case .disarm: return 150
        case .curse: return isFH ? 50 : 75
        case .bane: return 50
        case .brittle: return 25
        case .impair: return 50
        case .chill: return 25
        case .infect: return 25
        case .rupture: return 25
        case .strengthen: return 50
        case .bless: return 50
        case .regenerate: return isFH ? 25 : 40
        case .ward: return 50
        case .dodge: return 50
        case .empower: return 50
        case .safeguard: return 50
        case .fire, .ice, .air, .earth, .light, .dark: return isFH ? 60 : 100
        case .wild: return isFH ? 100 : 150
        }
    }

    /// A summon's stats (GH p.47): +1 Move or Attack 100, +1 Range or hit points 50. The hit
    /// point line is the summon's `heal` slot in the data.
    private static func summonBaseCost(for action: EnhancementAction, actionType: ActionType, isFH: Bool) -> Int {
        switch action {
        case .plus1:
            if isFH { return 40 }
            return [.range, .heal].contains(actionType) ? 50 : 100
        case .poison, .wound: return isFH ? 30 : 100
        case .muddle: return isFH ? 30 : 75
        case .immobilize: return isFH ? 75 : 200
        case .strengthen: return isFH ? 75 : 150
        case .bless: return isFH ? 75 : 100
        case .regenerate: return isFH ? 30 : 50
        default: return standardBaseCost(for: action, actionType: .attack, isFH: isFH)
        }
    }

    // MARK: - The Enhancer

    /// Why an enhancement can't be bought.
    enum PurchaseProblem: Equatable {
        /// Gloomhaven's Enhancer opens with The Power of Enhancement (Frozen Hollow).
        case locked
        case slotTaken
        /// The board doesn't play it yet (hex areas, any element), so it isn't sold.
        case notPlayable
        /// The class already has as many enhanced cards as the city's prosperity level (GH p.47).
        case cardLimit
        case tooExpensive
    }

    /// The global achievement that opens Gloomhaven's Enhancer (GH p.42).
    static let enhancerAchievement = "the-power-of-enhancement"

    func enhancerOpen(edition: String) -> Bool {
        edition != "gh" || game.tableRules.enhancerFromStart || game.globalAchievements.contains(Self.enhancerAchievement)
    }

    func purchaseProblem(_ enhancement: EnhancementAction, in slot: CardEnhancing.Slot, card: AbilityModel,
                         for character: GameCharacter) -> PurchaseProblem? {
        if !enhancerOpen(edition: character.edition) { return .locked }
        if Self.enhancement(on: slot.cardId, half: slot.half, actionIndex: slot.actionIndex,
                            slotIndex: slot.slotIndex, in: character.enhancements) != nil { return .slotTaken }
        if !CardEnhancing.options(for: slot, edition: character.edition).contains(enhancement) { return .notPlayable }
        if !canEnhanceAnotherCard(slot.cardId, for: character) { return .cardLimit }
        let cost = CardEnhancing.cost(enhancement, in: slot, card: card, enhancements: character.enhancements,
                                      edition: character.edition)
        if character.loot < cost { return .tooExpensive }
        return nil
    }

    /// The cards of the character's class that carry an enhancement: every card of the class
    /// counts, whoever had it enhanced (FAQ).
    static func enhancedCards(of character: GameCharacter) -> Set<Int> {
        Set(character.enhancements.map(\.cardId))
    }

    /// Whether the card may take an enhancement: Gloomhaven allows a class as many enhanced
    /// cards as the city's prosperity level (GH p.47); a card already enhanced may take more.
    func canEnhanceAnotherCard(_ cardId: Int, for character: GameCharacter) -> Bool {
        guard character.edition == "gh" else { return true }
        let enhanced = Self.enhancedCards(of: character)
        return enhanced.contains(cardId) || enhanced.count < game.prosperityLevel
    }

    /// Buy an enhancement for one of the character's cards: it stays on the card for good, and
    /// costs its price in the character's gold. Returns whether it was bought.
    @discardableResult
    func buy(_ enhancement: EnhancementAction, in slot: CardEnhancing.Slot, card: AbilityModel,
             for character: GameCharacter) -> Bool {
        guard purchaseProblem(enhancement, in: slot, card: card, for: character) == nil else { return false }
        let cost = CardEnhancing.cost(enhancement, in: slot, card: card, enhancements: character.enhancements,
                                      edition: character.edition)
        onBeforeMutate?()
        character.loot -= cost
        character.enhancements.append(Enhancement(cardId: slot.cardId, actionHalf: slot.half,
                                                  actionIndex: slot.actionIndex, slotIndex: slot.slotIndex,
                                                  action: enhancement))
        return true
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

    /// Count of enhancements on one action of a card — its top or its bottom half. Each one
    /// makes the next on that action dearer (GH p.47); the other half's don't.
    static func enhancementCount(on cardId: Int, half: String, in enhancements: [Enhancement]) -> Int {
        enhancements.filter { $0.cardId == cardId && $0.actionHalf == half }.count
    }

    /// Get enhancement applied to a specific slot.
    static func enhancement(on cardId: Int, half: String, actionIndex: Int, slotIndex: Int, in enhancements: [Enhancement]) -> Enhancement? {
        enhancements.first {
            $0.cardId == cardId && $0.actionHalf == half && $0.actionIndex == actionIndex && $0.slotIndex == slotIndex
        }
    }
}
