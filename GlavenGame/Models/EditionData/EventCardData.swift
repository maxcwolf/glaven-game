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

struct EventOption: Codable, Hashable {
    var label: String?
    var narrative: String?
    var returnToDeck: Bool?
    var outcomes: [EventOutcome]?
}

struct EventOutcome: Codable, Hashable {
    var narrative: String?
    var effects: [EventEffect]?
    var condition: EventCondition?
}

struct EventEffect: Codable, Hashable {
    var type: String
    // values can be [Int], [String], or [{EventEffect}] — use AnyCodable-like approach
    // For simplicity, store raw JSON and parse on demand
    var values: [IntOrString]?
    var subEffects: [EventEffect]?

    enum CodingKeys: String, CodingKey {
        case type, values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

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
    }
}

struct EventCondition: Codable, Hashable {
    var type: String?
    var value: IntOrString?
}
