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

    /// Saved campaigns, one file each.
    let campaignStore: CampaignStore

    /// The campaign being played; the game saves to it. Nil until a new campaign first saves.
    private(set) var currentCampaignID: UUID?

    /// Every saved campaign, most recently played first, kept up to date as the game saves so the
    /// main menu doesn't read the files on every render.
    private(set) var campaigns: [CampaignStore.Entry] = []

    /// The campaign Continue resumes: the most recently played one with a party.
    var continueCampaign: CampaignStore.Entry? { campaigns.first { $0.summary != nil } }

    /// What Continue resumes (nil when there is nothing to continue).
    var autosaveSummary: AutosaveSummary? { continueCampaign?.summary }

    /// Whether there's a campaign to continue.
    var hasAutosave: Bool { autosaveSummary != nil }

    /// The game as it stood at the start of the current round on the board. While a scenario is
    /// in progress this is what the autosave holds, and Continue resumes there.
    private(set) var roundCheckpoint: GameSnapshot?

    // Undo/Redo snapshots
    private var undoStack: [Data] = []
    private var redoStack: [Data] = []

    init(modelContainer: ModelContainer) {
        // Use local variables to satisfy Swift two-phase initialization
        self.campaignStore = CampaignStore(directory: CampaignStore.directory(for: modelContainer))
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

        migrateSwiftDataSaves()
        refreshCampaigns()

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

    /// Start over with an empty party, as a new campaign: the one being played stays saved as it is.
    func newGame() {
        if boardCoordinator.scenarioData != nil { boardCoordinator.exitBoard() }
        currentCampaignID = nil
        roundCheckpoint = nil
        appPhase = .mainMenu
        game.resetToNewCampaign()
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
        forgetHistory()
    }

    /// What road and city events left for this scenario (GH p.38): each character starts with
    /// the damage, conditions, −1 cards and discarded cards the events gave them.
    func applyEventEffectsAtScenarioStart() {
        game.events.donatedThisVisit = []   // the party has left town
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
            if let count = effects.blessings[character.id], count > 0 {
                for _ in 0..<count where game.hasSpecialCardLeft(.bless, forMonsterDeck: false) {
                    character.attackModifierDeck.addCard(type: .bless)
                }
                boardCoordinator.log("\(name) starts with \(count) blessings from the sanctuary", category: .setup)
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

    /// Undo and redo are for the town and setup screens. On the board a turn in progress holds
    /// figures, continuations and animations that a restored snapshot would leave behind (a
    /// half-finished move would never complete), so the board's own Cancel takes back a choice
    /// instead, and nothing is recorded there. History never reaches across a scenario.
    var canUndo: Bool { appPhase != .board && !undoStack.isEmpty }
    var canRedo: Bool { appPhase != .board && !redoStack.isEmpty }

    private func forgetHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
    var undoCount: Int { undoStack.count }
    var redoCount: Int { redoStack.count }

    private static let maxUndoDepth = 50

    // MARK: - Persistence

    /// Save the game to its campaign. While a scenario is in progress that's the round
    /// checkpoint, so a save in the middle of a round never records a half-played turn. A new
    /// campaign gets its file once it has a party.
    /// Why the last save failed (a full disk, say), for the app to tell the player; nil once a
    /// save works again.
    var saveFailure: String?

    /// Write a campaign file, noting a failure instead of losing it silently.
    private func writeCampaign(_ file: CampaignFile) {
        do {
            try campaignStore.save(file)
            saveFailure = nil
        } catch {
            saveFailure = "The campaign couldn't be saved: \(error.localizedDescription)"
        }
    }

    func saveGame() {
        let snapshot = roundCheckpoint ?? game.toSnapshot()
        let now = Date()
        if let id = currentCampaignID, var file = campaignStore.load(id) {
            file.snapshot = snapshot
            file.updatedAt = now
            writeCampaign(file)
        } else {
            guard !game.characters.isEmpty else { return }
            let id = currentCampaignID ?? UUID()
            currentCampaignID = id
            writeCampaign(CampaignFile(id: id, name: "", createdAt: now, updatedAt: now, snapshot: snapshot))
        }
        refreshCampaigns()
    }

    /// Record the start of a round on the board and save it. Called as each round's card
    /// selection begins, the one point where no turn is half-played.
    func checkpointRound() {
        var snapshot = game.toSnapshot()
        snapshot.boardSnapshot = boardCoordinator.snapshot()
        roundCheckpoint = snapshot
        saveGame()
    }

    /// Load the campaign Continue offers into the game. A save made during a scenario becomes the
    /// round checkpoint again, for `continueGame` to resume the board from.
    @discardableResult
    func restoreGame() -> Bool {
        guard let id = continueCampaign?.id ?? currentCampaignID else { return false }
        return restoreCampaign(id)
    }

    private func restoreCampaign(_ id: UUID) -> Bool {
        guard let file = campaignStore.load(id) else { return false }
        if boardCoordinator.scenarioData != nil { boardCoordinator.exitBoard() }
        undoStack.removeAll()
        redoStack.removeAll()
        currentCampaignID = id
        let snapshot = file.snapshot
        game.restore(from: snapshot, editionStore: editionStore)
        roundCheckpoint = snapshot.boardSnapshot != nil && game.scenario != nil ? snapshot : nil
        return true
    }

    /// Continue the most recently played campaign.
    func continueGame() {
        guard let id = continueCampaign?.id ?? currentCampaignID else { return }
        continueCampaign(id)
    }

    /// Play a saved campaign: back onto the board at the start of the saved round if a scenario
    /// was in progress, otherwise to the party and scenario screen. The campaign being played is
    /// saved first.
    func continueCampaign(_ id: UUID) {
        if id != currentCampaignID, currentCampaignID != nil { saveGame() }
        guard restoreCampaign(id) else { return }
        if resumeScenarioFromCheckpoint() {
            appPhase = .board
            forgetHistory()
        } else {
            appPhase = .gameSetup
        }
        // Played now: it moves to the top of the list.
        if var file = campaignStore.load(id) {
            file.updatedAt = Date()
            writeCampaign(file)
        }
        refreshCampaigns()
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
        let questReward = success ? game.scenario.flatMap { scenario in
            scenario.data.rewards?.custom.flatMap { editionStore.resolveCustomText($0, edition: scenario.data.edition) }
        } : nil
        scenarioManager.finishScenario(success: success, choices: choices)
        if let questReward { applyQuestReward(questReward) }
        roundCheckpoint = nil
        boardCoordinator.exitBoard()
        forgetHistory()   // a finished scenario can't be undone
        // Back to town: spend gold, level up, pick the next scenario — after a city event.
        game.events.cityEventDue = true
        appPhase = .gameSetup
        saveGame()
    }

    /// Scenario rewards about a personal quest (GH 54–62): '"Vengeance" quest complete' completes
    /// it for whoever holds it; "Immediately retire the Seeker of Xorn" retires them, the
    /// scenario's own events replacing the class's retirement events.
    func applyQuestReward(_ text: String) {
        func holder(of questName: String) -> GameCharacter? {
            game.characters.first { character in
                guard let id = character.personalQuest else { return false }
                return characterManager.personalQuest(id, edition: character.edition)?.name.lowercased() == questName.lowercased()
            }
        }
        func complete(_ character: GameCharacter) {
            guard let id = character.personalQuest,
                  let quest = characterManager.personalQuest(id, edition: character.edition) else { return }
            character.personalQuestProgress = quest.requirements.map(\.target)
            game.campaignLog.append(CampaignLogEntry(type: .questCompleted,
                message: "\(GameText.characterName(character, labels: editionStore))\u{2019}s quest \(quest.name) is complete"))
        }
        if let match = text.firstMatch(of: #/"(.+)" quest complete/#), let character = holder(of: String(match.1)) {
            complete(character)
        } else if let match = text.firstMatch(of: #/[Ii]mmediately retire the ([^.]+)\./#), let character = holder(of: String(match.1)) {
            complete(character)
            characterManager.retireCharacter(character, addRetirementEvents: false)
        }
    }

    /// Turn a table rule on or off. Going back to the item limits leaves home what no longer fits;
    /// items already at home stay there until brought.
    func setTableRule(_ rule: WritableKeyPath<TableRules, Bool>, _ on: Bool) {
        guard game.tableRules[keyPath: rule] != on else { return }
        pushUndoState()
        game.tableRules[keyPath: rule] = on
        if rule == \TableRules.bringEveryItem {
            for character in game.characters {
                editionStore.fitLoadout(character, unlimited: on)
            }
        }
        saveGame()
    }

    /// Draw the events about to be resolved: their decks are started (shuffled) now and saved, so
    /// quitting before resolving one can't deal a different card next time.
    func prepareEvents(_ decks: [EventCardManager.Deck]) {
        let unstarted = decks.contains { game.events.peek($0.rawValue) == nil }
        for deck in decks { _ = eventCardManager.deck(deck) }
        if unstarted { saveGame() }
    }

    /// Start a new campaign from scratch and go to the party screen. Other campaigns stay saved.
    func beginNewGame() {
        newGame()
        setEdition("gh")
        appPhase = .gameSetup
    }

    /// New Campaign from the app menu: the campaign being played is saved (a scenario at the
    /// start of its round), then a new one begins.
    func requestNewGame() {
        if boardCoordinator.scenarioData != nil {
            saveAndQuitScenario()
        } else if !game.characters.isEmpty {
            saveGame()
        }
        beginNewGame()
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
        forgetHistory()
    }

    // MARK: - Campaigns

    /// A copy of a saved campaign, to come back to (before a hard scenario, say). Play carries on
    /// in the original. The current campaign is saved first, so its copy is as it stands.
    @discardableResult
    func duplicateCampaign(_ id: UUID) -> UUID? {
        if id == currentCampaignID { saveGame() }
        guard var file = campaignStore.load(id) else { return nil }
        let title = campaigns.first { $0.id == id }?.title ?? file.name
        file.id = UUID()
        file.name = "\(title) (copy)"
        file.createdAt = Date()
        file.updatedAt = file.updatedAt.addingTimeInterval(-1)   // listed below the original
        writeCampaign(file)
        refreshCampaigns()
        return file.id
    }

    func renameCampaign(_ id: UUID, to name: String) {
        guard var file = campaignStore.load(id) else { return }
        file.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        writeCampaign(file)
        refreshCampaigns()
    }

    /// Delete a campaign's file for good. Deleting the one being played leaves the game as it is,
    /// unsaved, until it's saved as a new campaign.
    func deleteCampaign(_ id: UUID) {
        campaignStore.delete(id)
        if id == currentCampaignID { currentCampaignID = nil }
        refreshCampaigns()
    }

    func refreshCampaigns() {
        campaigns = campaignStore.entries(labels: editionStore)
    }

    /// Saves from before campaigns were files (the SwiftData autosave and named slots) become
    /// campaigns, once.
    private func migrateSwiftDataSaves() {
        guard let saved = try? modelContext.fetch(FetchDescriptor<SavedGameModel>()), !saved.isEmpty else { return }
        for model in saved {
            if let data = model.snapshotData, let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data) {
                writeCampaign(CampaignFile(id: UUID(), name: model.name == "autosave" ? "" : model.name,
                                                createdAt: model.createdAt, updatedAt: model.updatedAt, snapshot: snapshot))
            }
            modelContext.delete(model)
        }
        try? modelContext.save()
    }

    // MARK: - Export / Import

    /// The current campaign's file, saved first, for sharing.
    func exportGameData() -> Data? {
        saveGame()
        return currentCampaignID.flatMap(campaignStore.exportData)
    }

    /// Add an exported campaign to the list (it never replaces one); false if the file isn't one.
    @discardableResult
    func importGameData(_ data: Data) -> Bool {
        guard campaignStore.importCampaign(data) != nil else { return false }
        refreshCampaigns()
        return true
    }

    // MARK: - Undo/Redo

    func pushUndoState() {
        guard appPhase != .board else { return }
        guard let data = try? JSONEncoder().encode(game.toSnapshot(boardCoordinator: boardCoordinator)) else { return }
        undoStack.append(data)
        if undoStack.count > Self.maxUndoDepth {
            undoStack.removeFirst(undoStack.count - Self.maxUndoDepth)
        }
        redoStack.removeAll()
    }

    func undo() {
        guard canUndo, let previous = undoStack.popLast() else { return }
        // Push current state to redo
        if let current = try? JSONEncoder().encode(game.toSnapshot(boardCoordinator: boardCoordinator)) {
            redoStack.append(current)
        }
        if let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: previous) {
            game.restore(from: snapshot, editionStore: editionStore, boardCoordinator: boardCoordinator)
        }
    }

    func redo() {
        guard canRedo, let next = redoStack.popLast() else { return }
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
        if index == currentIndex || appPhase == .board { return }

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
