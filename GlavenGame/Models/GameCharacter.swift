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
    /// Ability cards chosen on levelling up, one per level above 1 (see `CardPool`).
    var chosenCards: [Int] = []
    /// What they've done over the campaign, for their personal quest.
    var record = CharacterRecord()
    /// The two personal quests dealt on recruiting, until one is kept.
    var questChoices: [String] = []

    // Battle goal state
    var battleGoalCardIds: [String] = []
    var selectedBattleGoal: Int? = nil

    // Items: stored as "edition-id" keys
    var items: [String] = []
    /// Items that have been spent this scenario (flipped down; refreshed on long rest).
    var spentItems: Set<String> = []
    /// Items that have been consumed this scenario (removed until scenario end).
    var consumedItems: Set<String> = []
    /// Use slots marked on items that take several uses before they're spent (Hide Armor).
    var itemSlotsUsed: [String: Int] = [:]

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
    var activeCards: [Int] = []     // Persistent cards in the active area (ongoing effects)
    /// Active-area cards holding a round bonus: they leave the active area at the end of the round.
    var roundBonusCards: [Int] = []
    /// Active-area cards whose used half had the lost icon: they go to the lost pile, not the
    /// discard pile, when they leave the active area.
    var lostWhenRemoved: [Int] = []

    /// Move a card out of the active area to the lost or discard pile, as its icon requires.
    func removeFromActiveArea(_ cardId: Int) {
        activeCards.removeAll { $0 == cardId }
        roundBonusCards.removeAll { $0 == cardId }
        if lostWhenRemoved.contains(cardId) {
            lostWhenRemoved.removeAll { $0 == cardId }
            lostCards.append(cardId)
        } else {
            discardedCards.append(cardId)
        }
    }

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

    // MARK: - Perks

    /// Whether a selected perk carries the given custom rule (e.g. "ignoreNegativeItem").
    func hasCustomPerk(_ key: String) -> Bool {
        guard let perks = characterData?.perks else { return false }
        return perks.indices.contains { index in
            index < selectedPerks.count && selectedPerks[index] > 0
                && (perks[index].custom?.contains(key) ?? false)
        }
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
