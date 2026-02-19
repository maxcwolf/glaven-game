import Foundation

// MARK: - Top-Level Game Snapshot

struct GameSnapshot: Codable {
    var edition: String?
    var conditions: [ConditionName]
    var figures: [FigureSnapshot]
    var state: GamePhase
    var round: Int
    var level: Int
    var levelCalculation: Bool
    var levelAdjustment: Int
    var bonusAdjustment: Int
    var ge5Player: Bool
    var playerCount: Int
    var solo: Bool
    var playSeconds: Int
    var totalSeconds: Int
    var elementBoard: [ElementModel]
    var monsterAttackModifierDeck: AttackModifierDeck
    var allyAttackModifierDeck: AttackModifierDeck
    var lootDeck: LootDeck
    var partyName: String
    var partyReputation: Int
    var partyProsperity: Int
    var scenario: ScenarioSnapshot?
    var completedScenarios: Set<String>
    var manualScenarios: Set<String>
    var globalAchievements: Set<String>
    var partyAchievements: Set<String>
    var campaignStickers: Set<String>
    var lootedTreasures: Set<String>
    var retiredCharacters: [CharacterSnapshot]
    var campaignLog: [CampaignLogEntry]
    var unlockedCharacters: Set<String>
    var unlockedItems: Set<String>
    var boardSnapshot: BoardSnapshot?

    init(edition: String?, conditions: [ConditionName], figures: [FigureSnapshot],
         state: GamePhase, round: Int, level: Int, levelCalculation: Bool,
         levelAdjustment: Int, bonusAdjustment: Int, ge5Player: Bool, playerCount: Int,
         solo: Bool, playSeconds: Int, totalSeconds: Int, elementBoard: [ElementModel],
         monsterAttackModifierDeck: AttackModifierDeck, allyAttackModifierDeck: AttackModifierDeck,
         lootDeck: LootDeck, partyName: String, partyReputation: Int, partyProsperity: Int,
         scenario: ScenarioSnapshot?, completedScenarios: Set<String>,
         manualScenarios: Set<String> = [],
         globalAchievements: Set<String>, partyAchievements: Set<String>,
         campaignStickers: Set<String>, lootedTreasures: Set<String> = [],
         retiredCharacters: [CharacterSnapshot] = [], campaignLog: [CampaignLogEntry] = [],
         unlockedCharacters: Set<String> = [],
         unlockedItems: Set<String> = [],
         boardSnapshot: BoardSnapshot? = nil) {
        self.edition = edition; self.conditions = conditions; self.figures = figures
        self.state = state; self.round = round; self.level = level
        self.levelCalculation = levelCalculation; self.levelAdjustment = levelAdjustment
        self.bonusAdjustment = bonusAdjustment; self.ge5Player = ge5Player
        self.playerCount = playerCount; self.solo = solo
        self.playSeconds = playSeconds; self.totalSeconds = totalSeconds
        self.elementBoard = elementBoard
        self.monsterAttackModifierDeck = monsterAttackModifierDeck
        self.allyAttackModifierDeck = allyAttackModifierDeck
        self.lootDeck = lootDeck; self.partyName = partyName
        self.partyReputation = partyReputation; self.partyProsperity = partyProsperity
        self.scenario = scenario; self.completedScenarios = completedScenarios
        self.manualScenarios = manualScenarios
        self.globalAchievements = globalAchievements; self.partyAchievements = partyAchievements
        self.campaignStickers = campaignStickers; self.lootedTreasures = lootedTreasures
        self.retiredCharacters = retiredCharacters; self.campaignLog = campaignLog
        self.unlockedCharacters = unlockedCharacters
        self.unlockedItems = unlockedItems
        self.boardSnapshot = boardSnapshot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        edition = try c.decodeIfPresent(String.self, forKey: .edition)
        conditions = try c.decode([ConditionName].self, forKey: .conditions)
        figures = try c.decode([FigureSnapshot].self, forKey: .figures)
        state = try c.decode(GamePhase.self, forKey: .state)
        round = try c.decode(Int.self, forKey: .round)
        level = try c.decode(Int.self, forKey: .level)
        levelCalculation = try c.decode(Bool.self, forKey: .levelCalculation)
        levelAdjustment = try c.decode(Int.self, forKey: .levelAdjustment)
        bonusAdjustment = try c.decode(Int.self, forKey: .bonusAdjustment)
        ge5Player = try c.decode(Bool.self, forKey: .ge5Player)
        playerCount = try c.decode(Int.self, forKey: .playerCount)
        solo = try c.decode(Bool.self, forKey: .solo)
        playSeconds = try c.decode(Int.self, forKey: .playSeconds)
        totalSeconds = try c.decode(Int.self, forKey: .totalSeconds)
        elementBoard = try c.decode([ElementModel].self, forKey: .elementBoard)
        monsterAttackModifierDeck = try c.decode(AttackModifierDeck.self, forKey: .monsterAttackModifierDeck)
        allyAttackModifierDeck = try c.decode(AttackModifierDeck.self, forKey: .allyAttackModifierDeck)
        lootDeck = try c.decode(LootDeck.self, forKey: .lootDeck)
        partyName = try c.decode(String.self, forKey: .partyName)
        partyReputation = try c.decode(Int.self, forKey: .partyReputation)
        partyProsperity = try c.decode(Int.self, forKey: .partyProsperity)
        scenario = try c.decodeIfPresent(ScenarioSnapshot.self, forKey: .scenario)
        completedScenarios = try c.decode(Set<String>.self, forKey: .completedScenarios)
        manualScenarios = try c.decodeIfPresent(Set<String>.self, forKey: .manualScenarios) ?? []
        globalAchievements = try c.decode(Set<String>.self, forKey: .globalAchievements)
        partyAchievements = try c.decode(Set<String>.self, forKey: .partyAchievements)
        campaignStickers = try c.decode(Set<String>.self, forKey: .campaignStickers)
        lootedTreasures = try c.decodeIfPresent(Set<String>.self, forKey: .lootedTreasures) ?? []
        retiredCharacters = try c.decodeIfPresent([CharacterSnapshot].self, forKey: .retiredCharacters) ?? []
        campaignLog = try c.decodeIfPresent([CampaignLogEntry].self, forKey: .campaignLog) ?? []
        unlockedCharacters = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedCharacters) ?? []
        unlockedItems = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedItems) ?? []
        boardSnapshot = try c.decodeIfPresent(BoardSnapshot.self, forKey: .boardSnapshot)
    }
}

