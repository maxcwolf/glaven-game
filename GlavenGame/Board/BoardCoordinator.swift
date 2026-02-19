import Foundation
import SpriteKit
import SwiftUI

/// The phase of the board game.
enum BoardPhase: String {
    case setup          // Placing characters on starting locations
    case cardSelection  // Players selecting ability cards
    case execution      // Turns being executed in initiative order
    case roomReveal     // A door has been opened, new room appearing
    case scenarioEnd    // Victory or defeat
}

/// What kind of interaction the user is currently performing.
enum InteractionMode {
    case idle
    case placingCharacter(characterID: String)
    case selectingMove(pieceID: PieceID, range: Int, validHexes: Set<HexCoord>)
    /// Single-target attack selection (targetCount == 1).
    case selectingAttackTarget(pieceID: PieceID, range: Int, validTargets: Set<PieceID>)
    /// Multi-target attack selection (targetCount > 1). Player picks targets one by one.
    case selectingMultiAttackTargets(pieceID: PieceID, range: Int, validTargets: Set<PieceID>, targetCount: Int, selected: [PieceID])
    case placingSummon(summonID: String, characterID: String, validHexes: Set<HexCoord>)
    case selectingPushPullHex(target: PieceID, attackerPos: HexCoord, validHexes: Set<HexCoord>, remainingSteps: Int, isPush: Bool)
    case watchingMonsterTurn
}

/// Category for turn log entries — drives icon and color rendering.
enum TurnLogCategory {
    case setup       // Scenario start, character placement
    case round       // Round transitions, card selection
    case move        // Movement actions
    case attack      // Attack actions
    case heal        // Healing
    case condition   // Conditions applied
    case damage      // Damage taken
    case death       // Figure killed
    case rest        // Long rest
    case loot        // Looting
    case element     // Element infusion/consumption
    case door        // Door opened / room revealed
    case info        // General info

    var icon: String {
        switch self {
        case .setup:     return "flag.fill"
        case .round:     return "arrow.trianglehead.clockwise"
        case .move:      return "arrow.right"
        case .attack:    return "bolt.fill"
        case .heal:      return "heart.fill"
        case .condition: return "exclamationmark.triangle.fill"
        case .damage:    return "flame.fill"
        case .death:     return "xmark.circle.fill"
        case .rest:      return "bed.double.fill"
        case .loot:      return "star.fill"
        case .element:   return "sparkles"
        case .door:      return "door.left.hand.open"
        case .info:      return "info.circle"
        }
    }

    var color: SwiftUI.Color {
        switch self {
        case .setup:     return .blue
        case .round:     return .yellow
        case .move:      return .cyan
        case .attack:    return .red
        case .heal:      return .green
        case .condition: return .orange
        case .damage:    return .red
        case .death:     return .red
        case .rest:      return .orange
        case .loot:      return .yellow
        case .element:   return .purple
        case .door:      return .cyan
        case .info:      return .gray
        }
    }
}

/// An entry in the turn log.
struct TurnLogEntry: Identifiable {
    let id = UUID()
    let message: String
    let category: TurnLogCategory
    let timestamp = Date()
    /// If true, this is a round separator header (not a regular entry).
    let isRoundHeader: Bool

    init(message: String, category: TurnLogCategory = .info, isRoundHeader: Bool = false) {
        self.message = message
        self.category = category
        self.isRoundHeader = isRoundHeader
    }
}

/// Represents a figure in initiative order during the execution phase.
struct TurnOrderEntry: Identifiable {
    let id = UUID()
    let figure: AnyFigure
    let initiative: Double
    var completed: Bool = false
}

/// Bridge between SpriteKit scene and SwiftUI state.
/// Owns the BoardState and drives the BoardScene.
@Observable
final class BoardCoordinator {

    // MARK: - State

    var boardState: BoardState
    var boardPhase: BoardPhase = .setup
    var interactionMode: InteractionMode = .idle
    var selectedPiece: PieceID?
    var turnLog: [TurnLogEntry] = []

    /// The SpriteKit scene.
    var boardScene: BoardScene?

    /// Current scenario VGB data (needed for room reveals).
    var scenarioData: VGBScenario?

    /// Offset for coordinate rendering (set during board build).
    var offsetCol: Int = 0
    var offsetRow: Int = 0

    /// Reference to the game manager for state mutations.
    weak var gameManager: GameManager?

    // MARK: - Round Loop State

    /// Turn order for the current round's execution phase.
    var turnOrder: [TurnOrderEntry] = []

    /// Index of the currently active figure in turnOrder.
    var currentTurnIndex: Int = -1

    /// The active player turn controller (nil when monster/no turn).
    var activePlayerTurn: PlayerTurnController?

    /// The last target hit by a player attack (used for standalone push/pull actions).
    var lastAttackTarget: PieceID?

    /// The attacker's position at time of last attack (used for standalone push/pull direction).
    var lastAttackerPos: HexCoord?

    /// The summon turn controller.
    var summonTurnController: SummonTurnController?

    /// Pending summon placement awaiting player hex tap.
    struct PendingSummonPlacement {
        let summonID: String
        let characterID: String
        let summonName: String
        let validHexes: Set<HexCoord>
    }
    var pendingSummonPlacement: PendingSummonPlacement?

    /// The monster turn controller.
    var monsterTurnController: MonsterTurnController?

    /// Characters that have completed card selection this round.
    var cardSelectionsComplete: Set<String> = []

    /// Whether the current character is selecting cards.
    var cardSelectingCharacterID: String?

    /// Selected card pairs from card selection phase. Key = character ID.
    var selectedCardPairs: [String: (top: AbilityModel, bottom: AbilityModel)] = [:]

    // MARK: - Damage Mitigation

    /// How the player chose to handle incoming damage.
    enum DamageMitigationChoice {
        case takeDamage
        case loseHandCard(cardIndex: Int)     // Lose 1 card from hand → negate all
        case loseDiscardCards(indices: [Int])  // Lose 2 cards from discard → negate all
    }

    /// Pending damage awaiting player mitigation decision.
    struct PendingDamage: Identifiable {
        let id = UUID()
        let characterID: String
        let damage: Int
        let sourceDescription: String
        var continuation: CheckedContinuation<DamageMitigationChoice, Never>?
    }

    /// Non-nil when a character is being attacked and needs to choose mitigation.
    var pendingDamage: PendingDamage?

    /// Called from the UI when the player makes a damage mitigation choice.
    func resolvePendingDamage(choice: DamageMitigationChoice) {
        guard let pending = pendingDamage else { return }
        let cont = pending.continuation
        pendingDamage = nil
        cont?.resume(returning: choice)
    }

