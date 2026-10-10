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
    /// Position of the current card in `abilities` (the shuffled draw order). Persists across
    /// rounds so each round reveals the next card; reset to -1 when the deck is reshuffled.
    var ability: Int = -1
    var abilities: [Int] = []
    /// Whether an ability card has been drawn for the current round.
    var abilityDrawn: Bool = false
    /// Initiative of the card drawn this round (nil between rounds).
    var drawnInitiative: Int?
    var entities: [GameMonsterEntity] = []
    var isAlly: Bool = false
    var isAllied: Bool = false
    /// A third side: enemies to the characters and to every other monster type (the Sun Demons
    /// of the Sun Temple). Those that stand apart are one another's allies.
    var standsApart: Bool = false
    var tags: [String] = []
    var drawExtra: Bool = false

    // Reference to static data
    var monsterData: MonsterData?

    // Scenario stat-effect overrides (set by ScenarioRulesManager)
    var displayName: String?                        // display/UI name override
    var deckOverride: String?                       // ability deck name override
    var additionalStatActions: [ActionModel] = []   // extra persistent stat actions
    var additionalImmunities: [ConditionName] = []  // extra immunities for all entities
    var statEffectHealthExpr: String?               // health formula for new entities (e.g. "Hx2")
    var statEffectHealthAbsolute: Bool = false      // whether health formula is absolute
    /// X in a stat-effect formula: how many of the figures the rule counts are in play (Temple
    /// of the Elements: altars standing).
    var statEffectX = 0
    /// What a scenario rule adds to the stat card's attack, movement and range.
    var statBonusAttack = 0
    var statBonusMovement = 0
    var statBonusRange = 0

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
        guard var stat = monsterData?.stat(for: type, at: level) else { return nil }
        guard statBonusAttack != 0 || statBonusMovement != 0 || statBonusRange != 0 else { return stat }
        stat.attack = Self.raised(stat.attack, by: statBonusAttack)
        stat.movement = Self.raised(stat.movement, by: statBonusMovement)
        // A melee attack gains no range.
        if let range = stat.range, range != .int(0), range != .string("-") {
            stat.range = Self.raised(range, by: statBonusRange)
        }
        return stat
    }

    /// A stat value with a bonus added: a number, or the expression it is ("1+C") plus the bonus.
    private static func raised(_ value: IntOrString?, by bonus: Int) -> IntOrString? {
        guard bonus != 0 else { return value }
        switch value {
        case nil: return .int(bonus)
        case .int(let n): return .int(n + bonus)
        case .string(let expression):
            if let n = Int(expression) { return .int(n + bonus) }
            return expression == "-" ? .int(bonus) : .string("(\(expression))+\(bonus)")
        }
    }

    /// The stat card used for attacks: including actions a scenario rule added (e.g. "Cave Bears
    /// add Poison to their attacks").
    func attackStat(for type: MonsterType) -> MonsterStatModel? {
        guard var stat = stat(for: type) else { return nil }
        if !additionalStatActions.isEmpty {
            stat.actions = (stat.actions ?? []) + additionalStatActions
        }
        return stat
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
