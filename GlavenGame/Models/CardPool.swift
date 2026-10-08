import Foundation

/// A character's ability cards between scenarios (GH p.44): every level 1 and X card of the class,
/// plus one card the player chose for each level gained above 1, of that level or lower. Before a
/// scenario they bring a hand of cards from this pool, up to their hand size.
enum CardPool {

    /// The card's level, or nil for an X card.
    static func level(of card: AbilityModel) -> Int? {
        if case .string(let text) = card.level, text.uppercased() == "X" { return nil }
        return card.level?.intValue
    }

    static func isStarting(_ card: AbilityModel) -> Bool {
        level(of: card).map { $0 <= 1 } ?? true
    }

    /// The cards the character can take into a scenario.
    static func pool(_ abilities: [AbilityModel], chosen: [Int]) -> [AbilityModel] {
        abilities.filter { card in
            guard let id = card.cardId else { return false }
            return isStarting(card) || chosen.contains(id)
        }
    }

    /// How many level-up cards the character still has to choose.
    static func pendingChoices(level: Int, chosen: [Int]) -> Int {
        max(0, level - 1 - chosen.count)
    }

    /// The cards the character can choose now: above level 1, at or below their level, not yet
    /// chosen.
    static func choosable(_ abilities: [AbilityModel], level characterLevel: Int, chosen: [Int]) -> [AbilityModel] {
        abilities.filter { card in
            guard let id = card.cardId, let cardLevel = level(of: card) else { return false }
            return cardLevel >= 2 && cardLevel <= characterLevel && !chosen.contains(id)
        }
    }

    /// A starting hand from the pool: the level 1 cards first, then X cards, then chosen cards.
    static func defaultHand(_ abilities: [AbilityModel], chosen: [Int], handSize: Int) -> [Int] {
        let pool = pool(abilities, chosen: chosen)
        let ordered = pool.filter { level(of: $0) == 1 } + pool.filter { level(of: $0) == nil }
            + pool.filter { (level(of: $0) ?? 0) >= 2 }
        return Array(ordered.compactMap(\.cardId).prefix(handSize))
    }

    /// For saves made before cards were chosen: the higher-level cards a character already carries
    /// become their chosen cards, as many as their level allows.
    static func adoptedChoices(_ abilities: [AbilityModel], level characterLevel: Int, carried: [Int]) -> [Int] {
        let higher = abilities.filter { card in
            guard let id = card.cardId, let cardLevel = level(of: card) else { return false }
            return cardLevel >= 2 && cardLevel <= characterLevel && carried.contains(id)
        }
        return Array(higher.compactMap(\.cardId).prefix(max(0, characterLevel - 1)))
    }
}