    // MARK: - Long Rest Card Choice

    /// Pending long rest awaiting player's choice of which discard card to lose.
    struct PendingLongRest: Identifiable {
        let id = UUID()
        let characterID: String
    }

    /// Non-nil when a character is long resting and needs to choose a card to lose.
    var pendingLongRest: PendingLongRest?

    /// Called from the UI when the player picks which discard card to lose during long rest.
    func resolveLongRest(characterID: String, discardIndex: Int) {
        guard let gameManager = gameManager,
              let character = gameManager.game.characters.first(where: { $0.id == characterID }) else { return }

        pendingLongRest = nil

        // Lose the chosen card
        guard discardIndex < character.discardedCards.count else { return }
        let lostCard = character.discardedCards.remove(at: discardIndex)
        character.lostCards.append(lostCard)

        // Recover remaining discard to hand
        character.handCards.append(contentsOf: character.discardedCards)
        character.discardedCards.removeAll()

        // Heal 2
        gameManager.entityManager.changeHealth(character, amount: 2)

        let deckName = character.characterData?.deck ?? character.name
        let deckData = gameManager.editionStore.deckData(name: deckName, edition: character.edition)
        let cardName = deckData?.abilities.first(where: { $0.cardId == lostCard })?.name ?? "Card \(lostCard)"
        log("\(characterID): Long Rest — Heal 2, lost \(cardName), recovered \(character.handCards.count) cards", category: .rest)

        // Continue to next figure
        advanceToNextFigure()
    }

    // MARK: - Short Rest

    /// Pending short rest awaiting player's decision (accept / reroll / skip).
    struct PendingShortRest: Identifiable {
        let id = UUID()
        let characterID: String
        /// The card ID randomly selected from discard to be lost.
        var randomCardId: Int
        /// Whether the player already used the re-pick option (costs 1 HP).
        var rerollUsed: Bool = false
    }

    /// Non-nil when a character is being offered a short rest at end of round.
    var pendingShortRest: PendingShortRest?

    /// Characters that performed a long rest this round (skip short rest for them).
    private var longRestedCharacterIDs: Set<String> = []

    /// Begin offering short rests to eligible characters at end of round.
    private func offerShortRests() {
        guard let gameManager = gameManager else {
            proceedAfterShortRests()
            return
        }

        // Record which characters long-rested this round
        longRestedCharacterIDs = Set(
            gameManager.game.activeCharacters
                .filter { $0.longRest }
                .map { $0.id }
        )

        advanceToNextShortRest(startingAfter: nil)
    }

    /// Find the next eligible character for short rest, or proceed to card selection.
    private func advanceToNextShortRest(startingAfter characterID: String?) {
        guard let gameManager = gameManager else {
            proceedAfterShortRests()
            return
        }

        let active = gameManager.game.activeCharacters.filter { !$0.exhausted && !$0.absent }
        let startIndex: Int
        if let afterID = characterID,
           let idx = active.firstIndex(where: { $0.id == afterID }) {
            startIndex = idx + 1
        } else {
            startIndex = 0
        }

        for i in startIndex..<active.count {
            let character = active[i]
            // Skip characters that long-rested (they already recovered)
            guard !longRestedCharacterIDs.contains(character.id) else { continue }
            // Need at least 2 discarded cards to short rest
            guard character.discardedCards.count >= 2 else { continue }

            // Pick a random card from the discard pile
            let randomCardId = character.discardedCards.randomElement()!
            pendingShortRest = PendingShortRest(
                characterID: character.id,
                randomCardId: randomCardId
            )
            return
        }

        // No more eligible characters
        proceedAfterShortRests()
    }

    /// Player accepts the short rest — lose the random card, recover remaining discard to hand.
    func resolveShortRest() {
        guard let gameManager = gameManager,
              let pending = pendingShortRest,
              let character = gameManager.game.characters.first(where: { $0.id == pending.characterID }) else { return }

        let lostCardId = pending.randomCardId

        // Remove the lost card from discard
        if let idx = character.discardedCards.firstIndex(of: lostCardId) {
            character.discardedCards.remove(at: idx)
        }
        character.lostCards.append(lostCardId)

        // Recover remaining discard to hand
        character.handCards.append(contentsOf: character.discardedCards)
        character.discardedCards.removeAll()

        let deckName = character.characterData?.deck ?? character.name
        let deckData = gameManager.editionStore.deckData(name: deckName, edition: character.edition)
        let cardName = deckData?.abilities.first(where: { $0.cardId == lostCardId })?.name ?? "Card \(lostCardId)"
        log("\(character.id): Short Rest — lost \(cardName), recovered \(character.handCards.count) cards to hand", category: .rest)

        let charID = pending.characterID
        pendingShortRest = nil
        advanceToNextShortRest(startingAfter: charID)
    }

    /// Player takes 1 damage to re-pick a different random card.
    func rerollShortRest() {
        guard let gameManager = gameManager,
              var pending = pendingShortRest,
              !pending.rerollUsed,
              let character = gameManager.game.characters.first(where: { $0.id == pending.characterID }) else { return }

        // Apply 1 damage
        gameManager.entityManager.changeHealth(character, amount: -1)
        log("\(character.id): Short Rest — took 1 damage to re-pick", category: .rest)

        pending.rerollUsed = true

        // Pick a new random card, different from the current one if possible
        let candidates = character.discardedCards.filter { $0 != pending.randomCardId }
        if let newCard = candidates.randomElement() {
            pending.randomCardId = newCard
        }
        // If no other candidates exist, keep the same card (only 1 unique card ID scenario — unlikely with >=2 cards)

        pendingShortRest = pending
    }

    /// Player declines the short rest — cards stay as-is.
    func skipShortRest() {
        guard let pending = pendingShortRest else { return }
        let charID = pending.characterID
        log("\(charID): Skipped short rest", category: .rest)
        pendingShortRest = nil
        advanceToNextShortRest(startingAfter: charID)
    }

    /// Continue with end-of-round cleanup after all short rests are resolved.
    private func proceedAfterShortRests() {
        guard let gameManager = gameManager else { return }

        longRestedCharacterIDs = []

        // Original endRound() cleanup
        gameManager.roundManager.nextGameState()
        log("Round \(gameManager.game.round) complete", category: .round)

        checkVictoryDefeat()
        if scenarioResult != nil { return }

        beginCardSelection()
    }

    // MARK: - Modifier Card Display

    /// The last drawn attack modifier card (for popup display).
    var lastDrawnModifier: AttackModifier? = nil

    /// Whether to show the modifier card popup.
    var showModifierCard: Bool = false

    // MARK: - Card Image Preview

