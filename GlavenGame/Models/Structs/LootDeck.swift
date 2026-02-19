import Foundation

struct LootDeck: Codable {
    var cards: [Loot]
    var current: Int
    var active: Bool

    init(cards: [Loot] = [], current: Int = -1, active: Bool = false) {
        self.cards = cards
        self.current = current
        self.active = active
    }

    var currentCard: Loot? {
        guard current >= 0, current < cards.count else { return nil }
        return cards[current]
    }

    var remainingCount: Int {
        cards.count - current - 1
    }
}