// MARK: - Figure Snapshot (enum wrapping character/monster/objective)

enum FigureSnapshot: Codable {
    case character(CharacterSnapshot)
    case monster(MonsterSnapshot)
    case objective(ObjectiveContainerSnapshot)

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    private enum FigureSnapshotType: String, Codable {
        case character, monster, objective
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .character(let c):
            try container.encode(FigureSnapshotType.character, forKey: .type)
            try container.encode(c, forKey: .data)
        case .monster(let m):
            try container.encode(FigureSnapshotType.monster, forKey: .type)
            try container.encode(m, forKey: .data)
        case .objective(let o):
            try container.encode(FigureSnapshotType.objective, forKey: .type)
            try container.encode(o, forKey: .data)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(FigureSnapshotType.self, forKey: .type)
        switch type {
        case .character:
            self = .character(try container.decode(CharacterSnapshot.self, forKey: .data))
        case .monster:
            self = .monster(try container.decode(MonsterSnapshot.self, forKey: .data))
        case .objective:
            self = .objective(try container.decode(ObjectiveContainerSnapshot.self, forKey: .data))
        }
    }
}

// MARK: - Character Snapshot

struct CharacterSnapshot: Codable {
    var name: String
    var edition: String
    var level: Int
    var off: Bool
    var active: Bool
    var number: Int
    var health: Int
    var maxHealth: Int
    var entityConditions: [EntityCondition]
    var immunities: [ConditionName]
    var markers: [String]
    var tags: [String]
    var shield: ActionModel?
    var shieldPersistent: ActionModel?
    var retaliate: [ActionModel]
    var retaliatePersistent: [ActionModel]
    var title: String
    var initiative: Int
    var experience: Int
    var loot: Int
    var lootCards: [Int]
    var exhausted: Bool
    var absent: Bool
    var longRest: Bool
    var identity: Int
    var token: Int
    var tokenValues: [Int]
    var attackModifierDeck: AttackModifierDeck
    var summons: [SummonSnapshot]
    var selectedPerks: [Int]
    var battleGoalCardIds: [String]
    var selectedBattleGoal: Int?
    var items: [String]
    var notes: String
    var battleGoalProgress: Int
    var personalQuest: String?
    var personalQuestProgress: [Int]
    var retired: Bool
    var handCards: [Int]
    var discardedCards: [Int]
    var lostCards: [Int]
    var resources: [String: Int]
    var enhancements: [Enhancement]

