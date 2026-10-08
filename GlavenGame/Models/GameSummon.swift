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
    /// Effects added to every attack the summon makes (e.g. Rat Swarm's Poison, Shadow Wolf's Pierce 2).
    var attackEffects: [ActionModel] = []

    var effectiveAttack: Int {
        // Values such as "2 %game.element.fire%" carry an icon after the number.
        if case .string(let raw) = attack, let number = raw.split(separator: " ").first.flatMap({ Int($0) }) {
            return number
        }
        return evaluateEntityValue(attack, level: level)
    }

    init(uuid: UUID = UUID(), name: String, cardId: String = "", number: Int = 0, color: SummonColor = .blue,
         health: Int = 0, maxHealth: Int = 0, level: Int = 0,
         attack: IntOrString = .int(0), movement: Int = 0, range: Int = 0, flying: Bool = false) {
        self.uuid = uuid
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
