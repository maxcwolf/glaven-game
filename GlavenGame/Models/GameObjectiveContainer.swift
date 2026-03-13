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
    /// Actions this escort performs each turn (move, attack, etc.) — parsed from scenario JSON.
    var escortActions: [ActionModel] = []
    /// Whether this escort uses the ally attack modifier deck instead of the monster deck.
    var useAllyDeck: Bool = false

    var figureType: FigureType { .objectiveContainer }

    var effectiveInitiative: Double {
        Double(initiative) - 0.5
    }

    /// Extract move value from escort actions.
    var escortMove: Int {
        escortActions.first(where: { $0.type == .move })?.value?.intValue ?? 0
    }

    /// Extract attack value from escort actions.
    var escortAttack: Int {
        escortActions.first(where: { $0.type == .attack })?.value?.intValue ?? 0
    }

    /// Extract attack range from escort actions (melee = 0 unless range sub-action present).
    var escortRange: Int {
        guard let attackAction = escortActions.first(where: { $0.type == .attack }) else { return 0 }
        if let rangeSub = attackAction.subActions?.first(where: { $0.type == .range }) {
            return rangeSub.value?.intValue ?? 0
        }
        return 0
    }

    /// Whether this escort has any actions to execute (some escorts are passive — no move/attack).
    var hasEscortActions: Bool {
        !escortActions.isEmpty && (escortMove > 0 || escortAttack > 0)
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