    /// The cardId of the card whose full image is being previewed (nil = no preview).
    var previewCardId: Int?

    /// Show the full-size card image preview overlay.
    func showCardPreview(cardId: Int) {
        previewCardId = cardId
    }

    /// Dismiss the card image preview overlay.
    func dismissCardPreview() {
        previewCardId = nil
    }

    /// Scenario outcome (nil while in progress).
    var scenarioResult: ScenarioResult?

    enum ScenarioResult {
        case victory
        case defeat
    }

    // MARK: - Init

    init() {
        self.boardState = BoardState()
    }

    // MARK: - Scenario Setup

    /// Initialize the board for a scenario.
    func startScenario(scenario: VGBScenario, playerCount: Int) {
        self.scenarioData = scenario
        self.boardState = BoardBuilder.build(from: scenario, playerCount: playerCount)
        self.scenarioResult = nil

        // Create the SpriteKit scene
        let scene = BoardScene(size: CGSize(width: 1200, height: 800))
        scene.scaleMode = .resizeFill
        scene.onHexTap = { [weak self] coord in self?.handleHexTap(coord) }
        scene.onPieceTap = { [weak self] piece in self?.handlePieceTap(piece) }
        self.boardScene = scene

        // Compute offset
        let padding = 2
        offsetCol = boardState.bounds.minCol - padding
        offsetRow = boardState.bounds.minRow - padding

        // Build the visual board with character appearance data
        scene.buildBoard(from: boardState, scenario: scenario, offsetCol: offsetCol, offsetRow: offsetRow,
                         characterAppearances: buildCharacterAppearances())

        boardPhase = .setup
        turnLog = []
        log("Scenario \(scenario.id): \(scenario.title)", category: .setup)
        log("\(boardState.startingLocations.count) starting locations available", category: .setup)
    }

    /// Tear down the board and return to the main menu.
    func exitBoard() {
        gameManager?.appPhase = .mainMenu
        boardScene = nil
        scenarioData = nil
        boardState = BoardState()
        boardPhase = .setup
        interactionMode = .idle
        turnOrder = []
        currentTurnIndex = -1
        activePlayerTurn = nil
        monsterTurnController = nil
        summonTurnController = nil
        pendingSummonPlacement = nil
        pendingShortRest = nil
        cardSelectionsComplete = []
        cardSelectingCharacterID = nil
        scenarioResult = nil
    }

    // MARK: - Character Placement (Setup Phase)

    /// Begin placing a character on a starting location.
    func beginPlaceCharacter(characterID: String) {
        guard boardPhase == .setup else { return }
        interactionMode = .placingCharacter(characterID: characterID)

        // Highlight available starting locations
        let occupied = Set(boardState.piecePositions.values)
        let available = Set(boardState.startingLocations.filter { !occupied.contains($0) })
        boardScene?.highlightHexes(available, color: .yellow, offsetCol: offsetCol, offsetRow: offsetRow)
    }

    /// Place a character on a starting hex.
    func placeCharacter(characterID: String, at coord: HexCoord) {
        guard boardState.startingLocations.contains(coord),
              !boardState.isOccupied(coord) else { return }

        let pieceID = PieceID.character(characterID)
        boardState.placePiece(pieceID, at: coord)

        // Ensure character appearance data is stored before placing
        let appearances = buildCharacterAppearances()
        for (id, appearance) in appearances {
            boardScene?.storedAppearances[id] = appearance
        }

        boardScene?.addPieceSprite(id: pieceID, at: coord, offsetCol: offsetCol, offsetRow: offsetRow)
        boardScene?.clearHighlights()
        interactionMode = .idle
        log("Placed \(characterID) at (\(coord.col), \(coord.row))", category: .setup)
    }

    /// Place a summon on a chosen hex during interactive summon placement.
    func placeSummon(summonID: String, characterID: String, at coord: HexCoord) {
        let summonPieceID = PieceID.summon(id: summonID)
        boardState.placePiece(summonPieceID, at: coord)
        boardScene?.addPieceSprite(id: summonPieceID, at: coord, offsetCol: offsetCol, offsetRow: offsetRow)
        boardScene?.clearHighlights()
        pendingSummonPlacement = nil
        interactionMode = .idle
        log("\(characterID): Summon placed at (\(coord.col), \(coord.row))", category: .info)

        // Advance the player turn controller past the async summon action
        activePlayerTurn?.advanceAfterAsyncAction()
    }

    /// Finish setup phase and begin the first round.
    func finishSetup() {
        guard boardPhase == .setup else { return }
        boardScene?.clearHighlights()
        interactionMode = .idle
        logRoundHeader(1)
        beginCardSelection()
    }

    // MARK: - Card Selection Phase

    /// Start the card selection phase for a new round.
    func beginCardSelection() {
        guard let gameManager = gameManager else { return }

        boardPhase = .cardSelection
        cardSelectionsComplete = []
        cardSelectingCharacterID = nil
        selectedCardPairs = [:]

        logRoundHeader(gameManager.game.round + 1)

        // Process exhaustion and auto-rests, then find the first character needing manual selection
        advanceToNextCardSelection()
    }

    /// Store the selected card pair for a character during card selection.
    func storeSelectedCards(for characterID: String, top: AbilityModel, bottom: AbilityModel) {
        selectedCardPairs[characterID] = (top: top, bottom: bottom)
    }

    /// Mark a character's card selection as complete and advance to the next.
    func completeCardSelection(for characterID: String) {
        cardSelectionsComplete.insert(characterID)
        advanceToNextCardSelection()
    }

    /// Find the next character that needs card selection, handling exhaustion and forced long rests.
    private func advanceToNextCardSelection() {
        guard let gameManager = gameManager else { return }
        let active = gameManager.game.activeCharacters.filter { !$0.exhausted && !$0.absent }

        // Process characters in order
        for character in active {
            guard !cardSelectionsComplete.contains(character.id) else { continue }

            let handCount = character.handCards.count
            let discardCount = character.discardedCards.count

            if handCount >= 2 {
                // Normal: can select 2 cards (long rest also available if discard >= 2)
                cardSelectingCharacterID = character.id
                return
            } else if discardCount >= 2 {
                // Forced long rest: not enough hand cards but can rest
                character.initiative = 99
                character.longRest = true
                log("\(character.id): Forced long rest (only \(handCount) hand card\(handCount == 1 ? "" : "s"))", category: .rest)
                cardSelectionsComplete.insert(character.id)
                // Continue to next character
            } else {
                // Exhausted: fewer than 2 hand cards AND fewer than 2 discard cards
                character.exhausted = true
                log("\(character.id): Exhausted! (\(handCount) hand, \(discardCount) discard)", category: .death)

                // Remove from board
                let pieceID = PieceID.character(character.id)
                boardState.removePiece(pieceID)
                boardScene?.removePieceSprite(id: pieceID)

                cardSelectionsComplete.insert(character.id)
                // Continue to next character
            }
        }

        // All characters processed — check if anyone is left alive
        let nonExhausted = active.filter { !$0.exhausted }
        if nonExhausted.isEmpty {
            // All exhausted — defeat
            checkVictoryDefeat()
            if scenarioResult != nil { return }
        }

        // All selections complete — transition to execution
        cardSelectingCharacterID = nil
        beginExecution()
    }

