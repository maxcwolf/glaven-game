import Foundation

@Observable
final class GameSummon: Entity {
    var id: String { uuid.uuidString }
    let uuid: UUID
    var name: String
    var cardId: String
    var number: Int
    var color: SummonColor
    var health: Int
    var maxHealth: Int
    var level: Int
    var attack: IntOrString
    var movement: Int
    var range: Int
    var flying: Bool
    var dead: Bool = false
    var state: SummonState = .new
    var active: Bool = false
    var dormant: Bool = false
    var off: Bool = false

    var entityConditions: [EntityCondition] = []
    var immunities: [ConditionName] = []
    var markers: [String] = []
    var tags: [String] = []
    var shield: ActionModel?
    var shieldPersistent: ActionModel?
    var retaliate: [ActionModel] = []
    var retaliatePersistent: [ActionModel] = []

    var effectiveAttack: Int {
        evaluateEntityValue(attack, level: level)
    }

    init(name: String, cardId: String = "", number: Int = 0, color: SummonColor = .blue,
         health: Int = 0, maxHealth: Int = 0, level: Int = 0,
         attack: IntOrString = .int(0), movement: Int = 0, range: Int = 0, flying: Bool = false) {
        self.uuid = UUID()
        self.name = name
        self.cardId = cardId
        self.number = number
        self.color = color
        self.health = health
        self.maxHealth = maxHealth
        self.level = level
        self.attack = attack
        self.movement = movement
        self.range = range
        self.flying = flying
    }
}
