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
        return AttackModifierDeck(attackModifiers: mods, cards: mods.shuffled(using: &GameRandom.shared))
    }

    /// True when a standard ×2 or null card was drawn since the last shuffle, so the deck
    /// must be reshuffled at the end of the round. Bless/Curse never trigger this.
    var needsShuffle: Bool {
        guard current >= 0, current < cards.count else { return false }
        return cards[0...current].contains(where: { $0.shuffle && !$0.type.isSpecial })
    }

    var currentCard: AttackModifier? {
        guard current >= 0, current < cards.count else { return nil }
        return cards[current]
    }

    var remainingCount: Int {
        cards.count - current - 1
    }

    /// Number of not-yet-drawn cards of `type` (drawn Bless/Curse are already removed from play).
    func undrawnCount(of type: AttackModifierType) -> Int {
        guard current + 1 < cards.count else { return 0 }
        return cards[(current + 1)...].filter { $0.type == type }.count
    }

    /// Draw the next card. If the draw pile is empty, the discards are shuffled back in first
    /// (GH: "also do this if a modifier card must be drawn and there are none left").
    mutating func draw() -> AttackModifier? {
        if current + 1 >= cards.count {
            reshuffle()
        }
        guard current + 1 < cards.count else { return nil }
        current += 1
        return cards[current]
    }

    /// Shuffle the discards back into the draw pile. Drawn Bless/Curse cards are removed from
    /// play; undrawn ones stay in the deck.
    mutating func reshuffle() {
        var newCards = attackModifiers.filter { !$0.type.isSpecial }
        if current + 1 < cards.count {
            newCards.append(contentsOf: cards[(current + 1)...].filter { $0.type.isSpecial })
        }
        newCards.shuffle(using: &GameRandom.shared)
        cards = newCards
        current = -1
        discards = []
    }

    /// Shuffle a card into the undrawn part of the deck.
    mutating func insertRandomly(_ card: AttackModifier) {
        let insertAt = max(current + 1, 0)
        let position = insertAt < cards.count ? Int.random(in: insertAt...cards.count, using: &GameRandom.shared) : cards.count
        cards.insert(card, at: position)
    }

    /// After a scenario: remove Bless, Curse and cards added by scenario effects, and shuffle
    /// the deck back to its base composition (GH p.47).
    mutating func removeScenarioCards() {
        attackModifiers.removeAll { $0.type.isSpecial || $0.scenarioAdded }
        cards = attackModifiers.shuffled(using: &GameRandom.shared)
        current = -1
        discards = []
    }

    /// Add a Bless/Curse (or other standard) card to the deck at a random undrawn position.
    /// Bless and Curse are capped at 10 undrawn copies per deck.
    mutating func addCard(type: AttackModifierType) {
        if type == .bless || type == .curse {
            guard undrawnCount(of: type) < 10 else { return }
        }
        var card = AttackModifier.standard(type)
        card.scenarioAdded = true
        // Non-special cards (e.g. scenario -1s) persist through reshuffles for the scenario.
        if !type.isSpecial {
            attackModifiers.append(card)
        }
        insertRandomly(card)
    }
}

enum AdvantageState: String, Codable {
    case advantage, disadvantage
}