    // MARK: - Execution Phase

    /// Transition from card selection to execution. Advances the round via RoundManager.
    private func beginExecution() {
        guard let gameManager = gameManager else { return }

        // Advance the round (draws monster abilities, sorts by initiative)
        gameManager.roundManager.nextGameState()

        boardPhase = .execution

        // Log monster ability draws
        for monster in gameManager.game.monsters where !monster.off && !monster.aliveEntities.isEmpty {
            if let ability = gameManager.monsterManager.currentAbility(for: monster) {
                log("\(monster.name): drew \(ability.name ?? "ability") (initiative \(ability.initiative))")
            }
        }

        // Build turn order from sorted figures
        turnOrder = gameManager.game.figures.compactMap { figure in
            switch figure {
            case .character(let c) where c.exhausted || c.absent:
                return nil
            case .character(let c) where c.longRest:
                return TurnOrderEntry(figure: figure, initiative: 99)
            case .character(let c):
                return TurnOrderEntry(figure: figure, initiative: c.effectiveInitiative)
            case .monster(let m) where !m.off && !m.aliveEntities.isEmpty:
                // Use monsterManager to get the real initiative from the drawn ability card
                let init_ = gameManager.monsterManager.currentAbilityInitiative(for: m)
                return TurnOrderEntry(figure: figure, initiative: Double(init_ ?? 99))
            case .objective(let o) where !o.off:
                return TurnOrderEntry(figure: figure, initiative: Double(o.initiative) - 0.5)
            default:
                return nil
            }
        }.sorted { $0.initiative < $1.initiative }

        currentTurnIndex = -1
        refreshInvisibility()
        let orderDesc = turnOrder.map { entry in
            let name: String
            switch entry.figure {
            case .character(let c): name = c.title.isEmpty ? c.name : c.title
            case .monster(let m): name = m.name
            case .objective(let o): name = o.name
            }
            return "\(name)(\(Int(entry.initiative)))"
        }.joined(separator: ", ")
        log("Turn order: \(orderDesc)", category: .round)
        advanceToNextFigure()
    }

    /// Advance to the next figure in initiative order.
    func advanceToNextFigure() {
        guard let gameManager = gameManager else { return }
        refreshInvisibility()

        // Mark current as completed
        if currentTurnIndex >= 0 && currentTurnIndex < turnOrder.count {
            turnOrder[currentTurnIndex].completed = true
            // Toggle off the current figure
            gameManager.roundManager.toggleFigure(turnOrder[currentTurnIndex].figure)
        }

        activePlayerTurn = nil
        currentTurnIndex += 1

        // Check if we're done
        if currentTurnIndex >= turnOrder.count {
            endRound()
            return
        }

        let entry = turnOrder[currentTurnIndex]

        switch entry.figure {
        case .character(let character):
            if character.longRest {
                // Long rest — player must choose which discard card to lose
                gameManager.roundManager.toggleFigure(entry.figure) // toggle on

                if character.discardedCards.isEmpty {
                    // No discard cards (shouldn't happen, but safety)
                    log("\(character.id): Long rest (no cards to lose)", category: .rest)
                    advanceToNextFigure()
                } else if character.discardedCards.count == 1 {
                    // Only 1 discard card — auto-choose it
                    resolveLongRest(characterID: character.id, discardIndex: 0)
                } else {
                    // Show prompt for player to choose which card to lose
                    log("\(character.id): Long rest — choose a card to lose", category: .rest)
                    pendingLongRest = PendingLongRest(characterID: character.id)
                }
            } else {
                // Player turn — toggle on
                gameManager.roundManager.toggleFigure(entry.figure) // toggle on
                selectedPiece = .character(character.id)

                // Check if character has living summons that need to act first
                let livingSummons = character.summons.filter { !$0.dead && $0.health > 0 }
                if !livingSummons.isEmpty {
                    interactionMode = .watchingMonsterTurn
                    log("\(character.id): Summons acting first...", category: .round)

                    let controller = SummonTurnController(coordinator: self, gameManager: gameManager)
                    self.summonTurnController = controller

                    Task { @MainActor in
                        await controller.executeSummonTurns(for: character)
                        self.summonTurnController = nil
                        self.checkVictoryDefeat()
                        if self.scenarioResult == nil {
                            self.beginPlayerTurnAfterSummons(character: character)
                        }
                    }
                } else {
                    beginPlayerTurnAfterSummons(character: character)
                }
            }

        case .monster(let monster):
            // Monster turn — automated
            gameManager.roundManager.toggleFigure(entry.figure) // toggle on
            interactionMode = .watchingMonsterTurn
            log("\(monster.name): Monster turn begins", category: .round)

            let controller = MonsterTurnController(coordinator: self, gameManager: gameManager)
            self.monsterTurnController = controller

            Task { @MainActor in
                await controller.executeMonsterGroup(monster)
                self.monsterTurnController = nil
                self.checkVictoryDefeat()
                if self.scenarioResult == nil {
                    self.advanceToNextFigure()
                }
            }

        case .objective:
            // Objectives don't take actions, just skip
            gameManager.roundManager.toggleFigure(entry.figure) // toggle on
            advanceToNextFigure()
        }
    }

    /// Create the PlayerTurnController after summon turns complete.
    private func beginPlayerTurnAfterSummons(character: GameCharacter) {
        guard let gameManager = gameManager else { return }
        let ptc = PlayerTurnController(
            characterID: character.id,
            coordinator: self,
            gameManager: gameManager
        )
        activePlayerTurn = ptc

        // Feed in the cards selected during card selection phase
        if let pair = selectedCardPairs[character.id] {
            ptc.selectCards(top: pair.top, bottom: pair.bottom)
            log("\(character.id): Turn begins — TOP: \(pair.top.name ?? "?") / BTM: \(pair.bottom.name ?? "?")", category: .round)
        } else {
            log("\(character.id): Turn begins (no cards selected)", category: .round)
        }
        interactionMode = .idle
    }

