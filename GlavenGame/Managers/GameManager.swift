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
    let eventCardManager: EventCardManager
    let actionsManager: ActionsManager
    let boardCoordinator: BoardCoordinator

    let modelContainer: ModelContainer
    private var modelContext: ModelContext

    /// What the autosave holds (nil when there is nothing to continue), kept up to date by
    /// `saveGame` so the main menu doesn't decode the save on every render.
    private(set) var autosaveSummary: AutosaveSummary?

    /// Whether an autosave with a party exists.
    var hasAutosave: Bool { autosaveSummary != nil }

    /// The game as it stood at the start of the current round on the board. While a scenario is
    /// in progress this is what the autosave holds, and Continue resumes there.
    private(set) var roundCheckpoint: GameSnapshot?

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
        self.eventCardManager = EventCardManager(game: game, editionStore: editionStore,
                                                 scenarioManager: scenarioMgr, itemManager: itemMgr)
        self.actionsManager = actMgr
        self.boardCoordinator = BoardCoordinator()

        // Wire board coordinator
        boardCoordinator.gameManager = self

        // Wire cross-manager dependencies
        entityMgr.scenarioStatsManager = statsMgr
        charMgr.scenarioStatsManager = statsMgr
        scenarioMgr.scenarioStatsManager = statsMgr

        // Wire scenario rules to round advancement
        roundMgr.onRoundAdvanced = { [weak self] in
            guard let self else { return }
            self.scenarioRulesManager.evaluateRules(phase: .roundStart)
            // Aggressor: is there a monster on the map as the round begins?
            let board = self.boardCoordinator
            let monstersPresent = board.boardState.piecePositions.keys.contains {
                if case .monster = $0 { return !board.isPlayerSide($0) }
                return false
            }
            self.scenarioStatsManager.advanceRound(monstersPresent: monstersPresent)
        }
        roundMgr.onRoundEnding = { [weak self] in
            self?.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        }

        // Wire room-reveal effect from scenario rules back into ScenarioManager
        rulesManager.onOpenRooms = { [weak self] roomNumbers in
            guard let self = self, let scenario = self.game.scenario else { return }
            // On the board, a room opened by a scenario rule is revealed through its door.
            if self.appPhase == .board, self.boardCoordinator.scenarioData != nil {
                self.boardCoordinator.openScenarioRooms(roomNumbers)
                return
            }
            for num in roomNumbers {
                if let room = scenario.data.rooms?.first(where: { $0.roomNumber == num }) {
                    self.scenarioManager.openRoom(room)
                }
            }
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

        autosaveSummary = loadAutosaveSummary()

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

    /// Start over with an empty party. The autosave is replaced the next time the game saves.
    func newGame() {
        if boardCoordinator.scenarioData != nil { boardCoordinator.exitBoard() }
        roundCheckpoint = nil
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
        // Scenario level (and so monster level, trap damage, gold and bonus XP) is fixed at the
        // start of the scenario from the party's levels and difficulty (p.15).
        levelManager.calculateAndApplyLevel()
        roundCheckpoint = nil

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
        scenarioManager.recordStartingTallies()

        let mapStore = ScenarioMapStore.shared
        guard let vgbScenario = mapStore.scenarioMap(for: scenario.data.index) else { return }

        // A character who hasn't chosen a hand brings the default one from their card pool.
        for character in game.activeCharacters where character.handCards.isEmpty {
            character.handCards = CardPool.defaultHand(characterManager.abilities(for: character),
                                                       chosen: character.chosenCards, handSize: character.handSize)
        }

        let playerCount = max(2, game.characters.filter { !$0.absent }.count)
        boardCoordinator.startScenario(scenario: vgbScenario, playerCount: playerCount)
        applyEventEffectsAtScenarioStart()
        appPhase = .board
    }

    /// What road and city events left for this scenario (GH p.38): each character starts with
    /// the damage, conditions, −1 cards and discarded cards the events gave them.
    func applyEventEffectsAtScenarioStart() {
        let effects = game.events.nextScenario
        guard !effects.isEmpty else { return }
        for character in game.activeCharacters {
            let name = GameText.characterName(character, labels: editionStore)
            if effects.damage > 0 {
                character.health = max(1, character.health - effects.damage)
                boardCoordinator.log("\(name) starts with \(effects.damage) damage from an event", category: .damage)
            }
            for condition in effects.conditions {
                entityManager.addCondition(condition, to: character)
                boardCoordinator.log("\(name) starts with \(GameText.conditionName(condition)) from an event", category: .condition)
            }
            for _ in 0..<(effects.minusOneCards[character.id] ?? 0) {
                character.attackModifierDeck.addCard(type: .minus1)
            }
            if let count = effects.minusOneCards[character.id], count > 0 {
                boardCoordinator.log("\(name) adds \(count) \u{2212}1 card\(count == 1 ? "" : "s") from an event", category: .setup)
            }
            let discards = (effects.discards[character.id] ?? []).filter(character.handCards.contains)
            if !discards.isEmpty {
                character.handCards.removeAll(where: discards.contains)
                character.discardedCards += discards
                boardCoordinator.log("\(name) starts with \(discards.count) card\(discards.count == 1 ? "" : "s") discarded from an event", category: .setup)
            }
        }
        game.events.nextScenario = ScenarioStartEffects()
        boardCoordinator.syncPieceVisuals()
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

    /// Save the game to the autosave. While a scenario is in progress the autosave holds the
    /// round checkpoint, so a save in the middle of a round never records a half-played turn.
    func saveGame() {
        let snapshot = roundCheckpoint ?? game.toSnapshot()
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
        autosaveSummary = AutosaveSummary(snapshot, savedAt: Date(), labels: editionStore)
    }

    /// Record the start of a round on the board and save it. Called as each round's card
    /// selection begins, the one point where no turn is half-played.
    func checkpointRound() {
        var snapshot = game.toSnapshot()
        snapshot.boardSnapshot = boardCoordinator.snapshot()
        roundCheckpoint = snapshot
        saveGame()
    }

    /// Load the autosave into the game. A save made during a scenario becomes the round
    /// checkpoint again, for `continueGame` to resume the board from.
    @discardableResult
    func restoreGame() -> Bool {
        guard let snapshot = loadAutosave() else { return false }
        if boardCoordinator.scenarioData != nil { boardCoordinator.exitBoard() }
        undoStack.removeAll()
        redoStack.removeAll()
        game.restore(from: snapshot, editionStore: editionStore)
        roundCheckpoint = snapshot.boardSnapshot != nil && game.scenario != nil ? snapshot : nil
        return true
    }

    /// Continue the saved game: back onto the board at the start of the saved round if a scenario
    /// was in progress, otherwise to the party and scenario screen.
    func continueGame() {
        guard restoreGame() else { return }
        if resumeScenarioFromCheckpoint() {
            appPhase = .board
        } else {
            appPhase = .gameSetup
        }
    }

    private func resumeScenarioFromCheckpoint() -> Bool {
        guard let checkpoint = roundCheckpoint, let board = checkpoint.boardSnapshot,
              let scenario = game.scenario,
              let map = ScenarioMapStore.shared.scenarioMap(for: scenario.data.index) else {
            roundCheckpoint = nil
            return false
        }
        boardCoordinator.resumeScenario(scenario: map, board: board)
        return true
    }

    /// Finish the scenario on the board (rewards on a success), leave the board and save.
    func completeScenario(success: Bool, choices: ScenarioRewardChoices = ScenarioRewardChoices()) {
        scenarioManager.finishScenario(success: success, choices: choices)
        roundCheckpoint = nil
        boardCoordinator.exitBoard()
        // Back to town: spend gold, level up, pick the next scenario — after a city event.
        game.events.cityEventDue = true
        appPhase = .gameSetup
        saveGame()
    }

    /// Shows the main menu's "Start a new campaign?" confirmation.
    var confirmingNewGame = false

    /// Start a new campaign from scratch and go to the party screen.
    func beginNewGame() {
        newGame()
        saveGame()
        setEdition("gh")
        appPhase = .gameSetup
    }

    /// New Campaign from the app menu: save and go to the main menu, which asks before
    /// replacing a saved party.
    func requestNewGame() {
        guard hasAutosave || !game.characters.isEmpty else {
            beginNewGame()
            return
        }
        if boardCoordinator.scenarioData != nil {
            saveAndQuitScenario()
        } else {
            returnToMainMenu()
        }
        confirmingNewGame = true
    }

    /// Go back to the main menu from the party screen, saving the party on the way.
    func returnToMainMenu() {
        saveGame()
        appPhase = .mainMenu
    }

    /// Leave the board for the main menu. The scenario stays saved at the start of the current
    /// round, and Continue resumes it there.
    func saveAndQuitScenario() {
        saveGame()
        boardCoordinator.exitBoard()
    }

    private func loadAutosave() -> GameSnapshot? {
        let fetchDescriptor = FetchDescriptor<SavedGameModel>(
            predicate: #Predicate { $0.name == "autosave" }
        )
        guard let saved = try? modelContext.fetch(fetchDescriptor).first,
              let data = saved.snapshotData else { return nil }
        return try? JSONDecoder().decode(GameSnapshot.self, from: data)
    }

    private func loadAutosaveSummary() -> AutosaveSummary? {
        let fetchDescriptor = FetchDescriptor<SavedGameModel>(
            predicate: #Predicate { $0.name == "autosave" }
        )
        guard let saved = try? modelContext.fetch(fetchDescriptor).first,
              let data = saved.snapshotData,
              let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data) else { return nil }
        return AutosaveSummary(snapshot, savedAt: saved.updatedAt, labels: editionStore)
    }

    // MARK: - Save Slots

    /// Save to a named slot. During a scenario that's the start of the current round, as for the
    /// autosave, so loading it never lands in a half-played turn.
    func saveToSlot(name: String) {
        let snapshot = roundCheckpoint ?? game.toSnapshot(boardCoordinator: boardCoordinator)
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

    /// Load a saved slot and carry on from it the way Continue does: it becomes the autosave,
    /// then the game resumes on the board (mid-scenario) or at the party screen.
    func loadSlotAndContinue(name: String) {
        let fetchDescriptor = FetchDescriptor<SavedGameModel>(predicate: #Predicate { $0.name == name })
        guard let saved = try? modelContext.fetch(fetchDescriptor).first, let data = saved.snapshotData,
              let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data) else { return }
        let autosave = FetchDescriptor<SavedGameModel>(predicate: #Predicate { $0.name == "autosave" })
        if let existing = try? modelContext.fetch(autosave).first {
            existing.snapshotData = data
            existing.updatedAt = Date()
        } else {
            let model = SavedGameModel(name: "autosave")
            model.snapshotData = data
            modelContext.insert(model)
        }
        try? modelContext.save()
        autosaveSummary = AutosaveSummary(snapshot, savedAt: Date(), labels: editionStore)
        continueGame()
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

/// What the autosave holds, in the words the main menu shows ("Brute, Tinkerer · #1 Black
/// Barrow · Round 2").
struct AutosaveSummary: Equatable {
    var characterNames: [String]
    /// "#1 Black Barrow" while a scenario is in progress.
    var scenario: String?
    /// The round Continue resumes at, while a scenario is in progress.
    var round: Int?
    var savedAt: Date

    init?(_ snapshot: GameSnapshot, savedAt: Date, labels: EditionDataStore?) {
        let characters: [CharacterSnapshot] = snapshot.figures.compactMap {
            if case .character(let c) = $0, !c.absent { return c }
            return nil
        }
        guard !characters.isEmpty else { return nil }
        characterNames = characters.map {
            $0.title.isEmpty ? GameText.className($0.name, edition: $0.edition, labels: labels) : $0.title
        }.sorted()
        if let scenario = snapshot.scenario, snapshot.boardSnapshot != nil {
            let name = labels?.scenarios(for: scenario.edition).first { $0.index == scenario.index }?.name
            self.scenario = name.map { "#\(scenario.index) \($0)" } ?? "#\(scenario.index)"
            round = snapshot.round + 1
        }
        self.savedAt = savedAt
    }
}
