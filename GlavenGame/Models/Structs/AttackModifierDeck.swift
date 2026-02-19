import Foundation

struct AttackModifierDeck: Codable {
    var attackModifiers: [AttackModifier]
    var cards: [AttackModifier]
    var current: Int
    var discards: [Int]
    var active: Bool
    var state: AdvantageState?

    init(attackModifiers: [AttackModifier] = [], cards: [AttackModifier] = [],
         current: Int = -1, discards: [Int] = [], active: Bool = true,
         state: AdvantageState? = nil) {
        self.attackModifiers = attackModifiers
        self.cards = cards
        self.current = current
        self.discards = discards
        self.active = active
        self.state = state
    }

    static func defaultDeck() -> AttackModifierDeck {
        let mods = AttackModifier.defaultMonsterDeck()
        return AttackModifierDeck(attackModifiers: mods, cards: mods.shuffled())
    }

    var needsShuffle: Bool {
        guard current >= 0, current < cards.count else { return false }
        return cards[0...current].contains(where: { $0.shuffle })
    }

    var currentCard: AttackModifier? {
        guard current >= 0, current < cards.count else { return nil }
        return cards[current]
    }

    var remainingCount: Int {
        cards.count - current - 1
    }

    /// Add a bless/curse card to the deck at a random position after the current draw.
    mutating func addCard(type: AttackModifierType) {
        let card = AttackModifier(id: UUID().uuidString, type: type)
        let insertAt = max(current + 1, 0)
        let position = insertAt < cards.count ? Int.random(in: insertAt...cards.count) : cards.count
        cards.insert(card, at: position)
    }
}

enum AdvantageState: String, Codable {
    case advantage, disadvantage
}