    /// Called when the player finishes their turn (all actions done or skipped).
    func finishPlayerTurn() {
        checkVictoryDefeat()
        if scenarioResult == nil {
            advanceToNextFigure()
        }
    }

    // MARK: - End of Round

    private func endRound() {
        // Offer short rests before transitioning to the next round
        offerShortRests()
    }

    // MARK: - Victory / Defeat

    func checkVictoryDefeat() {
        guard let gameManager = gameManager, scenarioResult == nil else { return }

        // Victory: all monsters dead across all revealed rooms
        // (We check if all monster groups have no alive entities and all rooms are revealed)
        let allMonstersDead = gameManager.game.monsters.allSatisfy { monster in
            monster.off || monster.aliveEntities.isEmpty
        }
        let allRoomsRevealed = boardState.doors.allSatisfy { $0.isOpen }

        if allMonstersDead && allRoomsRevealed && gameManager.game.round > 0 {
            scenarioResult = .victory
            boardPhase = .scenarioEnd
            interactionMode = .idle
            log("VICTORY! All enemies defeated.", category: .round)
            return
        }

        // Defeat: all characters exhausted
        let allExhausted = gameManager.game.activeCharacters.allSatisfy { $0.exhausted }
        if allExhausted && !gameManager.game.activeCharacters.isEmpty {
            scenarioResult = .defeat
            boardPhase = .scenarioEnd
            interactionMode = .idle
            log("DEFEAT! All characters exhausted.", category: .death)
        }
    }

    /// Apply scenario result and clean up.
    func confirmScenarioEnd() {
        guard let gameManager = gameManager, let result = scenarioResult else { return }

        gameManager.scenarioManager.finishScenario(success: result == .victory)
        exitBoard()
    }

    // MARK: - Turn Execution Actions

    /// Begin a player's move action.
    func beginMoveAction(pieceID: PieceID, moveRange: Int) {
        guard let pos = boardState.piecePositions[pieceID] else { return }

        let enemyPositions = Set(boardState.piecePositions.compactMap { id, coord -> HexCoord? in
            if case .monster = id { return coord }
            return nil
        })
        let allyPositions = Set(boardState.piecePositions.compactMap { id, coord -> HexCoord? in
            if case .character = id, id != pieceID { return coord }
            return nil
        })

        let reachable = Pathfinder.reachableHexes(
            board: boardState, from: pos, range: moveRange,
            occupiedByEnemy: enemyPositions, occupiedByAlly: allyPositions
        )

        let validHexes = Set(reachable.keys)
        interactionMode = .selectingMove(pieceID: pieceID, range: moveRange, validHexes: validHexes)
        boardScene?.highlightHexes(validHexes, color: .cyan, offsetCol: offsetCol, offsetRow: offsetRow)
    }

    /// Execute a move to a target hex.
    func executeMove(pieceID: PieceID, to target: HexCoord) {
        guard let pos = boardState.piecePositions[pieceID] else { return }

        let enemyPositions = Set(boardState.piecePositions.compactMap { id, coord -> HexCoord? in
            if case .monster = id { return coord }
            return nil
        })

        guard let path = Pathfinder.findPath(
            board: boardState, from: pos, to: target,
            occupiedByEnemy: enemyPositions
        ) else { return }

        boardScene?.clearHighlights()
        boardScene?.movePiece(id: pieceID, along: path, offsetCol: offsetCol, offsetRow: offsetRow) { [weak self] in
            self?.boardState.movePiece(pieceID, to: target)
            self?.interactionMode = .idle
            self?.log("\(pieceID): Moved to (\(target.col), \(target.row))", category: .move)

            // Check if character stepped on a trap
            self?.checkForTrap(pieceID: pieceID, at: target, flying: false)

            // Check if character stepped on a closed door
            self?.checkForDoorReveal(from: target)
        }
    }

    /// Begin a player's attack action.
    func beginAttackAction(pieceID: PieceID, range: Int, targetCount: Int = 1) {
        guard let pos = boardState.piecePositions[pieceID] else { return }

        var validTargets = Set<PieceID>()
        for (id, coord) in boardState.piecePositions {
            if case .monster(let name, let standee) = id {
                // Exclude invisible monsters
                if let monster = gameManager?.game.monsters.first(where: { $0.name == name }),
                   let entity = monster.entities.first(where: { $0.number == standee }),
                   entity.entityConditions.contains(where: { $0.name == .invisible && !$0.expired }) {
                    continue
                }
                if pos.distance(to: coord) <= range &&
                   LineOfSight.hasLOS(from: pos, to: coord, board: boardState) {
                    validTargets.insert(id)
                }
            }
        }

        if validTargets.isEmpty {
            log("\(pieceID): No valid targets in range \(range)", category: .attack)
            interactionMode = .idle
            return
        }

        if targetCount > 1 {
            interactionMode = .selectingMultiAttackTargets(
                pieceID: pieceID, range: range, validTargets: validTargets,
                targetCount: targetCount, selected: []
            )
            log("\(pieceID): Select up to \(targetCount) targets", category: .attack)
        } else {
            interactionMode = .selectingAttackTarget(pieceID: pieceID, range: range, validTargets: validTargets)
        }
        let targetHexes = Set(validTargets.compactMap { boardState.piecePositions[$0] })
        boardScene?.highlightHexes(targetHexes, color: .red, offsetCol: offsetCol, offsetRow: offsetRow)
    }

