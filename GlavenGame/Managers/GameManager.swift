import Foundation
import SwiftData

@Observable
final class GameManager {
    var appPhase: AppPhase = .mainMenu
    var game: GameState
    let editionStore: EditionDataStore

    let characterManager: CharacterManager
    let monsterManager: MonsterManager
    let roundManager: RoundManager
    let entityManager: EntityManager
    let levelManager: LevelManager
    let attackModifierManager: AttackModifierManager
    let lootManager: LootManager
    let settingsManager: SettingsManager
    let scenarioManager: ScenarioManager
    let scenarioRulesManager: ScenarioRulesManager
    let scenarioStatsManager: ScenarioStatsManager
    let objectiveManager: ObjectiveManager
    let enhancementsManager: EnhancementsManager
    let itemManager: ItemManager
    let actionsManager: ActionsManager
    let boardCoordinator: BoardCoordinator

    private let modelContainer: ModelContainer
    private var modelContext: ModelContext

    /// Whether an autosave with figures exists.
    var hasAutosave: Bool {
        let fetchDescriptor = FetchDescriptor<SavedGameModel>(
            predicate: #Predicate { $0.name == "autosave" }
        )
        guard let saved = try? modelContext.fetch(fetchDescriptor).first,
              let data = saved.snapshotData,
              let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data) else {
            return false
        }
        return !snapshot.figures.isEmpty
    }

    // Undo/Redo snapshots
    private var undoStack: [Data] = []
    private var redoStack: [Data] = []

    init(modelContainer: ModelContainer) {
        // Use local variables to satisfy Swift two-phase initialization
        let game = GameState()
        let editionStore = EditionDataStore()
        let modelContext = ModelContext(modelContainer)

        self.modelContainer = modelContainer
        self.modelContext = modelContext
        self.game = game
        self.editionStore = editionStore

        // Load GH edition only
        editionStore.loadAllEditions()

        // Initialize sub-managers (order matters: dependencies must be created first)
        let entityMgr = EntityManager(game: game)
        let levelMgr = LevelManager(game: game)
        let amMgr = AttackModifierManager(game: game)
        let charMgr = CharacterManager(game: game, editionStore: editionStore, entityManager: entityMgr, attackModifierManager: amMgr)
        let monMgr = MonsterManager(game: game, editionStore: editionStore)
        let lootMgr = LootManager(game: game)
        let roundMgr = RoundManager(game: game, entityManager: entityMgr,
                                     monsterManager: monMgr, attackModifierManager: amMgr)
        let settingsMgr = SettingsManager(modelContext: modelContext)
        let scenarioMgr = ScenarioManager(game: game, editionStore: editionStore,
                                           monsterManager: monMgr, levelManager: levelMgr)
        let rulesManager = ScenarioRulesManager(game: game, monsterManager: monMgr,
                                                 entityManager: entityMgr)
        let statsMgr = ScenarioStatsManager(game: game)
        let objMgr = ObjectiveManager(game: game)
        let enhMgr = EnhancementsManager(game: game)
        let itemMgr = ItemManager(game: game, editionStore: editionStore)
        let actMgr = ActionsManager(game: game, monsterManager: monMgr)

        self.entityManager = entityMgr
        self.levelManager = levelMgr
        self.attackModifierManager = amMgr
        self.characterManager = charMgr
        self.monsterManager = monMgr
        self.lootManager = lootMgr
        self.roundManager = roundMgr
        self.settingsManager = settingsMgr
        self.scenarioManager = scenarioMgr
        self.scenarioRulesManager = rulesManager
        self.scenarioStatsManager = statsMgr
        self.objectiveManager = objMgr
        self.enhancementsManager = enhMgr
        self.itemManager = itemMgr
        self.actionsManager = actMgr
        self.boardCoordinator = BoardCoordinator()

        // Wire board coordinator
        boardCoordinator.gameManager = self

        // Wire cross-manager dependencies
        entityMgr.scenarioStatsManager = statsMgr
        charMgr.scenarioStatsManager = statsMgr

        // Wire scenario rules to round advancement
        roundMgr.onRoundAdvanced = { [weak self] in
            self?.scenarioRulesManager.evaluateRules()
            self?.scenarioStatsManager.advanceRound()
        }

        // Wire undo state capture into all sub-managers
        let beforeMutate: () -> Void = { [weak self] in self?.pushUndoState() }
        charMgr.onBeforeMutate = beforeMutate
        monMgr.onBeforeMutate = beforeMutate
        entityMgr.onBeforeMutate = beforeMutate
        roundMgr.onBeforeMutate = beforeMutate
        scenarioMgr.onBeforeMutate = beforeMutate
        amMgr.onBeforeMutate = beforeMutate
        lootMgr.onBeforeMutate = beforeMutate
        objMgr.onBeforeMutate = beforeMutate
        enhMgr.onBeforeMutate = beforeMutate
        itemMgr.onBeforeMutate = beforeMutate
        actMgr.onBeforeMutate = beforeMutate

        // Remove summon pieces from board when a character is exhausted
        charMgr.onCharacterExhausted = { [weak self] character in
            guard let self else { return }
            for summon in character.summons {
                let pieceID = PieceID.summon(id: summon.id)
                self.boardCoordinator.boardState.removePiece(pieceID)
                self.boardCoordinator.boardScene?.removePieceSprite(id: pieceID)
            }
        }
    }

    func newGame() {
        appPhase = .mainMenu
        game.edition = nil
        game.figures = []
        game.state = .draw
        game.round = 0
        game.level = 1
        game.levelAdjustment = 0
        game.elementBoard = ElementModel.defaultBoard()
        game.monsterAttackModifierDeck = .defaultDeck()
        game.allyAttackModifierDeck = .defaultDeck()
        game.lootDeck = LootDeck()
        game.conditions = []
        game.scenario = nil
        game.completedScenarios = []
        game.globalAchievements = []
        game.partyAchievements = []
        game.campaignStickers = []
        undoStack = []
        redoStack = []
        scenarioStatsManager.reset()
    }

    /// Set scenario and initialize the game board.
    func startScenarioOnBoard(_ scenarioData: ScenarioData) {
        // Set the scenario in game state
        scenarioManager.setScenario(scenarioData)

        // Try to start the board (requires characters)
        enterBoard()
    }

    /// Enter the board for the current scenario. Requires characters to be set.
    func enterBoard() {
        guard let scenario = game.scenario else { return }
        guard !game.activeCharacters.isEmpty else { return }
        guard boardCoordinator.boardScene == nil else { return } // already on board

        let mapStore = ScenarioMapStore.shared
        guard let vgbScenario = mapStore.scenarioMap(for: scenario.data.index) else { return }

        // Auto-fill empty hands with starting ability cards
        for character in game.activeCharacters {
            guard character.handCards.isEmpty else { continue }
            let deckName = character.characterData?.deck ?? character.name
            let allAbilities = editionStore.abilities(forDeck: deckName, edition: character.edition)

            // Available cards: level 1 + level X + any up to character level
            let available = allAbilities.filter { ability in
                guard let level = ability.level else { return false }
                switch level {
                case .string(let s): return s.uppercased() == "X"
                case .int(let l): return l >= 1 && l <= character.level
                }
            }

            // Fill hand: level 1 cards first, then level X, then higher levels
            let level1 = available.filter { $0.level?.intValue == 1 }
            let levelX = available.filter {
                if case .string(let s) = $0.level { return s.uppercased() == "X" }
                return false
            }
            let higherLevel = available.filter {
                guard let l = $0.level?.intValue else { return false }
                return l > 1 && l <= character.level
            }

            var hand: [Int] = level1.compactMap(\.cardId)
            for card in levelX + higherLevel {
                if hand.count >= character.handSize { break }
                if let cardId = card.cardId { hand.append(cardId) }
            }
            character.handCards = Array(hand.prefix(character.handSize))
        }

        let playerCount = max(2, game.activeCharacters.count)
        boardCoordinator.startScenario(scenario: vgbScenario, playerCount: playerCount)
        appPhase = .board
    }

    func setEdition(_ edition: String) {
        game.edition = edition
        if let info = editionStore.editions.first(where: { $0.edition == edition }) {
            game.conditions = info.conditions ?? [
                .stun, .immobilize, .disarm, .wound, .muddle, .poison,
                .invisible, .strengthen, .curse, .bless
            ]
        }
    }

    func sortFigures() {
        game.figures.sort { a, b in
            let initA = a.effectiveInitiative
            let initB = b.effectiveInitiative
            if initA != initB { return initA < initB }
            if a.figureType != b.figureType {
                return a.figureType == .character
            }
            return a.name < b.name
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoCount: Int { undoStack.count }
    var redoCount: Int { redoStack.count }

    private static let maxUndoDepth = 50

    // MARK: - Persistence

    func saveGame() {
        let snapshot = game.toSnapshot(boardCoordinator: boardCoordinator)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        let fetchDescriptor = FetchDescriptor<SavedGameModel>(
            predicate: #Predicate { $0.name == "autosave" }
        )
        if let existing = try? modelContext.fetch(fetchDescriptor).first {
            existing.snapshotData = data
            existing.updatedAt = Date()
        } else {
            let model = SavedGameModel(name: "autosave")
            model.snapshotData = data
            modelContext.insert(model)
        }
        try? modelContext.save()
    }

    func restoreGame() {
        let fetchDescriptor = FetchDescriptor<SavedGameModel>(
            predicate: #Predicate { $0.name == "autosave" }
        )
        guard let saved = try? modelContext.fetch(fetchDescriptor).first,
              let data = saved.snapshotData,
              let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data) else {
            return
        }
        game.restore(from: snapshot, editionStore: editionStore, boardCoordinator: boardCoordinator)
    }

    // MARK: - Save Slots

    func saveToSlot(name: String) {
        let snapshot = game.toSnapshot(boardCoordinator: boardCoordinator)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        let fetchDescriptor = FetchDescriptor<SavedGameModel>(
            predicate: #Predicate { $0.name == name }
        )
        if let existing = try? modelContext.fetch(fetchDescriptor).first {
            existing.snapshotData = data
            existing.updatedAt = Date()
        } else {
            let model = SavedGameModel(name: name)
            model.snapshotData = data
            modelContext.insert(model)
        }
        try? modelContext.save()
    }

    func loadFromSlot(name: String) {
        let fetchDescriptor = FetchDescriptor<SavedGameModel>(
            predicate: #Predicate { $0.name == name }
        )
        guard let saved = try? modelContext.fetch(fetchDescriptor).first,
              let data = saved.snapshotData,
              let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data) else {
            return
        }
        undoStack.removeAll()
        redoStack.removeAll()
        game.restore(from: snapshot, editionStore: editionStore, boardCoordinator: boardCoordinator)
    }

    func deleteSlot(name: String) {
        let fetchDescriptor = FetchDescriptor<SavedGameModel>(
            predicate: #Predicate { $0.name == name }
        )
        if let saved = try? modelContext.fetch(fetchDescriptor).first {
            modelContext.delete(saved)
            try? modelContext.save()
        }
    }

    func allSaveSlots() -> [SavedGameModel] {
        let fetchDescriptor = FetchDescriptor<SavedGameModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(fetchDescriptor)) ?? []
    }

    // MARK: - Export / Import

    func exportGameData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(game.toSnapshot(boardCoordinator: boardCoordinator))
    }

    func importGameData(_ data: Data) -> Bool {
        guard let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data) else {
            return false
        }
        pushUndoState()
        game.restore(from: snapshot, editionStore: editionStore, boardCoordinator: boardCoordinator)
        return true
    }

    // MARK: - Undo/Redo

    func pushUndoState() {
        guard let data = try? JSONEncoder().encode(game.toSnapshot(boardCoordinator: boardCoordinator)) else { return }
        undoStack.append(data)
        if undoStack.count > Self.maxUndoDepth {
            undoStack.removeFirst(undoStack.count - Self.maxUndoDepth)
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        // Push current state to redo
        if let current = try? JSONEncoder().encode(game.toSnapshot(boardCoordinator: boardCoordinator)) {
            redoStack.append(current)
        }
        if let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: previous) {
            game.restore(from: snapshot, editionStore: editionStore, boardCoordinator: boardCoordinator)
        }
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        // Push current state to undo
        if let current = try? JSONEncoder().encode(game.toSnapshot(boardCoordinator: boardCoordinator)) {
            undoStack.append(current)
        }
        if let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: next) {
            game.restore(from: snapshot, editionStore: editionStore, boardCoordinator: boardCoordinator)
        }
    }

    /// Jump to a specific point in the history timeline.
    /// Index 0 = earliest undo state. Index undoCount = current state. Index undoCount + redoCount = latest redo state.
    func jumpToHistory(index: Int) {
        let currentIndex = undoStack.count
        if index == currentIndex { return }

        guard let currentData = try? JSONEncoder().encode(game.toSnapshot(boardCoordinator: boardCoordinator)) else { return }

        // Build full timeline: [undo0, undo1, ..., undoN, current, redo(top), ..., redo(bottom)]
        var timeline = undoStack
        timeline.append(currentData)
        timeline.append(contentsOf: redoStack.reversed())

        guard index >= 0 && index < timeline.count else { return }

        let targetData = timeline[index]
        guard let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: targetData) else { return }

        // Rebuild stacks: everything before index → undo, everything after index → redo (reversed)
        undoStack = Array(timeline[0..<index])
        redoStack = Array(timeline[(index + 1)...].reversed())

        game.restore(from: snapshot, editionStore: editionStore, boardCoordinator: boardCoordinator)
    }

    /// Total number of states in the timeline (undo + current + redo)
    var historyCount: Int { undoStack.count + 1 + redoStack.count }

    /// Current position in the timeline (0-based)
    var historyIndex: Int { undoStack.count }
}
