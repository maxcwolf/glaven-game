import Foundation

/// The campaign's city and road event decks and what their events leave for the next scenario.
struct EventState: Codable, Equatable {
    /// Card ids from the top of the deck down; nil until the deck is first used (it then starts as
    /// cards 01–30, shuffled).
    var cityDeck: [String]?
    var roadDeck: [String]?
    /// A city event is resolved each time the party is back in Gloomhaven, before they set out.
    var cityEventDue = false
    /// Effects of road and city events (and the sanctuary) that apply as the next scenario starts.
    var nextScenario = ScenarioStartEffects()
    /// Gold the party has given the Sanctuary of the Great Oak over the campaign.
    var sanctuaryGold = 0
    /// Characters (by id) who have donated on this visit to town.
    var donatedThisVisit: Set<String> = []
    /// The scenario the party is setting out for while its events are resolved, and the one
    /// whose road event is already resolved: quitting before departure doesn't deal another.
    var departingFor: String?
    var roadEventDoneFor: String?

    static let startingCards = (1...30).map { String(format: "%02d", $0) }

    init() {}

    /// Every field is optional in a save, so saves from before a field existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cityDeck = try c.decodeIfPresent([String].self, forKey: .cityDeck)
        roadDeck = try c.decodeIfPresent([String].self, forKey: .roadDeck)
        cityEventDue = try c.decodeIfPresent(Bool.self, forKey: .cityEventDue) ?? false
        nextScenario = try c.decodeIfPresent(ScenarioStartEffects.self, forKey: .nextScenario) ?? ScenarioStartEffects()
        sanctuaryGold = try c.decodeIfPresent(Int.self, forKey: .sanctuaryGold) ?? 0
        donatedThisVisit = try c.decodeIfPresent(Set<String>.self, forKey: .donatedThisVisit) ?? []
        departingFor = try c.decodeIfPresent(String.self, forKey: .departingFor)
        roadEventDoneFor = try c.decodeIfPresent(String.self, forKey: .roadEventDoneFor)
    }

    /// A deck, top card first, starting it (cards 01–30, shuffled) on first use. Only that first
    /// use writes: views read decks, and a write on every read would re-render them forever.
    mutating func cards(_ deck: String) -> [String] {
        if let cards = peek(deck) { return cards }
        let started = Self.startingCards.shuffled(using: &GameRandom.shared)
        setCards(deck, started)
        return started
    }

    /// A deck as it stands, nil before it's started.
    func peek(_ deck: String) -> [String]? {
        deck == "city" ? cityDeck : roadDeck
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
    /// Character id → Bless cards added to their deck (a sanctuary donation gives two).
    var blessings: [String: Int] = [:]

    var isEmpty: Bool { self == ScenarioStartEffects() }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        damage = try c.decodeIfPresent(Int.self, forKey: .damage) ?? 0
        conditions = try c.decodeIfPresent([ConditionName].self, forKey: .conditions) ?? []
        minusOneCards = try c.decodeIfPresent([String: Int].self, forKey: .minusOneCards) ?? [:]
        discards = try c.decodeIfPresent([String: [Int]].self, forKey: .discards) ?? [:]
        blessings = try c.decodeIfPresent([String: Int].self, forKey: .blessings) ?? [:]
    }
}
