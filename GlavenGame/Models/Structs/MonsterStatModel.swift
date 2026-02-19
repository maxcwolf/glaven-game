import Foundation

struct MonsterStatModel: Codable, Hashable {
    var type: MonsterType?
    var level: Int?
    var health: IntOrString?
    var movement: IntOrString?
    var attack: IntOrString?
    var range: IntOrString?
    var actions: [ActionModel]?
    var immunities: [ConditionName]?
    var special: [[ActionModel]]?
    var note: String?

    init(type: MonsterType? = nil, level: Int? = 0, health: IntOrString? = .int(0),
         movement: IntOrString? = nil, attack: IntOrString? = nil,
         range: IntOrString? = nil, actions: [ActionModel]? = nil,
         immunities: [ConditionName]? = nil) {
        self.type = type
        self.level = level
        self.health = health
        self.movement = movement
        self.attack = attack
        self.range = range
        self.actions = actions
        self.immunities = immunities
    }

    var resolvedType: MonsterType {
        type ?? .normal
    }
}
