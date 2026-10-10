import Foundation

@Observable
final class GameState {
    var edition: String?
    var conditions: [ConditionName] = []
    var figures: [AnyFigure] = []
    var state: GamePhase = .draw
    var round: Int = 0
    var level: Int = 1
    var levelCalculation: Bool = true
    var levelAdjustment: Int = 0
    var difficulty: DifficultyMode = .normal
    var bonusAdjustment: Int = 0
    var ge5Player: Bool = true
    var playerCount: Int = -1
    var solo: Bool = false
    var playSeconds: Int = 0
    var totalSeconds: Int = 0
    var elementBoard: [ElementModel] = ElementModel.defaultBoard()
    /// Told when an element is infused or consumed, so the board can sound it (not saved).
    @ObservationIgnored var onElementChange: ((ElementChange) -> Void)?
    var monsterAttackModifierDeck: AttackModifierDeck = .defaultDeck()
    var allyAttackModifierDeck: AttackModifierDeck = .defaultDeck()
    var lootDeck: LootDeck = LootDeck()
    var partyName: String = ""
    /// Variants this campaign plays by (all off: the rulebook).
    var tableRules = TableRules()
    /// Tips the first time each rule comes up, and "Why?" on what the monsters do: on for a
    /// player's first campaign.
    var learningMode = false
    var partyReputation: Int = 0
    var partyProsperity: Int = 0

    // Scenario
    var scenario: Scenario?

    // Campaign tracking
    var completedScenarios: Set<String> = []    // "{edition}-{index}"
    var manualScenarios: Set<String> = []       // Event-unlocked scenarios "{edition}-{index}"
    var globalAchievements: Set<String> = []
    var partyAchievements: Set<String> = []
    var campaignStickers: Set<String> = []
    /// Visual overlay stickers placed on the world map (from scenario completion rewards).
    var mapOverlays: [WorldMapOverlay] = []

    // Treasures: "{edition}-{scenarioIndex}-{treasureIndex}"
    var lootedTreasures: Set<String> = []

    // Retired characters stored as snapshots
    var retiredCharacters: [CharacterSnapshot] = []

    // Campaign log entries
    var campaignLog: [CampaignLogEntry] = []

    // Unlocked characters: "{edition}-{name}"
    var unlockedCharacters: Set<String> = []

    // Unlocked items: "{edition}-{id}"
    var unlockedItems: Set<String> = []

    /// City and road event decks, and what events leave for the next scenario.
    var events = EventState()

    /// Make this the state of a brand-new campaign: every field back to its starting value, so
    /// nothing (prosperity, unlocks, looted treasures, the log…) carries over from the last one.
    /// Every stored property must be listed here; `CampaignTests` checks against a fresh state.
    func resetToNewCampaign() {
        let fresh = GameState()
        edition = fresh.edition
        conditions = fresh.conditions
        figures = fresh.figures
        state = fresh.state
        round = fresh.round
        level = fresh.level
        levelCalculation = fresh.levelCalculation
        levelAdjustment = fresh.levelAdjustment
        difficulty = fresh.difficulty
        bonusAdjustment = fresh.bonusAdjustment
        ge5Player = fresh.ge5Player
        playerCount = fresh.playerCount
        solo = fresh.solo
        playSeconds = fresh.playSeconds
        totalSeconds = fresh.totalSeconds
        elementBoard = fresh.elementBoard
        monsterAttackModifierDeck = fresh.monsterAttackModifierDeck
        allyAttackModifierDeck = fresh.allyAttackModifierDeck
        lootDeck = fresh.lootDeck
        partyName = fresh.partyName
        tableRules = fresh.tableRules
        learningMode = fresh.learningMode
        partyReputation = fresh.partyReputation
        partyProsperity = fresh.partyProsperity
        scenario = fresh.scenario
        completedScenarios = fresh.completedScenarios
        manualScenarios = fresh.manualScenarios
        globalAchievements = fresh.globalAchievements
        partyAchievements = fresh.partyAchievements
        campaignStickers = fresh.campaignStickers
        mapOverlays = fresh.mapOverlays
        lootedTreasures = fresh.lootedTreasures
        retiredCharacters = fresh.retiredCharacters
        campaignLog = fresh.campaignLog
        unlockedCharacters = fresh.unlockedCharacters
        unlockedItems = fresh.unlockedItems
        events = fresh.events
    }

    // MARK: - Computed helpers

    var characters: [GameCharacter] {
        figures.compactMap { $0.asCharacter }
    }

    var activeCharacters: [GameCharacter] {
        characters.filter { !$0.absent && !$0.exhausted }
    }

    var monsters: [GameMonster] {
        figures.compactMap { $0.asMonster }
    }

    var objectives: [GameObjectiveContainer] {
        figures.compactMap { $0.asObjective }
    }

    /// Whether a Bless or Curse card is left to shuffle into a deck (p.23): the box has 10 Bless
    /// cards shared by every deck, 10 Curses for the players' decks and 10 for the monsters'.
    func hasSpecialCardLeft(_ type: AttackModifierType, forMonsterDeck: Bool) -> Bool {
        let playerDecks = characters.map(\.attackModifierDeck) + [allyAttackModifierDeck]
        let decks: [AttackModifierDeck]
        switch type {
        case .bless: decks = playerDecks + [monsterAttackModifierDeck]
        case .curse: decks = forMonsterDeck ? [monsterAttackModifierDeck] : playerDecks
        default: return true
        }
        return decks.reduce(0) { $0 + $1.undrawnCount(of: type) } < 10
    }

    /// Prosperity level (1–9) reached by the party's prosperity checkmarks.
    var prosperityLevel: Int {
        let thresholds = [0, 4, 9, 15, 22, 30, 39, 50, 64]
        return (thresholds.lastIndex { partyProsperity >= $0 } ?? 0) + 1
    }
}

// MARK: - Type-erased Figure wrapper

enum AnyFigure: Identifiable {
    case character(GameCharacter)
    case monster(GameMonster)
    case objective(GameObjectiveContainer)

    var id: String {
        switch self {
        case .character(let c): return "char-\(c.edition)-\(c.name)"
        case .monster(let m): return "mon-\(m.edition)-\(m.name)"
        case .objective(let o): return "obj-\(o.id)"
        }
    }

    var figure: any Figure {
        switch self {
        case .character(let c): return c
        case .monster(let m): return m
        case .objective(let o): return o
        }
    }

    var asCharacter: GameCharacter? {
        if case .character(let c) = self { return c }
        return nil
    }

    var asMonster: GameMonster? {
        if case .monster(let m) = self { return m }
        return nil
    }

    var asObjective: GameObjectiveContainer? {
        if case .objective(let o) = self { return o }
        return nil
    }

    var effectiveInitiative: Double {
        figure.effectiveInitiative
    }

    var name: String { figure.name }
    var edition: String { figure.edition }
    var figureType: FigureType { figure.figureType }
}