    init(name: String, edition: String, level: Int, off: Bool, active: Bool,
         number: Int, health: Int, maxHealth: Int,
         entityConditions: [EntityCondition], immunities: [ConditionName],
         markers: [String], tags: [String],
         shield: ActionModel?, shieldPersistent: ActionModel?,
         retaliate: [ActionModel], retaliatePersistent: [ActionModel],
         title: String, initiative: Int, experience: Int,
         loot: Int, lootCards: [Int],
         exhausted: Bool, absent: Bool, longRest: Bool,
         identity: Int, token: Int, tokenValues: [Int],
         attackModifierDeck: AttackModifierDeck, summons: [SummonSnapshot],
         selectedPerks: [Int] = [], battleGoalCardIds: [String] = [],
         selectedBattleGoal: Int? = nil, items: [String] = [],
         notes: String = "", battleGoalProgress: Int = 0,
         personalQuest: String? = nil, personalQuestProgress: [Int] = [],
         retired: Bool = false,
         handCards: [Int] = [], discardedCards: [Int] = [], lostCards: [Int] = [],
         resources: [String: Int] = [:], enhancements: [Enhancement] = []) {
        self.name = name; self.edition = edition; self.level = level
        self.off = off; self.active = active; self.number = number
        self.health = health; self.maxHealth = maxHealth
        self.entityConditions = entityConditions; self.immunities = immunities
        self.markers = markers; self.tags = tags
        self.shield = shield; self.shieldPersistent = shieldPersistent
        self.retaliate = retaliate; self.retaliatePersistent = retaliatePersistent
        self.title = title; self.initiative = initiative; self.experience = experience
        self.loot = loot; self.lootCards = lootCards
        self.exhausted = exhausted; self.absent = absent; self.longRest = longRest
        self.identity = identity; self.token = token; self.tokenValues = tokenValues
        self.attackModifierDeck = attackModifierDeck; self.summons = summons
        self.selectedPerks = selectedPerks
        self.battleGoalCardIds = battleGoalCardIds
        self.selectedBattleGoal = selectedBattleGoal
        self.items = items
        self.notes = notes
        self.battleGoalProgress = battleGoalProgress
        self.personalQuest = personalQuest
        self.personalQuestProgress = personalQuestProgress
        self.retired = retired
        self.handCards = handCards
        self.discardedCards = discardedCards
        self.lostCards = lostCards
        self.resources = resources
        self.enhancements = enhancements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        edition = try container.decode(String.self, forKey: .edition)
        level = try container.decode(Int.self, forKey: .level)
        off = try container.decode(Bool.self, forKey: .off)
        active = try container.decode(Bool.self, forKey: .active)
        number = try container.decode(Int.self, forKey: .number)
        health = try container.decode(Int.self, forKey: .health)
        maxHealth = try container.decode(Int.self, forKey: .maxHealth)
        entityConditions = try container.decode([EntityCondition].self, forKey: .entityConditions)
        immunities = try container.decode([ConditionName].self, forKey: .immunities)
        markers = try container.decode([String].self, forKey: .markers)
        tags = try container.decode([String].self, forKey: .tags)
        shield = try container.decodeIfPresent(ActionModel.self, forKey: .shield)
        shieldPersistent = try container.decodeIfPresent(ActionModel.self, forKey: .shieldPersistent)
        retaliate = try container.decode([ActionModel].self, forKey: .retaliate)
        retaliatePersistent = try container.decode([ActionModel].self, forKey: .retaliatePersistent)
        title = try container.decode(String.self, forKey: .title)
        initiative = try container.decode(Int.self, forKey: .initiative)
        experience = try container.decode(Int.self, forKey: .experience)
        loot = try container.decode(Int.self, forKey: .loot)
        lootCards = try container.decode([Int].self, forKey: .lootCards)
        exhausted = try container.decode(Bool.self, forKey: .exhausted)
        absent = try container.decode(Bool.self, forKey: .absent)
        longRest = try container.decode(Bool.self, forKey: .longRest)
        identity = try container.decode(Int.self, forKey: .identity)
        token = try container.decode(Int.self, forKey: .token)
        tokenValues = try container.decode([Int].self, forKey: .tokenValues)
        attackModifierDeck = try container.decode(AttackModifierDeck.self, forKey: .attackModifierDeck)
        summons = try container.decode([SummonSnapshot].self, forKey: .summons)
        selectedPerks = try container.decodeIfPresent([Int].self, forKey: .selectedPerks) ?? []
        battleGoalCardIds = try container.decodeIfPresent([String].self, forKey: .battleGoalCardIds) ?? []
        selectedBattleGoal = try container.decodeIfPresent(Int.self, forKey: .selectedBattleGoal)
        items = try container.decodeIfPresent([String].self, forKey: .items) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        battleGoalProgress = try container.decodeIfPresent(Int.self, forKey: .battleGoalProgress) ?? 0
        personalQuest = try container.decodeIfPresent(String.self, forKey: .personalQuest)
        personalQuestProgress = try container.decodeIfPresent([Int].self, forKey: .personalQuestProgress) ?? []
        retired = try container.decodeIfPresent(Bool.self, forKey: .retired) ?? false
        handCards = try container.decodeIfPresent([Int].self, forKey: .handCards) ?? []
        discardedCards = try container.decodeIfPresent([Int].self, forKey: .discardedCards) ?? []
        lostCards = try container.decodeIfPresent([Int].self, forKey: .lostCards) ?? []
        resources = try container.decodeIfPresent([String: Int].self, forKey: .resources) ?? [:]
        enhancements = try container.decodeIfPresent([Enhancement].self, forKey: .enhancements) ?? []
    }
}

