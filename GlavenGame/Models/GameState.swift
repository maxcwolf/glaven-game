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
    var bonusAdjustment: Int = 0
    var ge5Player: Bool = true
    var playerCount: Int = -1
    var solo: Bool = false
    var playSeconds: Int = 0
    var totalSeconds: Int = 0
    var elementBoard: [ElementModel] = ElementModel.defaultBoard()
    var monsterAttackModifierDeck: AttackModifierDeck = .defaultDeck()
    var allyAttackModifierDeck: AttackModifierDeck = .defaultDeck()
    var lootDeck: LootDeck = LootDeck()
    var partyName: String = ""
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
