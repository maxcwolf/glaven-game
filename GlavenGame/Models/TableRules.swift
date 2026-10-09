import Foundation

/// Variants a group plays by instead of the rulebook, chosen for the campaign. Each is off (the
/// rulebook) by default; the scenario brief lists any that are on.
struct TableRules: Codable, Equatable {
    /// The Enhancer is open from the start, not only after The Power of Enhancement.
    var enhancerFromStart = false
    /// Characters bring every item they own, whatever the slots.
    var bringEveryItem = false
    /// No road event on the way to the campaign's first scenario.
    var noFirstRoadEvent = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enhancerFromStart = try c.decodeIfPresent(Bool.self, forKey: .enhancerFromStart) ?? false
        bringEveryItem = try c.decodeIfPresent(Bool.self, forKey: .bringEveryItem) ?? false
        noFirstRoadEvent = try c.decodeIfPresent(Bool.self, forKey: .noFirstRoadEvent) ?? false
    }

    /// One table rule: what it's called, what the rulebook says instead, and its switch.
    struct Rule: Identifiable {
        let id: String
        let title: String
        let rulebook: String
        let keyPath: WritableKeyPath<TableRules, Bool>
    }

    static let all: [Rule] = [
        Rule(id: "enhancer", title: "Enhancer open from the start",
             rulebook: "By the rulebook it opens once the party wins The Power of Enhancement in Frozen Hollow.",
             keyPath: \.enhancerFromStart),
        Rule(id: "items", title: "Bring every item",
             rulebook: "By the rulebook a character brings one head, body and legs item, two hands' worth, and half their level in small items.",
             keyPath: \.bringEveryItem),
        Rule(id: "road", title: "No road event before the first scenario",
             rulebook: "By the rulebook every scenario reached by road draws a road event, the first one too.",
             keyPath: \.noFirstRoadEvent),
    ]

    /// The table rules in play, by title, for the scenario brief.
    var inPlay: [String] { Self.all.filter { self[keyPath: $0.keyPath] }.map(\.title) }
}
