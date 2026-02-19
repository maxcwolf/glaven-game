import Foundation

struct AbilityModel: Codable, Hashable, Identifiable {
    var id: Int { cardId ?? 0 }
    var cardId: Int?
    var name: String?
    var initiative: Int
    var level: IntOrString?
    var shuffle: Bool?
    var actions: [ActionModel]?
    var bottomActions: [ActionModel]?
    var lost: Bool?
    var persistent: Bool?
    var round: Bool?
    var xp: Int?
    var bottomLost: Bool?
    var bottomShuffle: Bool?

    init(cardId: Int? = nil, name: String? = nil, initiative: Int = 0,
         level: IntOrString? = nil, shuffle: Bool? = nil,
         actions: [ActionModel]? = nil, bottomActions: [ActionModel]? = nil) {
        self.cardId = cardId
        self.name = name
        self.initiative = initiative
        self.level = level
        self.shuffle = shuffle
        self.actions = actions
        self.bottomActions = bottomActions
    }
}
