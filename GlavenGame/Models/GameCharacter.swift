import Foundation

@Observable
final class GameCharacter: Figure, Entity {
    // Figure protocol
    let name: String
    let edition: String
    var level: Int
    var off: Bool = false
    var active: Bool = false
    var figureType: FigureType { .character }

    // Entity protocol
    var number: Int = 1
    var health: Int
    var maxHealth: Int
    var entityConditions: [EntityCondition] = []
    var immunities: [ConditionName] = []
    var markers: [String] = []
    var tags: [String] = []
    var shield: ActionModel?
    var shieldPersistent: ActionModel?
    var retaliate: [ActionModel] = []
    var retaliatePersistent: [ActionModel] = []

    // Character-specific
    var id: String { "\(edition)-\(name)" }
    var title: String = ""
    var initiative: Int = 0
    var experience: Int = 0
    var loot: Int = 0
    var lootCards: [Int] = []
    var exhausted: Bool = false
    var absent: Bool = false
    var longRest: Bool = false
    var identity: Int = 0
    var token: Int = 0
    var tokenValues: [Int] = []
    var attackModifierDeck: AttackModifierDeck = .defaultDeck()
    var summons: [GameSummon] = []
    var selectedPerks: [Int] = []

    // Battle goal state
    var battleGoalCardIds: [String] = []
    var selectedBattleGoal: Int? = nil

    // Items: stored as "edition-id" keys
    var items: [String] = []

    // Character sheet
    var notes: String = ""
    var battleGoalProgress: Int = 0

    // Personal quest
    var personalQuest: String? = nil  // cardId
    var personalQuestProgress: [Int] = []
    var retired: Bool = false

    // Hand management (ability card IDs)
    var handCards: [Int] = []       // Cards currently in hand
    var discardedCards: [Int] = []  // Cards in discard pile (recoverable)
    var lostCards: [Int] = []       // Cards permanently lost this scenario

    // Character-level resources (FH: lumber, metal, hide, herbs)
    var resources: [String: Int] = [:]

    // Card enhancements
    var enhancements: [Enhancement] = []

    // Reference to static data
    var characterData: CharacterData?

    var effectiveInitiative: Double {
        if absent { return 200 }
        if exhausted || health <= 0 { return 100 }
        if longRest { return 99.0 }
        return Double(initiative) - 0.9
    }

    var color: String {
        characterData?.color ?? "#808080"
    }

    var handSize: Int {
        characterData?.resolvedHandSize ?? 10
    }

    init(name: String, edition: String, level: Int, characterData: CharacterData?) {
        self.name = name
        self.edition = edition
        self.level = level
        self.characterData = characterData
        let hp = characterData?.healthForLevel(level) ?? 10
        self.health = hp
        self.maxHealth = hp
    }

    // MARK: - XP / Level

    static let xpThresholds = [0, 45, 95, 150, 210, 275, 345, 420, 500]

    static func levelForXP(_ xp: Int) -> Int {
        for i in stride(from: xpThresholds.count - 1, through: 0, by: -1) {
            if xp >= xpThresholds[i] { return i + 1 }
        }
        return 1
    }

    func updateStatsForLevel() {
        guard let data = characterData else { return }
        let hp = data.healthForLevel(level)
        maxHealth = hp
        health = min(health, hp)
    }
}
