import Foundation

struct Loot: Codable, Hashable, Identifiable {
    var id: String { "\(type.rawValue)-\(cardId)" }
    var type: LootType
    var cardId: Int
    var value4P: Int
    var value3P: Int
    var value2P: Int
    var enhancements: Int

    init(type: LootType, cardId: Int = 0, value4P: Int = 0, value3P: Int = 0,
         value2P: Int = 0, enhancements: Int = 0) {
        self.type = type
        self.cardId = cardId
        self.value4P = value4P
        self.value3P = value3P
        self.value2P = value2P
        self.enhancements = enhancements
    }
}