    /// Resolve a player attack on a single target. Called once per target.
    /// When `advanceAction` is true (default), calls `advanceAfterAsyncAction()` when done.
    /// Pass false when resolving multiple targets — the caller advances after all are resolved.
    func resolvePlayerAttack(attacker: PieceID, target: PieceID, attackValue: Int, range: Int, advanceAction: Bool = true) {
        guard let gameManager = gameManager,
              let attackerPos = boardState.piecePositions[attacker],
              let targetPos = boardState.piecePositions[target] else { return }

        // Track last attack target for standalone push/pull actions
        lastAttackTarget = target
        lastAttackerPos = attackerPos

        // Read pierce/conditions from the active player turn
        let pierce = activePlayerTurn?.pendingPierce ?? 0
        let conditions = activePlayerTurn?.pendingConditions ?? []

        // Get defender info
        var defenderHealth = 0
        var defenderShield = 0
        var retInfo: (value: Int, range: Int) = (0, 1)
        var isPoisoned = false

        if case .monster(let name, let standee) = target,
           let monster = gameManager.game.monsters.first(where: { $0.name == name }),
           let entity = monster.entities.first(where: { $0.number == standee }) {
            defenderHealth = entity.health
            defenderShield = CombatResolver.totalShield(shield: entity.shield, shieldPersistent: entity.shieldPersistent)
            retInfo = CombatResolver.retaliateInfo(retaliate: entity.retaliate, retaliatePersistent: entity.retaliatePersistent)
            isPoisoned = entity.entityConditions.contains(where: { $0.name == .poison && !$0.expired })
        }

        // Determine advantage/disadvantage
        let isRangedAdjacent = range > 1 && attackerPos.isAdjacent(to: targetPos)

        // Get attacker's character for modifier deck — each target draws separately
        var drawModifier: () -> AttackModifier? = { nil }
        if case .character(let charID) = attacker,
           let character = gameManager.game.characters.first(where: { $0.id == charID }) {
            drawModifier = { gameManager.attackModifierManager.drawCharacterCard(for: character) }
        }

        let result = CombatResolver.resolveAttack(
            attacker: attacker,
            defender: target,
            baseAttack: attackValue,
            advantage: false,
            disadvantage: isRangedAdjacent,
            isPoisoned: isPoisoned,
            shield: defenderShield,
            pierce: pierce,
            conditions: conditions,
            retaliateValue: retInfo.value,
            retaliateRange: retInfo.range,
            attackerDefenderDistance: attackerPos.distance(to: targetPos),
            drawModifier: drawModifier,
            defenderHealth: defenderHealth
        )

        // Show modifier card popup
        if let mod = result.modifierCard {
            lastDrawnModifier = mod
            showModifierCard = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                self?.showModifierCard = false
            }
        }

        log("\(attacker): Attack \(target) — \(result.damage) damage", category: .attack)

