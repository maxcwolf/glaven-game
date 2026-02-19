import Foundation

struct SummonDataModel: Codable, Hashable {
    var name: String
    var cardId: String?
    var edition: String?
    var health: IntOrString
    var attack: IntOrString?
    var movement: IntOrString?
    var range: IntOrString?
    var flying: Bool?
    var action: ActionModel?
    var additionalAction: ActionModel?
    var level: Int?
    var special: Bool?
    var count: Int?
    var thumbnail: Bool?

    init(name: String, health: IntOrString = .int(0)) {
        self.name = name
        self.health = health
    }
}
