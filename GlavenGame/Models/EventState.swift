import Foundation

/// The campaign's city and road event decks and what their events leave for the next scenario.
struct EventState: Codable, Equatable {
    /// Card ids from the top of the deck down; nil until the deck is first used (it then starts as
    /// cards 01–30, shuffled).
    var cityDeck: [String]?
    var roadDeck: [String]?
    /// A city event is resolved each time the party is back in Gloomhaven, before they set out.
    var cityEventDue = false
    /// Effects of road and city events that apply as the next scenario starts.
    var nextScenario = ScenarioStartEffects()

    static let startingCards = (1...30).map { String(format: "%02d", $0) }

    /// A deck, top card first, starting it (cards 01–30, shuffled) on first use.
    mutating func cards(_ deck: String) -> [String] {
        switch deck {
        case "city":
            if cityDeck == nil { cityDeck = Self.startingCards.shuffled(using: &GameRandom.shared) }
            return cityDeck ?? []
        default:
            if roadDeck == nil { roadDeck = Self.startingCards.shuffled(using: &GameRandom.shared) }
            return roadDeck ?? []
        }
    }

    mutating func setCards(_ deck: String, _ cards: [String]) {
        if deck == "city" { cityDeck = cards } else { roadDeck = cards }
    }

    /// Shuffle a card into a deck (an event's or a scenario's "add event").
    mutating func add(_ id: String, to deck: String) {
        var current = cards(deck)
        guard !current.contains(id) else { return }
        current.append(id)
        setCards(deck, current.shuffled(using: &GameRandom.shared))
    }
}

/// What every character starts the next scenario with, from events (GH p.38): damage, conditions,
/// extra −1 cards, and cards already in the discard pile.
struct ScenarioStartEffects: Codable, Equatable {
    var damage = 0
    var conditions: [ConditionName] = []
    /// Character id → extra −1 cards in their attack modifier deck.
    var minusOneCards: [String: Int] = [:]
    /// Character id → the ability cards they start with in their discard pile.
    var discards: [String: [Int]] = [:]

    var isEmpty: Bool { self == ScenarioStartEffects() }
}
