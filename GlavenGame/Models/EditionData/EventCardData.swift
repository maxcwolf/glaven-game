import Foundation

/// A city or road event card.
struct EventCardData: Codable, Hashable, Identifiable {
    var id: String { "\(edition)-\(type)-\(cardId)" }
    var cardId: String
    var edition: String
    var type: String  // "city" or "road"
    var narrative: String?
    var options: [EventOption]?

    enum CodingKeys: String, CodingKey {
        case cardId, edition, type, narrative, options
    }
}

/// Event text uses HTML line breaks ("…a piece of parchment.<br><br>Something for sirs…");
/// they're read as paragraph breaks.
func eventText(_ raw: String?) -> String? {
    raw?.replacingOccurrences(of: "<br>", with: "\n")
}

extension EventCardData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardId = try c.decode(String.self, forKey: .cardId)
        edition = try c.decode(String.self, forKey: .edition)
        type = try c.decode(String.self, forKey: .type)
        narrative = eventText(try c.decodeIfPresent(String.self, forKey: .narrative))
        options = try c.decodeIfPresent([EventOption].self, forKey: .options)
    }
}

extension EventOption {
    enum CodingKeys: String, CodingKey { case label, narrative, returnToDeck, removeFromDeck, outcomes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        narrative = eventText(try c.decodeIfPresent(String.self, forKey: .narrative))
        returnToDeck = try c.decodeIfPresent(Bool.self, forKey: .returnToDeck)
        removeFromDeck = try c.decodeIfPresent(Bool.self, forKey: .removeFromDeck)
        outcomes = try c.decodeIfPresent([EventOutcome].self, forKey: .outcomes)
    }
}

extension EventOutcome {
    enum CodingKeys: String, CodingKey { case narrative, effects, condition, returnToDeck, removeFromDeck }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        narrative = eventText(try c.decodeIfPresent(String.self, forKey: .narrative))
        effects = try c.decodeIfPresent([EventEffect].self, forKey: .effects)
        condition = try c.decodeIfPresent(EventCondition.self, forKey: .condition)
        returnToDeck = try c.decodeIfPresent(Bool.self, forKey: .returnToDeck)
        removeFromDeck = try c.decodeIfPresent(Bool.self, forKey: .removeFromDeck)
    }
}

struct EventOption: Codable, Hashable {
    var label: String?
    var narrative: String?
    var returnToDeck: Bool?
    var removeFromDeck: Bool?
    var outcomes: [EventOutcome]?
}

struct EventOutcome: Codable, Hashable {
    var narrative: String?
    var effects: [EventEffect]?
    var condition: EventCondition?
    var returnToDeck: Bool?
    var removeFromDeck: Bool?
}

struct EventEffect: Codable, Hashable {
    var type: String
    // values can be [Int], [String], or [{EventEffect}] — use AnyCodable-like approach
    // For simplicity, store raw JSON and parse on demand
    var values: [IntOrString]?
    var subEffects: [EventEffect]?
    /// Some effects only apply when a condition holds ("+5 gold if reputation is below -4").
    var condition: EventCondition?

    enum CodingKeys: String, CodingKey {
        case type, values, condition
    }

    init(type: String, values: [IntOrString]? = nil, subEffects: [EventEffect]? = nil, condition: EventCondition? = nil) {
        self.type = type; self.values = values; self.subEffects = subEffects; self.condition = condition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        condition = try container.decodeIfPresent(EventCondition.self, forKey: .condition)

        // Try decoding values as [IntOrString] first, fall back to [EventEffect]
        if let intValues = try? container.decode([IntOrString].self, forKey: .values) {
            values = intValues
            subEffects = nil
        } else if let effectValues = try? container.decode([EventEffect].self, forKey: .values) {
            values = nil
            subEffects = effectValues
        } else {
            values = nil
            subEffects = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let values = values {
            try container.encode(values, forKey: .values)
        } else if let subEffects = subEffects {
            try container.encode(subEffects, forKey: .values)
        }
        try container.encodeIfPresent(condition, forKey: .condition)
    }
}

/// When an outcome (or an effect) applies: "otherwise", a class in the party, a reputation, or
/// a price the party can pay. A condition can carry a cost paid when it holds ("effect").
struct EventCondition: Codable, Hashable {
    var type: String
    var values: [IntOrString]?
    /// Alternatives, for "payCollectiveGoldConditional" (the price depends on reputation).
    var alternatives: [EventCondition]?
    /// A cost paid when the condition holds (0 or 1 effect; an array so the types can nest).
    var effects: [EventEffect] = []

    enum CodingKeys: String, CodingKey { case type, values, effect }

    init(type: String, values: [IntOrString]? = nil, alternatives: [EventCondition]? = nil, effects: [EventEffect] = []) {
        self.type = type; self.values = values; self.alternatives = alternatives; self.effects = effects
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        if let plain = try? c.decode([IntOrString].self, forKey: .values) {
            values = plain
        } else {
            alternatives = try? c.decode([EventCondition].self, forKey: .values)
        }
        if let effect = try c.decodeIfPresent(EventEffect.self, forKey: .effect) { effects = [effect] }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        if let values { try c.encode(values, forKey: .values) } else { try c.encodeIfPresent(alternatives, forKey: .values) }
        try c.encodeIfPresent(effects.first, forKey: .effect)
    }
}
