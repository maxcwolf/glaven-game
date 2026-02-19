import Foundation

@Observable
final class GameMonster: Figure {
    // Figure protocol
    let name: String
    let edition: String
    var level: Int
    var off: Bool = false
    var active: Bool = false
    var figureType: FigureType { .monster }

    var id: String { "\(edition)-\(name)" }

    // Monster-specific
    var ability: Int = -1
    var abilities: [Int] = []
    var entities: [GameMonsterEntity] = []
    var isAlly: Bool = false
    var isAllied: Bool = false
    var tags: [String] = []
    var drawExtra: Bool = false

    // Reference to static data
    var monsterData: MonsterData?

    var effectiveInitiative: Double {
        guard ability >= 0, monsterData != nil else { return 100 }
        // Look up ability deck to get initiative from the drawn card
        return Double(currentAbilityInitiative ?? 99)
    }

    var currentAbilityInitiative: Int? {
        // This will be resolved by the manager that has access to deck data
        nil
    }

    var isBoss: Bool {
        monsterData?.isBoss ?? false
    }

    var maxCount: Int {
        monsterData?.maxCount ?? 6
    }

    var aliveEntities: [GameMonsterEntity] {
        entities.filter { !$0.dead }
    }

    var normalEntities: [GameMonsterEntity] {
        entities.filter { $0.type == .normal && !$0.dead }
    }

    var eliteEntities: [GameMonsterEntity] {
        entities.filter { $0.type == .elite && !$0.dead }
    }

    init(name: String, edition: String, level: Int, monsterData: MonsterData?) {
        self.name = name
        self.edition = edition
        self.level = level
        self.monsterData = monsterData
    }

    func stat(for type: MonsterType) -> MonsterStatModel? {
        monsterData?.stat(for: type, at: level)
    }
}

@Observable
final class GameMonsterEntity: Entity {
    var id: String { "\(number)-\(type.rawValue)" }
    var number: Int
    var type: MonsterType
    var health: Int
    var maxHealth: Int
    var level: Int
    var dead: Bool = false
    var dormant: Bool = false
    var revealed: Bool = false
    var active: Bool = false
    var off: Bool = false
    var summonState: SummonState?

    var entityConditions: [EntityCondition] = []
    var immunities: [ConditionName] = []
    var markers: [String] = []
    var tags: [String] = []
    var shield: ActionModel?
    var shieldPersistent: ActionModel?
    var retaliate: [ActionModel] = []
    var retaliatePersistent: [ActionModel] = []

    init(number: Int, type: MonsterType, health: Int, maxHealth: Int, level: Int) {
        self.number = number
        self.type = type
        self.health = health
        self.maxHealth = maxHealth
        self.level = level
    }
}