// MARK: - Monster Snapshot

struct MonsterSnapshot: Codable {
    var name: String
    var edition: String
    var level: Int
    var off: Bool
    var active: Bool
    var ability: Int
    var abilities: [Int]
    var entities: [MonsterEntitySnapshot]
    var isAlly: Bool
    var isAllied: Bool
    var tags: [String]
    var drawExtra: Bool
}

// MARK: - Monster Entity Snapshot

struct MonsterEntitySnapshot: Codable {
    var number: Int
    var type: MonsterType
    var health: Int
    var maxHealth: Int
    var level: Int
    var dead: Bool
    var dormant: Bool
    var revealed: Bool
    var active: Bool
    var off: Bool
    var summonState: SummonState?
    var entityConditions: [EntityCondition]
    var immunities: [ConditionName]
    var markers: [String]
    var tags: [String]
    var shield: ActionModel?
    var shieldPersistent: ActionModel?
    var retaliate: [ActionModel]
    var retaliatePersistent: [ActionModel]
}

// MARK: - Objective Container Snapshot

struct ObjectiveContainerSnapshot: Codable {
    var uuid: UUID
    var name: String
    var edition: String
    var title: String
    var escort: Bool
    var level: Int
    var off: Bool
    var active: Bool
    var initiative: Int
    var entities: [ObjectiveEntitySnapshot]
}

// MARK: - Objective Entity Snapshot

struct ObjectiveEntitySnapshot: Codable {
    var uuid: UUID
    var number: Int
    var health: Int
    var maxHealth: Int
    var level: Int
    var dead: Bool
    var dormant: Bool
    var active: Bool
    var off: Bool
    var marker: String
    var entityConditions: [EntityCondition]
    var immunities: [ConditionName]
    var markers: [String]
    var tags: [String]
    var shield: ActionModel?
    var shieldPersistent: ActionModel?
    var retaliate: [ActionModel]
    var retaliatePersistent: [ActionModel]
}

// MARK: - Summon Snapshot

struct SummonSnapshot: Codable {
    var uuid: UUID
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
    var dead: Bool
    var state: SummonState
    var active: Bool
    var dormant: Bool
    var off: Bool
    var entityConditions: [EntityCondition]
    var immunities: [ConditionName]
    var markers: [String]
    var tags: [String]
    var shield: ActionModel?
    var shieldPersistent: ActionModel?
    var retaliate: [ActionModel]
    var retaliatePersistent: [ActionModel]
}

// MARK: - Scenario Snapshot

struct ScenarioSnapshot: Codable {
    var edition: String
    var index: String
    var isCustom: Bool
    var revealedRooms: [Int]
    var additionalSections: [String]
    var appliedRules: Set<String>
    var disabledRules: Set<Int>
}
