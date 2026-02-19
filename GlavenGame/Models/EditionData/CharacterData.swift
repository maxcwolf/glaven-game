import Foundation

struct CharacterData: Codable, Hashable, Identifiable {
    var id: String { "\(edition)-\(name)" }
    var name: String
    var edition: String
    var characterClass: String?
    var gender: String?
    var handSize: IntOrString?
    var color: String?
    var stats: [CharacterStatModel]
    var perks: [PerkModel]?
    var availableSummons: [SummonDataModel]?
    var specialActions: [CharacterSpecialAction]?
    var specialConditions: [ConditionName]?
    var identities: [String]?
    var tokens: [String]?
    var icon: String?
    var marker: Bool?
    var spoiler: Bool?
    var locked: Bool?
    var deck: String?
    var masteries: [String]?
    var traits: [String]?
    var retireEvent: String?
    var unlockEvent: String?

    func healthForLevel(_ level: Int) -> Int {
        stats.first(where: { $0.level == level })?.health ?? stats.last?.health ?? 0
    }

    var resolvedHandSize: Int {
        handSize?.intValue ?? 10
    }
}

struct CharacterSpecialAction: Codable, Hashable {
    var name: String?
    var level: Int?
    var noTag: Bool?
    var expire: Bool?
    var round: Bool?
    var summon: Bool?
    var perk: Int?
}
