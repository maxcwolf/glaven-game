import Foundation

struct PerkModel: Codable, Hashable {
    var type: PerkType
    var count: Int
    var cards: [PerkCardModel]?
    var custom: String?

    init(type: PerkType, count: Int = 1, cards: [PerkCardModel]? = nil, custom: String? = nil) {
        self.type = type
        self.count = count
        self.cards = cards
        self.custom = custom
    }
}

struct PerkCardModel: Codable, Hashable {
    var count: Int
    var attackModifier: AttackModifier
}