        // Apply damage
        if result.damage > 0 {
            if case .monster(let name, let standee) = target,
               let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                gameManager.entityManager.changeHealth(entity, amount: -result.damage)
                boardScene?.pieceDamage(id: target, amount: result.damage)
            }
        }

        // Apply conditions to target
        if !result.appliedConditions.isEmpty {
            if case .monster(let name, let standee) = target,
               let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                for condition in result.appliedConditions {
                    gameManager.entityManager.addCondition(condition, to: entity)
                    log("  \(target): \(condition.rawValue) applied", category: .condition)
                }
            }
        }

        // Retaliate (happens even if target dies or gets pushed)
        if result.retaliateDamage > 0 {
            log("\(attacker): Takes \(result.retaliateDamage) retaliate damage", category: .damage)
            if case .character(let charID) = attacker,
               let character = gameManager.game.characters.first(where: { $0.id == charID }) {
                gameManager.entityManager.changeHealth(character, amount: -result.retaliateDamage)
            }
        }

        if result.killed {
            log("\(target): Killed!", category: .death)
            boardState.removePiece(target)
            boardScene?.removePieceSprite(id: target)
            if case .monster(let name, let standee) = target,
               let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                entity.dead = true
            }
            checkVictoryDefeat()
            boardScene?.clearHighlights()
            interactionMode = .idle
            if advanceAction { activePlayerTurn?.advanceAfterAsyncAction() }
            return
        }

        // Push/Pull: if target survived and attacker has pending push or pull, begin the flow.
        // The push/pull flow is async — it will call advanceAfterAsyncAction() when done.
        if advanceAction {
            let pushSteps = activePlayerTurn?.pendingPush ?? 0
            let pullSteps = activePlayerTurn?.pendingPull ?? 0

            if pushSteps > 0 {
                boardScene?.clearHighlights()
                beginPushPull(target: target, attackerPos: attackerPos, remainingSteps: pushSteps, isPush: true)
                return
            }

            if pullSteps > 0 {
                boardScene?.clearHighlights()
                beginPushPull(target: target, attackerPos: attackerPos, remainingSteps: pullSteps, isPush: false)
                return
            }
        }

        boardScene?.clearHighlights()
        interactionMode = .idle
        if advanceAction { activePlayerTurn?.advanceAfterAsyncAction() }
    }

    // MARK: - Push / Pull

    /// Begin a standalone push/pull action (top-level action, not attack sub-action).
    /// Uses the last attack target to determine who to push/pull.
    func beginStandalonePushPull(steps: Int, isPush: Bool) {
        guard let target = lastAttackTarget,
              let attackerPos = lastAttackerPos,
              boardState.piecePositions[target] != nil else {
            let label = isPush ? "Push" : "Pull"
            log("No target to \(label)", category: .move)
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }
        beginPushPull(target: target, attackerPos: attackerPos, remainingSteps: steps, isPush: isPush)
    }

    /// Start the interactive push/pull flow for a target after an attack.
    func beginPushPull(target: PieceID, attackerPos: HexCoord, remainingSteps: Int, isPush: Bool) {
        guard remainingSteps > 0,
              let targetPos = boardState.piecePositions[target] else {
            // Done — restore idle and advance turn
            interactionMode = .idle
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }

        // Compute candidate hexes
        let candidates: [HexCoord]
        if isPush {
            candidates = targetPos.pushCandidates(awayFrom: attackerPos)
        } else {
            candidates = targetPos.pullCandidates(toward: attackerPos)
        }

        // Filter to passable + unoccupied (push/pull ignores difficult terrain but needs passable hex)
        let valid = candidates.filter { coord in
            boardState.isPassable(coord) && !boardState.isOccupied(coord)
        }

        if valid.isEmpty {
            let label = isPush ? "Push" : "Pull"
            log("  \(target): No room to \(label) further", category: .move)
            interactionMode = .idle
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }

        if valid.count == 1 {
            // Auto-move (only one option)
            executePushPullStep(target: target, to: valid[0], attackerPos: attackerPos, remainingSteps: remainingSteps, isPush: isPush)
        } else {
            // Multiple options — let the player choose
            let validSet = Set(valid)
            interactionMode = .selectingPushPullHex(
                target: target, attackerPos: attackerPos, validHexes: validSet,
                remainingSteps: remainingSteps, isPush: isPush
            )
            boardScene?.highlightHexes(validSet, color: isPush ? .orange : .cyan, offsetCol: offsetCol, offsetRow: offsetRow)
        }
    }

    /// Execute one step of a push/pull: move the target, then recurse or finish.
    func executePushPullStep(target: PieceID, to destination: HexCoord, attackerPos: HexCoord, remainingSteps: Int, isPush: Bool) {
        guard let currentPos = boardState.piecePositions[target] else { return }

        boardScene?.clearHighlights()

        // Move in board state
        boardState.movePiece(target, to: destination)

        // Animate the move
        let path = [currentPos, destination]
        boardScene?.movePiece(id: target, along: path, offsetCol: offsetCol, offsetRow: offsetRow) { [weak self] in
            guard let self = self else { return }

            let stepsLeft = remainingSteps - 1
            let label = isPush ? "Push" : "Pull"

            if stepsLeft > 0 {
                // More steps remaining — recurse
                self.beginPushPull(target: target, attackerPos: attackerPos, remainingSteps: stepsLeft, isPush: isPush)
            } else {
                // All steps done — check for traps at final position, then finish
                self.log("  \(target): \(label) to (\(destination.col), \(destination.row))", category: .move)
                self.checkForTrap(pieceID: target, at: destination, flying: false)
                self.interactionMode = .idle
                self.activePlayerTurn?.advanceAfterAsyncAction()
            }
        }
    }

    // MARK: - Trap Triggering

    /// Check if a piece landed on a trap and trigger it.
    /// Flying figures are immune to traps. Jumping figures trigger traps on the destination only
    /// (handled by the caller — intermediate hexes are skipped by Pathfinder).
    func checkForTrap(pieceID: PieceID, at coord: HexCoord, flying: Bool) {
        guard !flying else { return }
        guard let cell = boardState.cells[coord], cell.isTrap else { return }
        guard let gameManager = gameManager else { return }

        let damage = cell.trapDamage ?? 2
        let subType = cell.overlaySubType

        // Apply damage
        applyTrapDamage(damage, to: pieceID, gameManager: gameManager)

        // Apply conditions (e.g., poison trap)
        if subType == "poison" {
            applyTrapCondition(.poison, to: pieceID, gameManager: gameManager)
        }

        // Visual feedback
        boardScene?.pieceDamage(id: pieceID, amount: damage)
        log("\(pieceID): Triggered \(subType ?? "trap") trap for \(damage) damage", category: .damage)

        // Remove the trap from board state
        boardState.removeTrap(at: coord)

        // Remove the trap sprite visually
        boardScene?.removeOverlaySprite(at: coord, offsetCol: offsetCol, offsetRow: offsetRow)

        // Check if figure died
        checkTrapDeath(pieceID: pieceID, gameManager: gameManager)
    }

    /// Apply trap damage to the entity behind a PieceID.
    private func applyTrapDamage(_ damage: Int, to pieceID: PieceID, gameManager: GameManager) {
        switch pieceID {
        case .character(let charID):
            if let character = gameManager.game.characters.first(where: { $0.id == charID }) {
                gameManager.entityManager.changeHealth(character, amount: -damage)
            }
        case .monster(let name, let standee):
            if let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                gameManager.entityManager.changeHealth(entity, amount: -damage)
            }
        case .summon(let summonID):
            for char in gameManager.game.characters {
                if let summon = char.summons.first(where: { $0.id == summonID }) {
                    gameManager.entityManager.changeHealth(summon, amount: -damage)
                    break
                }
            }
        default:
            break
        }
    }

    /// Apply a condition from a trap to the entity behind a PieceID.
    private func applyTrapCondition(_ condition: ConditionName, to pieceID: PieceID, gameManager: GameManager) {
        switch pieceID {
        case .character(let charID):
            if let character = gameManager.game.characters.first(where: { $0.id == charID }) {
                gameManager.entityManager.addCondition(condition, to: character)
                log("  \(pieceID): \(condition.rawValue) applied", category: .condition)
            }
        case .monster(let name, let standee):
            if let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                gameManager.entityManager.addCondition(condition, to: entity)
                log("  \(pieceID): \(condition.rawValue) applied", category: .condition)
            }
        case .summon(let summonID):
            for char in gameManager.game.characters {
                if let summon = char.summons.first(where: { $0.id == summonID }) {
                    gameManager.entityManager.addCondition(condition, to: summon)
                    log("  \(pieceID): \(condition.rawValue) applied", category: .condition)
                    break
                }
            }
        default:
            break
        }
    }

    /// Check if a figure died from trap damage and clean up.
    private func checkTrapDeath(pieceID: PieceID, gameManager: GameManager) {
        switch pieceID {
        case .character(let charID):
            if let character = gameManager.game.characters.first(where: { $0.id == charID }),
               character.health <= 0 {
                log("\(pieceID): Killed by trap!", category: .death)
                boardState.removePiece(pieceID)
                boardScene?.removePieceSprite(id: pieceID)
                checkVictoryDefeat()
            }
        case .monster(let name, let standee):
            if let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }),
               entity.health <= 0 {
                entity.dead = true
                log("\(pieceID): Killed by trap!", category: .death)
                boardState.removePiece(pieceID)
                boardScene?.removePieceSprite(id: pieceID)
                checkVictoryDefeat()
            }
        case .summon(let summonID):
            for char in gameManager.game.characters {
                if let summon = char.summons.first(where: { $0.id == summonID }),
                   summon.health <= 0 {
                    summon.dead = true
                    log("\(pieceID): Killed by trap!", category: .death)
                    boardState.removePiece(pieceID)
                    boardScene?.removePieceSprite(id: pieceID)
                    break
                }
            }
        default:
            break
        }
    }

    // MARK: - Room Reveal

    /// Check if the character moved onto a closed door hex — if so, open it automatically.
    /// Per Gloomhaven rules: "if [a character] enters a tile with a closed door, flip the door
    /// tile to the opened side and immediately reveal the adjacent room."
    private func checkForDoorReveal(from coord: HexCoord) {
        // Check if the character is standing ON a closed door
        if let door = boardState.doors.first(where: { $0.coord == coord && !$0.isOpen }) {
            openDoor(at: door.coord)
        }
    }

    /// Get adjacent unopened doors for a position.
    func adjacentDoors(from coord: HexCoord) -> [DoorInfo] {
        boardState.doors.filter { !$0.isOpen && (coord.isAdjacent(to: $0.coord) || coord == $0.coord) }
    }

    /// Open a door and reveal the room behind it.
    func openDoor(at coord: HexCoord) {
        guard let door = boardState.doors.first(where: { $0.coord == coord && !$0.isOpen }),
              let scenario = scenarioData,
              let gameManager = gameManager else { return }

        boardPhase = .roomReveal
        let newMonsters = BoardBuilder.revealRoom(
            door: door, scenario: scenario,
            board: boardState, playerCount: max(2, gameManager.game.activeCharacters.count)
        )

        // Add monster figures to GameState via ScenarioManager
        // The BoardBuilder already placed them on the board; now register with game state
        for (pieceID, _) in newMonsters {
            if case .monster(let name, _) = pieceID {
                // Ensure the monster group exists in game state
                if !gameManager.game.monsters.contains(where: { $0.name == name }) {
                    gameManager.monsterManager.addMonster(name: name, edition: gameManager.game.edition ?? "gh")
                }
            }
        }

        // Rebuild the visual board to include the new room
        boardScene?.buildBoard(from: boardState, scenario: scenario, offsetCol: offsetCol, offsetRow: offsetRow,
                               characterAppearances: buildCharacterAppearances())

        boardPhase = .execution
        log("Door opened — \(door.childTileRef) revealed", category: .door)
        for (id, pos) in newMonsters {
            log("Spawned \(id) at (\(pos.col), \(pos.row))", category: .setup)
        }
    }

    // MARK: - Input Handling

    func handleHexTap(_ coord: HexCoord) {
        switch interactionMode {
        case .placingCharacter(let charID):
            placeCharacter(characterID: charID, at: coord)

        case .selectingMove(let pieceID, _, let validHexes):
            if validHexes.contains(coord) {
                executeMove(pieceID: pieceID, to: coord)
            }

        case .placingSummon(let summonID, let characterID, let validHexes):
            if validHexes.contains(coord) {
                placeSummon(summonID: summonID, characterID: characterID, at: coord)
            }

        case .selectingPushPullHex(let target, let attackerPos, let validHexes, let remaining, let isPush):
            if validHexes.contains(coord) {
                executePushPullStep(target: target, to: coord, attackerPos: attackerPos, remainingSteps: remaining, isPush: isPush)
            }

        default:
            // Check if tapping a door
            if let door = boardState.doors.first(where: { $0.coord == coord && !$0.isOpen }) {
                // Check if any character is adjacent
                let charAdjacentToDoor = boardState.piecePositions.contains { id, pos in
                    if case .character = id {
                        return pos.isAdjacent(to: door.coord) || pos == door.coord
                    }
                    return false
                }
                if charAdjacentToDoor {
                    openDoor(at: coord)
                }
            }
        }
    }

    func handlePieceTap(_ piece: PieceID) {
        switch interactionMode {
        case .selectingAttackTarget(let attackerID, _, let validTargets):
            if validTargets.contains(piece) {
                let attackValue = activePlayerTurn?.currentAttackValue() ?? 2
                let range = activePlayerTurn?.currentAttackRange() ?? 1
                resolvePlayerAttack(attacker: attackerID, target: piece, attackValue: attackValue, range: range)
            }

        case .selectingMultiAttackTargets(let attackerID, let range, let validTargets, let targetCount, var selected):
            if validTargets.contains(piece) && !selected.contains(piece) {
                selected.append(piece)
                log("\(attackerID): Target \(selected.count)/\(targetCount) — \(piece)", category: .attack)

                if selected.count >= targetCount || selected.count >= validTargets.count {
                    // All targets selected — resolve each attack (no push/pull for multi-target)
                    let attackValue = activePlayerTurn?.currentAttackValue() ?? 2
                    let attackRange = activePlayerTurn?.currentAttackRange() ?? 1
                    for target in selected {
                        resolvePlayerAttack(attacker: attackerID, target: target, attackValue: attackValue, range: attackRange, advanceAction: false)
                    }
                    activePlayerTurn?.advanceAfterAsyncAction()
                } else {
                    // Update mode with new selected list, highlight remaining valid targets
                    let remaining = validTargets.subtracting(selected)
                    interactionMode = .selectingMultiAttackTargets(
                        pieceID: attackerID, range: range, validTargets: validTargets,
                        targetCount: targetCount, selected: selected
                    )
                    let targetHexes = Set(remaining.compactMap { boardState.piecePositions[$0] })
                    boardScene?.highlightHexes(targetHexes, color: .red, offsetCol: offsetCol, offsetRow: offsetRow)
                }
            }

        default:
            selectedPiece = piece
        }
    }

    /// Confirm multi-target attack early (fewer targets than allowed).
    func confirmMultiAttack() {
        guard case .selectingMultiAttackTargets(let attackerID, _, _, _, let selected) = interactionMode,
              !selected.isEmpty else { return }

        let attackValue = activePlayerTurn?.currentAttackValue() ?? 2
        let attackRange = activePlayerTurn?.currentAttackRange() ?? 1
        for target in selected {
            resolvePlayerAttack(attacker: attackerID, target: target, attackValue: attackValue, range: attackRange, advanceAction: false)
        }
        activePlayerTurn?.advanceAfterAsyncAction()
    }

    // MARK: - Snapshot

    func snapshot() -> BoardSnapshot {
        BoardSnapshot.from(boardState)
    }

    func restore(from snapshot: BoardSnapshot) {
        snapshot.restore(to: boardState)
        // Rebuild visuals
        if let scenario = scenarioData {
            boardScene?.buildBoard(from: boardState, scenario: scenario, offsetCol: offsetCol, offsetRow: offsetRow,
                                   characterAppearances: buildCharacterAppearances())
        }
    }

    // MARK: - Character Appearances

    /// Build a mapping of character IDs to their visual appearance data (color + thumbnail).
    func buildCharacterAppearances() -> [String: BoardScene.CharacterAppearance] {
        var result: [String: BoardScene.CharacterAppearance] = [:]
        guard let gm = gameManager else { return result }
        for char in gm.game.characters {
            let color = SKColor(hex: char.color) ?? SKColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)
            let thumbnail = ImageLoader.characterThumbnail(edition: char.edition, name: char.name)
            result[char.id] = BoardScene.CharacterAppearance(color: color, thumbnail: thumbnail)
        }
        return result
    }

    // MARK: - Invisibility

    /// Update piece alpha for all characters/summons based on their invisible condition.
    func refreshInvisibility() {
        guard let gameManager = gameManager else { return }
        for character in gameManager.game.characters where !character.exhausted {
            let isInvisible = character.entityConditions.contains { $0.name == .invisible && !$0.expired }
            boardScene?.setPieceAlpha(id: .character(character.id), invisible: isInvisible)

            for summon in character.summons where !summon.dead && summon.health > 0 {
                let summonInvisible = summon.entityConditions.contains { $0.name == .invisible && !$0.expired }
                boardScene?.setPieceAlpha(id: .summon(id: summon.id), invisible: summonInvisible)
            }
        }
        for monster in gameManager.game.monsters where !monster.off {
            for entity in monster.aliveEntities {
                let isInvisible = entity.entityConditions.contains { $0.name == .invisible && !$0.expired }
                boardScene?.setPieceAlpha(id: .monster(name: monster.name, standee: entity.number), invisible: isInvisible)
            }
        }
    }

    // MARK: - Logging

    func log(_ message: String, category: TurnLogCategory = .info) {
        turnLog.append(TurnLogEntry(message: message, category: category))
    }

    func logRoundHeader(_ round: Int) {
        turnLog.append(TurnLogEntry(message: "Round \(round)", category: .round, isRoundHeader: true))
    }
}
