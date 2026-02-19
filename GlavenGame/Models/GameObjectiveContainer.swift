import Foundation

@Observable
final class GameObjectiveContainer: Figure {
    var id: String { uuid.uuidString }
    let uuid: UUID
    var name: String
    var edition: String
    var title: String
    var escort: Bool
    var level: Int
    var off: Bool = false
    var active: Bool = false
    var initiative: Int = 99
    var entities: [GameObjectiveEntity] = []

    var figureType: FigureType { .objectiveContainer }

    var effectiveInitiative: Double {
        Double(initiative) - 0.5
    }

    init(name: String = "", edition: String = "", title: String = "", escort: Bool = false, level: Int = 0) {
        self.uuid = UUID()
        self.name = name
        self.edition = edition
        self.title = title
        self.escort = escort
        self.level = level
    }
}

@Observable
final class GameObjectiveEntity: Entity {
    var id: String { uuid.uuidString }
    let uuid: UUID
    var number: Int
    var health: Int
    var maxHealth: Int
    var level: Int = -1
    var dead: Bool = false
    var dormant: Bool = false
    var active: Bool = false
    var off: Bool = false
    var marker: String = ""

    var entityConditions: [EntityCondition] = []
    var immunities: [ConditionName] = []
    var markers: [String] = []
    var tags: [String] = []
    var shield: ActionModel?
    var shieldPersistent: ActionModel?
    var retaliate: [ActionModel] = []
    var retaliatePersistent: [ActionModel] = []

    init(number: Int = 0, health: Int = 0, maxHealth: Int = 0) {
        self.uuid = UUID()
        self.number = number
        self.health = health
        self.maxHealth = maxHealth
    }
}
