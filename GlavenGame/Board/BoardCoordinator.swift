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
    case selectingMove(pieceID: PieceID, range: Int, validHexes: Set<HexCoord>, teleport: Bool = false,
                       mode: MoveMode = .normal)
    /// Single-target attack selection (targetCount == 1).
    case selectingAttackTarget(pieceID: PieceID, range: Int, validTargets: Set<PieceID>)
    /// Multi-target attack selection (targetCount > 1). Player picks targets one by one.
    case selectingMultiAttackTargets(pieceID: PieceID, range: Int, validTargets: Set<PieceID>, targetCount: Int, selected: [PieceID])
    case placingSummon(summonID: String, characterID: String, validHexes: Set<HexCoord>)
    /// The character picks who performs a printed action: "One adjacent ally may perform Attack
    /// 6" (Possession), "Force one enemy within Range 4 to perform Move 1" (Parasitic Influence).
    case choosingPerformer(pieceID: PieceID, action: ActionModel, candidates: Set<PieceID>)
    /// The character places a trap or obstacle from a card in an empty adjacent hex
    /// (Proximity Mine, Avalanche); `remaining` counts this one.
    case placingToken(pieceID: PieceID, token: PlacedToken, remaining: Int, validHexes: Set<HexCoord>)
    case selectingPushPullHex(target: PieceID, attackerPos: HexCoord, validHexes: Set<HexCoord>, remainingSteps: Int, isPush: Bool)
    /// Player selects a single enemy to apply a condition to.
    case selectingConditionTarget(pieceID: PieceID, condition: ConditionName, validTargets: Set<PieceID>)
    /// Player selects an ally (or self) within range to heal.
    case selectingHealTarget(pieceID: PieceID, healValue: Int, validTargets: Set<PieceID>)
    /// Player selects an enemy to push or pull.
    case selectingForcedMoveTarget(pieceID: PieceID, steps: Int, isPush: Bool, validTargets: Set<PieceID>)
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
    /// Technical detail kept out of the player's view (grid coordinates, raw values) that test
    /// transcripts record alongside the message.
    let trace: String?
    /// The monster decision behind this line, for "Why?".
    var whyID: UUID?

    init(message: String, category: TurnLogCategory = .info, isRoundHeader: Bool = false, trace: String? = nil) {
        self.message = message
        self.category = category
        self.isRoundHeader = isRoundHeader
        self.trace = trace
    }
}

/// Represents a figure in initiative order during the execution phase.
struct TurnOrderEntry: Identifiable {
    let id = UUID()
    let figure: AnyFigure
    let initiative: Double
    var completed: Bool = false
    /// For a monster type that already acted this round: only these newly revealed standees act.
    var onlyStandees: Set<Int>? = nil
    /// A character's second turn this round (Second Chance Ring): their summons don't act again.
    var anotherTurn = false
}

/// Bridge between SpriteKit scene and SwiftUI state.
/// Owns the BoardState and drives the BoardScene.
@Observable
final class BoardCoordinator {

    // MARK: - State

    var boardState: BoardState
    var boardPhase: BoardPhase = .setup
    var interactionMode: InteractionMode = .idle
    /// Conditions the heal being targeted gives whoever it heals (Amputate's stun, a bless enhancement).
    var pendingHealConditions: [ConditionName] = []
    var selectedPiece: PieceID?
    /// The figure whose turn it is, ringed on the board (nil between turns).
    var actingPiece: PieceID?
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

    /// Whether the current turn-order entry's figure was toggled active (start-of-turn processed).
    var currentTurnToggled: Bool = false

    /// Incremented whenever a board starts or is torn down; turn tasks started for an earlier
    /// board stop instead of advancing the new one.
    private(set) var boardGeneration = 0

    /// Monster standees that entered play during the current turn, by monster name; they are
    /// scheduled to act this round when the turn ends.
    var pendingRevealedStandees: [String: Set<Int>] = [:]

    /// A scenario result triggered this round; it takes effect at the end of the round (p.47).
    /// The objective being destroyed right now, while the rules its destruction triggers run:
    /// the letters it carried and where it stood.
    var fallenObjective: (markers: [String], hex: HexCoord)?
    var pendingResult: ScenarioResult?
    /// Why the scenario ended (or will, at the end of the round).
    var endReason: ScenarioEndReason?

    /// How the scenario's brief is showing: as its intro, or reopened from the Goal chip.
    enum BriefPresentation { case intro, reminder }
    var briefPresentation: BriefPresentation?

    /// The goal, ways to lose and special rules of the scenario on the board.
    var scenarioBrief: ScenarioBrief? {
        guard let gameManager, let scenario = gameManager.game.scenario else { return nil }
        // Views read it on every render; it only changes with the scenario.
        if let cached = briefCache, cached.scenarioID == scenario.data.id { return cached.brief }
        let brief = ScenarioBrief.make(for: scenario.data, labels: gameManager.editionStore)
        briefCache = (scenario.data.id, brief)
        return brief
    }
    @ObservationIgnored private var briefCache: (scenarioID: String, brief: ScenarioBrief)?

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
        /// More figures of the same summon still to place (e.g. "Summon two Shadow Wolves").
        var remaining: Int = 0
        var summonData: SummonDataModel? = nil
    }
    var pendingSummonPlacement: PendingSummonPlacement?

    /// The monster turn controller.
    var monsterTurnController: MonsterTurnController?
    var escortTurnController: EscortTurnController?

    /// Characters that have completed card selection this round.
    var cardSelectionsComplete: Set<String> = []

    /// Whether the current character is selecting cards.
    var cardSelectingCharacterID: String?

    /// Selected card pairs from card selection phase. Key = character ID.
    var selectedCardPairs: [String: (top: AbilityModel, bottom: AbilityModel)] = [:]

    // MARK: - Attack Modifier Draw

    /// Context for an interactive attack modifier draw presented to the player before combat resolves.
    struct PendingModifierDraw: Identifiable {
        let id = UUID()
        let attackerPiece: PieceID
        let defenderPiece: PieceID
        let baseAttack: Int
        /// The attack value the two cards of an advantage/disadvantage draw are compared on
        /// (with poison's +1).
        var comparedAttack: Int? = nil
        let advantage: Bool
        let disadvantage: Bool
        /// Draws one card from the appropriate deck (mutates the deck).
        let drawCard: () -> AttackModifier?
        var continuation: CheckedContinuation<[AttackModifier], Never>?
    }

    /// Non-nil when an attack is waiting for the player to draw modifier card(s).
    var pendingModifierDraw: PendingModifierDraw?

    /// The modifier cards of an attack, as the tray beside the board shows them.
    struct ModifierReveal: Identifiable {
        let id = UUID()
        let attacker: PieceID
        let defender: PieceID
        /// Every card drawn, in order (both draws of an advantage attack).
        let drawn: [AttackModifier]
        /// The cards that apply.
        let selected: [AttackModifier]
        let advantage: Bool
        let disadvantage: Bool
        /// Drawn by the player's tap, rather than for a monster or summon.
        let drawnByPlayer: Bool
        /// The attack's sum once it has resolved: "2 + 1 − 1 shield = 2 damage".
        var sum: String?
        /// The same sum as chips, for the tray.
        var chips: [CombatResolver.SumChip] = []

        /// Whether `card` (at `index` in `drawn`) is one of the cards that apply.
        func applies(at index: Int) -> Bool {
            guard drawn.indices.contains(index) else { return false }
            if drawn.count == selected.count { return true }
            let card = drawn[index]
            return selected.contains { $0.id == card.id }
        }
    }

    /// The most recent attack's modifier cards, shown in the tray until the next attack.
    var lastModifierReveal: ModifierReveal?
    /// The conditions the latest heal removed (Poison, Wound), for its log line.
    @ObservationIgnored var lastHealRemoved: [ConditionName] = []

    /// Resolve modifier draws, damage-negation prompts and forced-movement choices automatically
    /// (no player input). Used for headless simulation and tests.
    var autoResolvePrompts = false

    /// Pause between automated figures' turns at normal animation speed.
    static let baseTurnDelayNanoseconds: UInt64 = 400_000_000

    /// Pause between automated figures' turns, for readability (scaled by the Animation Speed setting).
    var turnDelayNanoseconds: UInt64 = BoardCoordinator.baseTurnDelayNanoseconds
    /// The Animation Speed setting last applied (0.5 fast … 2 slow).
    var animationSpeed: Double = 1

    /// Monsters', summons' and escorts' turns held at their next step until resumed.
    var isPaused = false
    /// Monsters', summons' and escorts' turns played at `fastForwardFactor` times the pace,
    /// until a character's turn comes round.
    var isFastForward = false
    /// Automated turns parked by the pause; resuming (or leaving the board) lets them go on.
    var pauseWaiters: [CheckedContinuation<Void, Never>] = []

    /// Called before every attack resolves and every movement starts, with the board as it is at
    /// that moment. The simulation tests use these to check each one against the rules.
    var attackObserver: ((_ attacker: PieceID, _ target: PieceID) -> Void)?
    /// Whether the attack being made was drawn onto another figure than the one aimed at.
    var attackWasRedirected = false
    var moveObserver: ((_ piece: PieceID, _ path: [HexCoord], _ style: MovementStyle) -> Void)?

    /// Non-nil when a monster push/pull is in progress and the async caller is suspended.
    private var pendingPushPullContinuation: CheckedContinuation<Void, Never>?
    /// Moves waiting for their animation to finish, by move. A scene torn down mid-move never
    /// finishes them, so teardown resumes them instead.
    var pendingMoveAnimations: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Finish a pending draw with cards drawn elsewhere (the test policies draw this way).
    func completeModifierDraw(selectedCards: [AttackModifier]) {
        guard let pending = pendingModifierDraw else { return }
        lastModifierReveal = ModifierReveal(attacker: pending.attackerPiece, defender: pending.defenderPiece,
                                            drawn: selectedCards, selected: selectedCards,
                                            advantage: pending.advantage, disadvantage: pending.disadvantage,
                                            drawnByPlayer: true)
        let cont = pending.continuation
        pendingModifierDraw = nil
        cont?.resume(returning: selectedCards)
    }

    /// The player taps the deck: draw the pending attack's cards (both draws with advantage or
    /// disadvantage), show them in the tray and resolve the attack.
    func drawPendingModifiers() {
        guard let pending = pendingModifierDraw else { return }
        let draw = CombatResolver.drawModifiersDetailed(advantage: pending.advantage, disadvantage: pending.disadvantage,
                                                        baseAttack: pending.comparedAttack, draw: pending.drawCard)
        lastModifierReveal = ModifierReveal(attacker: pending.attackerPiece, defender: pending.defenderPiece,
                                            drawn: draw.drawn, selected: draw.selected,
                                            advantage: pending.advantage, disadvantage: pending.disadvantage,
                                            drawnByPlayer: true)
        let cont = pending.continuation
        pendingModifierDraw = nil
        cont?.resume(returning: draw.selected)
    }

    /// Whether an attack by `attacker` waits for the player to draw its modifier cards: the
    /// players' own attacks do; monsters and summons draw for themselves unless the player asked
    /// to draw for every attack.
    func playerDrawsModifiers(for attacker: PieceID) -> Bool {
        if case .character = attacker { return true }
        return gameManager?.settingsManager.drawAllModifiers ?? false
    }

    /// Draw an attack's modifier cards: by the player's tap for their own attacks, otherwise at
    /// once, shown in the tray for a moment before the attack resolves.
    @MainActor func performModifierDraw(
        attacker: PieceID,
        defender: PieceID,
        baseAttack: Int,
        comparedAttack: Int? = nil,
        advantage: Bool,
        disadvantage: Bool,
        drawCard: @escaping () -> AttackModifier?
    ) async -> [AttackModifier] {
        if autoResolvePrompts || !playerDrawsModifiers(for: attacker) {
            let draw = CombatResolver.drawModifiersDetailed(advantage: advantage, disadvantage: disadvantage,
                                                            baseAttack: comparedAttack ?? baseAttack, draw: drawCard)
            lastModifierReveal = ModifierReveal(attacker: attacker, defender: defender, drawn: draw.drawn,
                                                selected: draw.selected, advantage: advantage,
                                                disadvantage: disadvantage, drawnByPlayer: false)
            await beat(2)
            return draw.selected
        }
        return await withCheckedContinuation { continuation in
            pendingModifierDraw = PendingModifierDraw(
                attackerPiece: attacker,
                defenderPiece: defender,
                baseAttack: baseAttack,
                comparedAttack: comparedAttack ?? baseAttack,
                advantage: advantage,
                disadvantage: disadvantage,
                drawCard: drawCard,
                continuation: continuation
            )
        }
    }

    /// Returns a display label for a piece (e.g. "Brute", "Bandit Guard 2").
    func pieceLabel(_ piece: PieceID) -> String {
        name(piece)
    }

    // MARK: - Damage Mitigation

    /// How the player chose to handle incoming damage.
    enum DamageMitigationChoice {
        case takeDamage
        case loseHandCard(cardId: Int)        // Lose 1 card from hand → negate all
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

    /// Non-nil while a character being attacked is offered a defence item.
    var pendingItemUse: PendingItemUse?

    /// Non-nil while a character picks discarded cards to recover (Minor Stamina Potion).
    var pendingRecovery: PendingRecovery?

    /// Non-nil while a character picks a card to play for an item (Ring of Haste).
    var pendingCardPlay: PendingCardPlay?

    /// Non-nil while a character picks Attack or Move (Master's Lute).
    var pendingActionChoice: PendingActionChoice?

    /// Non-nil while the player picks a figure from a list mid-turn (Heart of the Betrayer).
    var pendingFigureChoice: PendingFigureChoice?

    // MARK: Learning mode

    /// The tip on screen, and the ones waiting their turn.
    var pendingTip: LearnTip?
    var tipQueue: [LearnTip] = []
    /// Tips shown since the queue was last empty: the one showing is this one of
    /// `tipsShownInRun + tipQueue.count`, so a run of tips says "2 of 4" and "Next".
    var tipsShownInRun = 0
    /// The monsters' turns were paused for a tip, and go on once it's closed.
    var tipPausedPlayback = false
    /// What a long-press (or the "?") is explaining, or a monster's "Why?".
    var explanation: Explanation?
    /// The "?": the next tap explains instead of acting.
    var explainMode = false
    /// What each monster weighed on its turn, for "Why?" on its log lines.
    var monsterWhys: [UUID: MonsterWhy] = [:]
    var currentWhyID: UUID?
    var howToPlay: HowToPlayRequest?

    /// Boots of Speed / Quickness offers still to make this round, and the one being made.
    var initiativeOffers: [PendingInitiativeChange] = []
    var pendingInitiativeChange: PendingInitiativeChange?

    /// Non-nil while the character decides how much damage to suffer (Flurry of Axes).
    var pendingSufferChoice: PendingSufferChoice?

    /// Non-nil while the player picks which ally recovers cards (Volatile Concoction).
    var pendingAllyChoice: PendingAllyChoice?

    /// Non-nil while a character picks elements to infuse (Mana Potions).
    var pendingElementChoice: PendingElementChoice?

    /// "On death" attacks (Cultists) waiting to be made, from where the monster fell.
    struct DeathAttack {
        let attacker: PieceID
        let monster: String
        let type: MonsterType
        let position: HexCoord
        let action: ActionModel
    }
    var pendingDeathAttacks: [DeathAttack] = []
    /// The fallen monster making its "on death" attack right now, and the hex it fell on.
    var deathAttackInProgress: DeathAttack?

    /// Added to every monster attack this round (Captain of the Guard's special).
    var monsterAttackBonusThisRound = 0

    /// Figures every attack against has disadvantage this round (Giant Viper).
    var disadvantagedThisRound: Set<PieceID> = []

    /// Conditions that go with the one being targeted (Pendant of the Plague's Curse).
    var pendingExtraConditions: [ConditionName] = []
    /// The attack of an enemy the character forces to attack, waiting for its target.
    var pendingForcedAttack: AttackParameters?

    /// Traps placed by characters that give experience when an enemy springs them (Proximity Mine).
    var characterTraps: [HexCoord: (characterID: String, experience: Int)] = [:]

    /// Doomed enemies that died, their dooms still to resolve (BoardCoordinator+Dooms).
    var pendingDoomDeaths: [PendingDoomDeath] = []
    /// Attacks characters perform because they suffered damage (Vengeful Barrage), still to make.
    var pendingDamageAttacks: [(characterID: String, value: Int)] = []
    /// Characters who used Expose's advantage this turn (once each turn).
    var exposeUsedThisTurn: Set<String> = []

    /// Non-nil while a character picks items to refresh (Empowering Talisman, Utility Belt).
    var pendingItemRefresh: PendingItemRefresh?

    /// Non-nil while a character picks a negative condition to remove (Minor Cure Potion).
    var pendingConditionRemoval: PendingConditionRemoval?

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

        // Lose the chosen card
        guard discardIndex >= 0, discardIndex < character.discardedCards.count else { return }
        pendingLongRest = nil
        gameManager.scenarioStatsManager.recordRest(by: character.name, long: true)
        let lostCard = character.discardedCards.remove(at: discardIndex)
        character.lostCards.append(lostCard)
        boardScene?.play(.rest)
        boardScene?.play(.lose)

        // Recover remaining discard to hand. (Heal 2 and refreshing spent items happen when the
        // resting turn starts — RoundManager.beforeTurn.)
        character.handCards.append(contentsOf: character.discardedCards)
        character.discardedCards.removeAll()

        let deckName = character.characterData?.deck ?? character.name
        let deckData = gameManager.editionStore.deckData(name: deckName, edition: character.edition)
        let cardName = deckData?.abilities.first(where: { $0.cardId == lostCard })?.name ?? "Card \(lostCard)"
        log("\(characterName(characterID)) long rests: loses \(cardName), heals 2 and takes back \(character.handCards.count) cards", category: .rest)

        lootAtEndOfTurn(characterID)
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
        /// The player chose to rest; the randomly lost card is now revealed and the rest can no
        /// longer be declined.
        var committed: Bool = false
    }

    /// The player decides to short rest: reveal the randomly chosen card.
    func commitShortRest() {
        guard var pending = pendingShortRest else { return }
        pending.committed = true
        pendingShortRest = pending
    }

    /// Non-nil when a character is being offered a short rest at end of round.
    var pendingShortRest: PendingShortRest?

    /// Characters that performed a long rest this round (skip short rest for them).
    private var longRestedCharacterIDs: Set<String> = []
    /// Characters already offered a short rest this round.
    private var shortRestOffered: Set<String> = []

    /// Begin offering short rests to eligible characters at end of round.
    private func offerShortRests() {
        guard let gameManager = gameManager else {
            proceedAfterShortRests()
            return
        }

        shortRestOffered = []
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

        if let characterID { shortRestOffered.insert(characterID) }
        let active = gameManager.game.activeCharacters.filter { !$0.exhausted && !$0.absent }

        for character in active where !shortRestOffered.contains(character.id) {
            shortRestOffered.insert(character.id)
            // Skip characters that long-rested (they already recovered)
            guard !longRestedCharacterIDs.contains(character.id) else { continue }
            // Need at least 2 discarded cards to short rest
            guard character.discardedCards.count >= 2 else { continue }

            // Pick a random card from the discard pile
            let randomCardId = character.discardedCards.randomElement(using: &GameRandom.shared)!
            pendingShortRest = PendingShortRest(
                characterID: character.id,
                randomCardId: randomCardId
            )
            // Before the choice, not after it (the rest's log line taught it too late).
            teach(.resting, "\(characterName(character.id)) may short rest now.")
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
        gameManager.scenarioStatsManager.recordRest(by: character.name, long: false)

        // Remove the lost card from discard
        if let idx = character.discardedCards.firstIndex(of: lostCardId) {
            character.discardedCards.remove(at: idx)
        }
        character.lostCards.append(lostCardId)
        boardScene?.play(.rest)
        boardScene?.play(.lose)

        // Recover remaining discard to hand
        character.handCards.append(contentsOf: character.discardedCards)
        character.discardedCards.removeAll()

        let deckName = character.characterData?.deck ?? character.name
        let deckData = gameManager.editionStore.deckData(name: deckName, edition: character.edition)
        let cardName = deckData?.abilities.first(where: { $0.cardId == lostCardId })?.name ?? "Card \(lostCardId)"
        log("\(characterName(character.id)) short rests: loses \(cardName) and takes back \(character.handCards.count) cards", category: .rest)

        let charID = pending.characterID
        pendingShortRest = nil
        advanceToNextShortRest(startingAfter: charID)
    }

    /// Player takes 1 damage to re-pick a different random card.
    func rerollShortRest() {
        guard let gameManager = gameManager,
              var pending = pendingShortRest,
              pending.committed, !pending.rerollUsed,
              let character = gameManager.game.characters.first(where: { $0.id == pending.characterID }) else { return }

        // Suffer 1 damage to keep the card and randomly lose a different one (once per rest).
        log("\(characterName(character.id)) suffers 1 damage to lose a different card", category: .rest)
        if sufferDamage(1, to: .character(character.id)) {
            // Exhausted by the damage: the rest is over.
            pendingShortRest = nil
            advanceToNextShortRest(startingAfter: pending.characterID)
            return
        }

        pending.rerollUsed = true

        // Pick a new random card, different from the current one if possible
        let candidates = character.discardedCards.filter { $0 != pending.randomCardId }
        if let newCard = candidates.randomElement(using: &GameRandom.shared) {
            pending.randomCardId = newCard
        }
        // If no other candidates exist, keep the same card (only 1 unique card ID scenario — unlikely with >=2 cards)

        pendingShortRest = pending
    }

    /// Player declines the short rest — cards stay as-is.
    func skipShortRest() {
        guard let pending = pendingShortRest, !pending.committed else { return }
        let charID = pending.characterID
        log("\(characterName(charID)) skips the short rest", category: .rest)
        pendingShortRest = nil
        advanceToNextShortRest(startingAfter: charID)
    }

    /// Continue with end-of-round cleanup after all short rests are resolved.
    private func proceedAfterShortRests() {
        guard let gameManager = gameManager else { return }

        longRestedCharacterIDs = []

        // End-of-round cleanup (end-of-round scenario rules, elements wane, decks reshuffle)
        let game = gameManager.game
        if game.monsterAttackModifierDeck.needsShuffle || game.allyAttackModifierDeck.needsShuffle
            || game.characters.contains(where: { $0.attackModifierDeck.needsShuffle }) {
            boardScene?.play(.shuffle)
        }
        gameManager.roundManager.nextGameState()
        log("Round \(gameManager.game.round) complete", category: .round)
        afterRuleDamage { [weak self] in
            guard let self else { return }
            self.sweepDeadFigures()
            self.updateLocks(roundEnded: true)
            self.resolvePendingResult()
            if self.scenarioResult != nil { return }
            self.beginCardSelection()
        }
    }

    // MARK: - Scenario-rule damage

    /// Damage scenario rules dealt characters this step (Scenario 51's summoners, 60's late
    /// rounds), each taken in turn so the character may lose cards to negate it.
    @ObservationIgnored var ruleDamageDue: [(characterID: String, amount: Int)] = []

    /// Resolve the rule damage due, then `next`; straight on when there's none.
    func afterRuleDamage(_ next: @escaping () -> Void) {
        guard !ruleDamageDue.isEmpty else { return next() }
        let due = ruleDamageDue
        ruleDamageDue = []
        let generation = boardGeneration
        Task { @MainActor in
            for (id, amount) in due where self.isCurrentBoard(generation) && self.isOnBoard(.character(id)) {
                self.log("\(self.characterName(id)) suffers \(amount) damage from the scenario", category: .damage)
                await self.sufferDamageWithMitigation(amount, to: .character(id), source: "the scenario")
            }
            guard self.isCurrentBoard(generation) else { return }
            next()
        }
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
        resetForScenario(scenario)
        briefPresentation = .intro
        let initialRefs = (gameManager?.game.scenario?.data.rooms ?? []).filter(\.isInitial).compactMap(\.ref)
        let (board, startingRoom) = BoardBuilder.buildStartingRoom(from: scenario, initialRoomRefs: initialRefs)
        self.boardState = board
        self.scenarioResult = nil
        // Some maps mark fewer starting hexes than there are characters; add the nearest empty
        // hexes of the starting room so everyone can be placed.
        let partySize = gameManager?.game.characters.filter { !$0.absent }.count ?? 0
        if board.startingLocations.count < partySize {
            var extra = board.startingLocations
            var frontier = board.startingLocations.isEmpty ? Array(board.cells.keys.min().map { [$0] } ?? []) : board.startingLocations
            var visited = Set(frontier)
            while extra.count < partySize, !frontier.isEmpty {
                let next = frontier.removeFirst()
                if !extra.contains(next), board.isPassable(next), !board.isOccupied(next),
                   board.cells[next]?.overlay == nil {
                    extra.append(next)
                }
                for neighbor in next.neighbors where board.cells[neighbor] != nil && !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    frontier.append(neighbor)
                }
            }
            board.startingLocations = extra
        }

        // The starting room's monsters were created from the scenario data; give them the map's
        // positions (or fall back to the map's own monster list if the scenario has none).
        let hasRoomData = !(gameManager?.game.scenario?.data.rooms ?? []).isEmpty
        placeRevealedMonsters(slots: startingRoom.slots, newEntities: unplacedMonsterEntities(),
                              playerCount: playerCount, useMapMonsters: !hasRoomData)
        placeRevealedObjectives()
        updateLocks()

        attachToGame()

        // Reset round state so monster abilities are drawn fresh regardless of how the previous game ended.
        gameManager?.game.state = .draw
        gameManager?.game.round = 0

        buildScene(for: scenario)
        showLocksAndPlates()
        boardPhase = .setup
        turnLog = []
        resetLearning()
        log("Scenario \(scenario.id): \(scenario.title)", category: .setup)
        log("\(boardState.startingLocations.count) starting locations available", category: .setup)
        beginNextPlacement()
    }

    /// Ready the next character to place, its starting hexes lit, so setup is a tap per character.
    func beginNextPlacement() {
        guard boardPhase == .setup,
              let next = gameManager?.game.activeCharacters.first(where: { boardState.piecePositions[.character($0.id)] == nil })
        else { return }
        beginPlaceCharacter(characterID: next.id)
    }

    /// Put a saved scenario back on the board at the start of a round. The game (figures, decks,
    /// elements, round) has already been restored; `board` is the board as it stood then.
    func resumeScenario(scenario: VGBScenario, board snapshot: BoardSnapshot) {
        resetForScenario(scenario)
        let board = BoardState()
        snapshot.restore(to: board)
        boardState = board
        restoreCharacterTraps(from: snapshot)
        attachToGame()
        buildScene(for: scenario)
        showLocksAndPlates()
        turnLog = []
        resetLearning()
        log("Scenario \(scenario.id): \(scenario.title)", category: .setup)
        beginCardSelection()
    }

    /// Clear everything left over from a previous scenario or turn.
    private func resetForScenario(_ scenario: VGBScenario) {
        scenarioData = scenario
        briefPresentation = nil
        boardGeneration += 1
        abandonPendingPrompts()
        turnOrder = []
        currentTurnIndex = -1
        activePlayerTurn = nil
        interactionMode = .idle
        scenarioResult = nil
        pendingResult = nil
        endReason = nil
        pendingRevealedStandees = [:]
        currentTurnToggled = false
        lastAttackTarget = nil
        lastAttackerPos = nil
        lastModifierReveal = nil   // the last scenario's draw isn't this one's
        lastDrawnModifier = nil
        characterTraps = [:]
        pendingDoomDeaths = []
        pendingDamageAttacks = []
        exposeUsedThisTurn = []
    }

    /// Whether `generation` (read when a turn task started) is still the board on the table. A
    /// task that finds it isn't stops without touching the game: the board was left or restarted.
    func isCurrentBoard(_ generation: Int) -> Bool { boardGeneration == generation }

    /// Resume every turn task waiting on the player or an animation and drop every prompt, as the
    /// board is torn down: the tasks end (finding the board gone) instead of hanging on, and no
    /// prompt of the old board surfaces, or is answered, on the next one. Call after bumping
    /// `boardGeneration`.
    private func abandonPendingPrompts() {
        let draw = pendingModifierDraw, damage = pendingDamage, item = pendingItemUse
        let pushPull = pendingPushPullContinuation, moves = pendingMoveAnimations
        let figure = pendingFigureChoice
        pendingFigureChoice = nil
        figure?.continuation?.resume(returning: nil)
        pendingModifierDraw = nil
        pendingDamage = nil
        pendingItemUse = nil
        pendingPushPullContinuation = nil
        pendingMoveAnimations = [:]
        draw?.continuation?.resume(returning: [])
        damage?.continuation?.resume(returning: .takeDamage)
        item?.continuation?.resume(returning: false)
        pushPull?.resume()
        for move in moves.values { move.resume() }
        endPlaybackControls()
        resetLearning()
        howToPlay = nil

        pendingShortRest = nil
        pendingLongRest = nil
        pendingSummonPlacement = nil
        woundDue = []
        pendingRecovery = nil
        pendingCardPlay = nil
        pendingActionChoice = nil
        initiativeOffers = []
        pendingInitiativeChange = nil
        pendingSufferChoice = nil
        pendingAllyChoice = nil
        pendingElementChoice = nil
        pendingItemRefresh = nil
        pendingConditionRemoval = nil
        pendingDeathAttacks = []
        deathAttackInProgress = nil
        pendingExtraConditions = []
        pendingForcedAttack = nil
        pendingHealConditions = []
        monsterAttackBonusThisRound = 0
        disadvantagedThisRound = []
    }

    /// Hand round flow and rule-driven spawns over to the board.
    private func attachToGame() {
        gameManager?.roundManager.figuresTakeOwnTurns = true
        gameManager?.entityManager.takesWoundDamage = { [weak self] entity in
            self?.deferWoundDamage(of: entity) ?? false
        }
        gameManager?.scenarioRulesManager.takesCharacterDamage = { [weak self] character, amount in
            guard let self, self.isOnBoard(.character(character.id)) else { return false }
            self.ruleDamageDue.append((character.id, amount))
            return true
        }

        // Monsters spawned by scenario rules go onto the board, not only into game state.
        gameManager?.scenarioRulesManager.onSpawnMonster = { [weak self] name, type, marker, health in
            self?.spawnFromScenarioRule(name: name, type: type, marker: marker, health: health) ?? false
        }
    }

    /// Create the SpriteKit scene and draw the current board into it.
    private func buildScene(for scenario: VGBScenario) {
        let scene = BoardScene(size: CGSize(width: 1200, height: 800))
        scene.scaleMode = .resizeFill
        scene.onHexTap = { [weak self] coord in self?.handleHexTap(coord) }
        scene.onPieceTap = { [weak self] piece in self?.handlePieceTap(piece) }
        scene.onHold = { [weak self] hex in self?.explainHex(at: hex) }
        scene.appearanceProvider = { [weak self] piece in
            self?.pieceAppearance(piece) ?? PieceAppearance.fallback(for: piece)
        }
        scene.statusProvider = { [weak self] piece in self?.pieceStatus(piece) }
        scene.playSound = { BoardSoundPlayer.play($0) }
        boardScene = scene
        gameManager?.game.onElementChange = { [weak self] change in
            self?.boardScene?.play(change == .infused ? .infuse : .consume)
        }

        (offsetCol, offsetRow) = Self.sceneOffsets(for: boardState)

        scene.buildBoard(from: boardState, scenario: scenario, offsetCol: offsetCol, offsetRow: offsetRow,
                         characterAppearances: buildCharacterAppearances())
        applyAnimationSpeed(gameManager?.settingsManager.animationSpeed ?? 1)
        syncPieceVisuals()
    }

    /// Apply the Animation Speed setting (0.5 fast … 2 slow) to the board's animations and to
    /// the pause between automated turns.
    func applyAnimationSpeed(_ speed: Double) {
        let speed = min(max(speed, 0.25), 4)
        animationSpeed = speed
        boardScene?.speed = CGFloat(Self.sceneSpeed(animationSpeed: speed, fastForward: isFastForward))
        turnDelayNanoseconds = UInt64(Double(Self.baseTurnDelayNanoseconds) * speed)
    }

    /// Tear down the board and return to the main menu.
    func exitBoard() {
        boardGeneration += 1
        abandonPendingPrompts()
        gameManager?.scenarioRulesManager.onSpawnMonster = nil
        gameManager?.entityManager.takesWoundDamage = nil
        gameManager?.scenarioRulesManager.takesCharacterDamage = nil
        ruleDamageDue = []
        gameManager?.roundManager.figuresTakeOwnTurns = false
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
        escortTurnController = nil
        pendingSummonPlacement = nil
        pendingShortRest = nil
        cardSelectionsComplete = []
        cardSelectingCharacterID = nil
        scenarioResult = nil
        pendingResult = nil
        endReason = nil
    }

    // MARK: - Character Placement (Setup Phase)

    /// Begin placing a character on a starting location.
    func beginPlaceCharacter(characterID: String) {
        guard boardPhase == .setup else { return }
        interactionMode = .placingCharacter(characterID: characterID)

        // Highlight available starting locations
        let occupied = Set(boardState.piecePositions.values)
        let available = Set(boardState.startingLocations.filter { !occupied.contains($0) })
        boardScene?.highlightHexes(available, style: .place, offsetCol: offsetCol, offsetRow: offsetRow)
    }

    /// Place a character on a starting hex.
    func placeCharacter(characterID: String, at coord: HexCoord) {
        guard boardState.startingLocations.contains(coord),
              !boardState.isOccupied(coord) else { return }

        let pieceID = PieceID.character(characterID)
        // A character already placed may move to another starting hex until the scenario begins.
        if let from = boardState.piecePositions[pieceID] {
            guard boardPhase == .setup else { return }
            boardState.movePiece(pieceID, to: coord)
            boardScene?.movePiece(id: pieceID, along: [from, coord], animation: .teleport,
                                  offsetCol: offsetCol, offsetRow: offsetRow) {}
            boardScene?.clearHighlights()
            interactionMode = .idle
            log("\(characterName(characterID)) takes another starting hex", category: .setup, trace: "at \(coord)")
            beginNextPlacement()
            return
        }
        boardState.placePiece(pieceID, at: coord)

        // Ensure character appearance data is stored before placing
        let appearances = buildCharacterAppearances()
        for (id, appearance) in appearances {
            boardScene?.storedAppearances[id] = appearance
        }

        boardScene?.addPieceSprite(id: pieceID, at: coord, offsetCol: offsetCol, offsetRow: offsetRow)
        boardScene?.clearHighlights()
        interactionMode = .idle
        log("\(characterName(characterID)) takes position", category: .setup, trace: "at \(coord)")
        beginNextPlacement()
    }

    /// Drop what rode on a target choice that was skipped (Pendant of the Plague's Curse, a
    /// heal's conditions), so it doesn't land on a later target instead.
    func dropChoiceExtras() {
        pendingExtraConditions = []
        pendingHealConditions = []
    }

    /// Drop a summon placement that won't happen (the ability was skipped or taken back): the
    /// summon waiting for its hex goes with it, so it neither lingers in the character's summons
    /// nor keeps the summon card in the active area.
    func abandonSummonPlacement() {
        guard let pending = pendingSummonPlacement else { return }
        pendingSummonPlacement = nil
        gameManager?.game.characters.first { $0.id == pending.characterID }?.summons.removeAll {
            $0.id == pending.summonID && !isOnBoard(.summon(id: $0.id))
        }
    }

    /// Place a summon on a chosen hex during interactive summon placement.
    func placeSummon(summonID: String, characterID: String, at coord: HexCoord) {
        let summonPieceID = PieceID.summon(id: summonID)
        boardState.placePiece(summonPieceID, at: coord)
        boardScene?.addPieceSprite(id: summonPieceID, at: coord, offsetCol: offsetCol, offsetRow: offsetRow)
        boardScene?.play(.summon)
        boardScene?.clearHighlights()
        teach(.summons, at: .piece(summonPieceID))
        let pending = pendingSummonPlacement
        pendingSummonPlacement = nil
        interactionMode = .idle
        log("\(characterName(characterID)) summons \(name(summonPieceID))", category: .info, trace: "at \(coord)")

        // Place the next figure of a multi-figure summon, if there is still an empty adjacent hex.
        if let pending, pending.remaining > 0, let data = pending.summonData,
           let gameManager, let character = gameManager.game.characters.first(where: { $0.id == characterID }),
           let charPos = boardState.piecePositions[.character(characterID)] {
            let hexes = Set(charPos.neighbors.filter { isEmptyHex($0) })
            if !hexes.isEmpty {
                gameManager.characterManager.addSummon(from: data, for: character)
                if let next = character.summons.last {
                    pendingSummonPlacement = PendingSummonPlacement(
                        summonID: next.id, characterID: characterID, summonName: pending.summonName,
                        validHexes: hexes, remaining: pending.remaining - 1, summonData: data)
                    interactionMode = .placingSummon(summonID: next.id, characterID: characterID, validHexes: hexes)
                    boardScene?.highlightHexes(hexes, style: .summon, offsetCol: offsetCol, offsetRow: offsetRow)
                    return
                }
            }
        }

        // Advance the player turn controller past the async summon action
        activePlayerTurn?.advanceAfterAsyncAction()
    }

    /// Finish setup phase and begin the first round.
    func finishSetup() {
        guard boardPhase == .setup else { return }
        boardScene?.clearHighlights()
        interactionMode = .idle
        beginCardSelection()
    }

    // MARK: - Card Selection Phase

    /// Start the card selection phase for a new round.
    func beginCardSelection() {
        guard let gameManager = gameManager else { return }
        teachAtCardSelection()

        boardPhase = .cardSelection
        endPlaybackControls()
        cardSelectionsComplete = []
        cardSelectingCharacterID = nil
        selectedCardPairs = [:]

        // No turn is half-played here: save the round so Continue can resume from it.
        gameManager.checkpointRound()

        logRoundHeader(gameManager.game.round + 1)

        // Process exhaustion and auto-rests, then find the first character needing manual selection
        advanceToNextCardSelection()
    }

    /// Store the selected card pair for a character during card selection.
    func storeSelectedCards(for characterID: String, top: AbilityModel, bottom: AbilityModel) {
        selectedCardPairs[characterID] = (top: top, bottom: bottom)
    }

    /// A character plays two cards this round. The first card leads: its initiative is the
    /// character's initiative (p.16). Either card can still supply the top half during the turn.
    func chooseCards(for characterID: String, leading: AbilityModel, other: AbilityModel) {
        guard let character = gameManager?.game.characters.first(where: { $0.id == characterID }) else { return }
        character.initiative = leading.initiative
        character.longRest = false
        storeSelectedCards(for: characterID, top: leading, bottom: other)
        boardScene?.play(.cardConfirm)
        log("\(characterName(characterID)) plays \(leading.name ?? "a card") (\(leading.initiative)) and \(other.name ?? "a card")", category: .round)
        completeCardSelection(for: characterID)
    }

    /// A character declares a long rest instead of playing cards (initiative 99, p.27).
    func chooseLongRest(for characterID: String) {
        guard let character = gameManager?.game.characters.first(where: { $0.id == characterID }),
              character.discardedCards.count >= 2 else { return }
        character.initiative = 99
        character.longRest = true
        log("\(characterName(characterID)) will long rest", category: .rest)
        boardScene?.play(.cardConfirm)
        completeCardSelection(for: characterID)
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
                log("\(characterName(character.id)) must long rest (only \(handCount) card\(handCount == 1 ? "" : "s") in hand)", category: .rest)
                cardSelectionsComplete.insert(character.id)
                // Continue to next character
            } else {
                // Exhausted: can't play two cards and can't rest (p.27). HP is unaffected.
                exhaust(character, reason: "\(handCount) hand, \(discardCount) discard")
                cardSelectionsComplete.insert(character.id)
                if scenarioResult != nil { return }
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

        // Advance the round (start-of-round rules, monster ability draws, initiative order)
        boardScene?.play(.round)
        gameManager.roundManager.nextGameState()
        afterRuleDamage { [weak self] in self?.continueExecution() }
    }

    private func continueExecution() {
        guard let gameManager = gameManager else { return }
        sweepDeadFigures()
        if scenarioResult != nil { return }

        boardPhase = .execution

        // Log monster ability draws
        for monster in gameManager.game.monsters where !monster.off && !monster.aliveEntities.isEmpty {
            if let ability = gameManager.monsterManager.currentAbility(for: monster) {
                log("\(monsterTypeName(monster.name)) draws \(ability.name ?? "an ability card") (\(ability.initiative))",
                    category: .round)
            }
        }

        disadvantagedThisRound = []
        monsterAttackBonusThisRound = 0
        // Every card is revealed: Boots of Speed and Quickness may change an initiative now.
        initiativeOffers = initiativeItemOffers()
        offerNextInitiativeChange()
    }

    /// Order the round's figures by initiative and start the first turn.
    func buildTurnOrderAndStart() {
        guard let gameManager = gameManager else { return }
        teach(.initiative, at: .turnRail)
        // Build turn order from sorted figures
        turnOrder = gameManager.game.figures.compactMap { figure in
            switch figure {
            case .character(let c) where c.exhausted || c.absent:
                return nil
            case .character(let c) where c.longRest:
                // Initiative 99; a character goes before a monster type on a tie (p.16).
                return TurnOrderEntry(figure: figure, initiative: 99 - 0.9)
            case .character(let c):
                // Ties between characters are broken by their second card's initiative (p.16).
                let secondCard = Double(selectedCardPairs[c.id]?.bottom.initiative ?? 99) / 1000
                return TurnOrderEntry(figure: figure, initiative: c.effectiveInitiative + secondCard)
            case .monster(let m) where !m.off && !m.aliveEntities.isEmpty:
                // Use monsterManager to get the real initiative from the drawn ability card
                let init_ = gameManager.monsterManager.currentAbilityInitiative(for: m)
                return TurnOrderEntry(figure: figure, initiative: Double(init_ ?? 99))
            case .objective(let o) where !o.off && o.escort && o.entities.contains(where: { !$0.dead }):
                // An escort takes a turn; an objective on the map (an altar, a door) takes none.
                return TurnOrderEntry(figure: figure, initiative: Double(o.initiative) - 0.5)
            default:
                return nil
            }
        }.sorted { $0.initiative < $1.initiative }

        currentTurnIndex = -1
        syncPieceVisuals()
        let orderDesc = turnOrder.map { entry in
            let name: String
            switch entry.figure {
            case .character(let c): name = characterName(c.id)
            case .monster(let m): name = monsterTypeName(m.name)
            case .objective(let o): name = o.name
            }
            return "\(name) \(Int(entry.initiative.rounded(.up)))"
        }.joined(separator: ", ")
        log("Turn order: \(orderDesc)", category: .round)
        advanceToNextFigure()
    }

    /// Advance to the next figure in initiative order.
    func advanceToNextFigure() {
        guard let gameManager = gameManager else { return }
        // Doomed enemies that died this turn (to a trap, a wound…) resolve their dooms first.
        if !pendingDoomDeaths.isEmpty || !pendingDamageAttacks.isEmpty {
            let generation = boardGeneration
            Task { @MainActor in
                await self.resolveDoomDeaths()
                guard self.isCurrentBoard(generation), self.scenarioResult == nil else { return }
                self.advanceToNextFigure()
            }
            return
        }
        syncPieceVisuals()

        // End the current figure's turn (conditions expire), then resolve anything that died.
        if currentTurnIndex >= 0 && currentTurnIndex < turnOrder.count {
            turnOrder[currentTurnIndex].completed = true
            if currentTurnToggled, case .character(let character) = turnOrder[currentTurnIndex].figure {
                gameManager.scenarioRulesManager.evaluateTurnRules(.turnEnd, for: character)
            }
            if currentTurnToggled {
                gameManager.roundManager.toggleFigure(turnOrder[currentTurnIndex].figure)
                currentTurnToggled = false
            }
            // Damage a rule deals as a turn ends (The Void) is suffered now, not when the round is over.
            if !ruleDamageDue.isEmpty {
                afterRuleDamage { [weak self] in self?.advanceToNextFigure() }
                return
            }
            sweepDeadFigures()
            if scenarioResult != nil { return }
        }

        // Monsters revealed or spawned during the turn that just ended act this round (p.32).
        scheduleRevealedMonsters()

        activePlayerTurn = nil
        currentTurnIndex += 1

        if currentTurnIndex >= turnOrder.count {
            setActing(nil)
            endRound()
            return
        }

        let entry = turnOrder[currentTurnIndex]

        switch entry.figure {
        case .character(let character):
            // Exhausted (or removed) characters take no further part in the scenario.
            guard !character.exhausted, !character.absent, isOnBoard(.character(character.id)) else {
                advanceToNextFigure()
                return
            }
            selectedPiece = .character(character.id)
            setActing(.character(character.id))

            // A summon's turn comes directly before its summoner's — even a resting one (p.26).
            let livingSummons = entry.anotherTurn ? []
                : character.summons.filter { !$0.dead && isOnBoard(.summon(id: $0.id)) }
            if !livingSummons.isEmpty {
                interactionMode = .watchingMonsterTurn
                log("\(characterName(character.id))\u{2019}s summons act first", category: .round)
                let controller = SummonTurnController(coordinator: self, gameManager: gameManager)
                self.summonTurnController = controller
                let generation = boardGeneration
                Task { @MainActor in
                    await controller.executeSummonTurns(for: character)
                    guard self.boardGeneration == generation else { return }
                    self.summonTurnController = nil
                    guard self.scenarioResult == nil else { return }
                    self.beginCharacterTurn(character, entry: entry)
                }
            } else {
                beginCharacterTurn(character, entry: entry)
            }

        case .monster(let monster):
            guard !monster.off, !monster.aliveEntities.isEmpty else {
                advanceToNextFigure()
                return
            }
            // Each monster's conditions tick at the start of its own turn (MonsterTurnController).
            gameManager.roundManager.toggleFigure(entry.figure)
            currentTurnToggled = true
            interactionMode = .watchingMonsterTurn

            let controller = MonsterTurnController(coordinator: self, gameManager: gameManager)
            self.monsterTurnController = controller
            let generation = boardGeneration
            Task { @MainActor in
                await controller.executeMonsterGroup(monster, only: entry.onlyStandees)
                guard self.boardGeneration == generation else { return }
                self.monsterTurnController = nil
                self.checkVictoryDefeat()
                if self.scenarioResult == nil {
                    self.advanceToNextFigure()
                }
            }

        case .objective(let container):
            gameManager.roundManager.toggleFigure(entry.figure)
            currentTurnToggled = true
            if container.escort && container.hasEscortActions {
                interactionMode = .watchingMonsterTurn
                log("\(container.name)\u{2019}s turn", category: .round)
                let controller = EscortTurnController(coordinator: self, gameManager: gameManager)
                self.escortTurnController = controller
                let generation = boardGeneration
                Task { @MainActor in
                    await controller.executeEscortTurns(for: container)
                    guard self.boardGeneration == generation else { return }
                    self.escortTurnController = nil
                    self.checkVictoryDefeat()
                    if self.scenarioResult == nil {
                        self.advanceToNextFigure()
                    }
                }
            } else {
                advanceToNextFigure()
            }
        }
    }

    /// Start a character's own turn (after its summons acted): conditions tick, then it either
    /// long rests, loses its turn to Stun, or plays its two cards.
    private func beginCharacterTurn(_ character: GameCharacter, entry: TurnOrderEntry) {
        guard let gameManager = gameManager else { return }
        exposeUsedThisTurn.remove(character.id)
        // Inescapable Fate: the marker advances as the owner's turn starts.
        if activeDooms.contains(where: { $0.doom.characterID == character.id && { if case .countdown = $0 { return true }; return false }($0.doom.effect) }) {
            let generation = boardGeneration
            Task { @MainActor in
                await self.advanceDoomCountdowns(for: character)
                guard self.isCurrentBoard(generation), self.scenarioResult == nil else { return }
                self.beginCharacterTurnAfterDooms(character, entry: entry)
            }
            return
        }
        beginCharacterTurnAfterDooms(character, entry: entry)
    }

    private func beginCharacterTurnAfterDooms(_ character: GameCharacter, entry: TurnOrderEntry) {
        guard let gameManager = gameManager else { return }
        // The player has the board again: the monsters' pace goes back to normal.
        endPlaybackControls()
        gameManager.roundManager.toggleFigure(entry.figure)
        currentTurnToggled = true

        // Wound: 1 damage as the turn starts, which the character may negate by losing cards.
        if woundDue.remove(character.id) != nil {
            let piece = PieceID.character(character.id)
            log("\(characterName(character.id)) suffers 1 damage from their wound", category: .damage)
            if !autoResolvePrompts, !negatesDamage(piece, amount: 1),
               !losableHandCards(of: character).isEmpty || character.discardedCards.count >= 2 {
                interactionMode = .idle
                let generation = boardGeneration
                Task { @MainActor in
                    await self.sufferDamageWithMitigation(1, to: piece, source: "Wound")
                    guard self.isCurrentBoard(generation) else { return }
                    self.continueCharacterTurn(character, entry: entry)
                }
                return
            }
            sufferDamage(1, to: piece)
        }
        continueCharacterTurn(character, entry: entry)
    }

    /// Characters whose wound damage is due as their turn starts (taken by the board, so it can
    /// be negated).
    @ObservationIgnored private var woundDue: Set<String> = []

    private func deferWoundDamage(of entity: any Entity) -> Bool {
        // A long rester's heal follows the wound's damage in the same step (and removes the
        // wound), so that damage stays where it is.
        guard let character = entity as? GameCharacter, !character.longRest,
              isOnBoard(.character(character.id)) else { return false }
        woundDue.insert(character.id)
        return true
    }

    private func continueCharacterTurn(_ character: GameCharacter, entry: TurnOrderEntry) {
        guard let gameManager = gameManager else { return }
        gameManager.scenarioRulesManager.evaluateTurnRules(.turnStart, for: character)
        sweepDeadFigures()
        if scenarioResult != nil { return }
        guard !character.exhausted, isOnBoard(.character(character.id)) else {
            advanceToNextFigure()
            return
        }

        if character.longRest {
            if character.discardedCards.count <= 1 {
                if character.discardedCards.isEmpty {
                    log("\(characterName(character.id)) long rests (no cards to lose)", category: .rest)
                    lootAtEndOfTurn(character.id)
                    advanceToNextFigure()
                } else {
                    resolveLongRest(characterID: character.id, discardIndex: 0)
                }
            } else {
                log("\(characterName(character.id)) long rests: choose a card to lose", category: .rest)
                interactionMode = .idle   // the rest panel asks; nothing on the board to tap
                pendingLongRest = PendingLongRest(characterID: character.id)
            }
            return
        }

        // Stun: no abilities and no items; the two played cards are simply discarded (p.22).
        if character.entityConditions.contains(where: { $0.name == .stun && !$0.expired }) {
            if let pair = selectedCardPairs[character.id] {
                for cardId in [pair.top.cardId, pair.bottom.cardId].compactMap({ $0 }) {
                    character.handCards.removeAll { $0 == cardId }
                    character.discardedCards.append(cardId)
                }
            }
            log("\(characterName(character.id)) is stunned: no actions, both cards are discarded", category: .condition)
            // Looting at the end of the turn isn't an ability: a stunned character still loots.
            lootAtEndOfTurn(character.id)
            advanceToNextFigure()
            return
        }

        beginPlayerTurnAfterSummons(character: character)
    }

    /// Insert monsters that entered play during the last turn into this round's turn order.
    /// A type that hasn't acted yet just acts at its initiative; a type whose initiative already
    /// passed acts right after the turn in which it was revealed (p.32).
    private func scheduleRevealedMonsters() {
        guard let gameManager, !pendingRevealedStandees.isEmpty else { return }
        let revealed = pendingRevealedStandees
        pendingRevealedStandees = [:]

        let currentInitiative = (currentTurnIndex >= 0 && currentTurnIndex < turnOrder.count)
            ? turnOrder[currentTurnIndex].initiative : -1
        var immediate: [TurnOrderEntry] = []

        for (name, standees) in revealed.sorted(by: { $0.key < $1.key }) {
            guard let monster = gameManager.game.monsters.first(where: { $0.name == name }),
                  let initiative = gameManager.monsterManager.currentAbilityInitiative(for: monster).map(Double.init)
            else { continue }

            let pendingIndex = turnOrder.indices.first { index in
                index > currentTurnIndex && !turnOrder[index].completed && turnOrder[index].onlyStandees == nil &&
                    { if case .monster(let m) = turnOrder[index].figure { return m === monster }; return false }()
            }
            if pendingIndex != nil { continue } // its whole type still acts later this round

            let entry = TurnOrderEntry(figure: .monster(monster), initiative: initiative, onlyStandees: standees)
            if initiative < currentInitiative {
                immediate.append(entry)
            } else {
                let insertAt = turnOrder.indices.first { $0 > currentTurnIndex && turnOrder[$0].initiative > initiative }
                    ?? turnOrder.count
                turnOrder.insert(entry, at: insertAt)
            }
        }
        immediate.sort { $0.initiative < $1.initiative }
        turnOrder.insert(contentsOf: immediate, at: min(currentTurnIndex + 1, turnOrder.count))
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
        // A standalone push/pull can only follow an attack made this turn.
        lastAttackTarget = nil
        lastAttackerPos = nil

        // Feed in the cards selected during card selection phase
        if let pair = selectedCardPairs[character.id] {
            ptc.selectCards(top: pair.top, bottom: pair.bottom)
            log("\(characterName(character.id))\u{2019}s turn: \(pair.top.name ?? "a card") and \(pair.bottom.name ?? "a card")", category: .round)
        } else {
            log("\(characterName(character.id))\u{2019}s turn (no cards chosen)", category: .round)
        }
        interactionMode = .idle
        teach(.yourTurn, at: .playedCards)
    }

    /// Called when the player finishes their turn (all actions done or skipped).
    func finishPlayerTurn() {
        // Ignore a second End Turn for the same turn.
        guard let ptc = activePlayerTurn, ptc.phase == .turnComplete else { return }
        boardScene?.play(.endTurn)
        teach(.playedCards)
        applyEndOfTurnItems(ptc)
        applyEndOfTurnBonuses(ptc)
        activePlayerTurn = nil
        lootAtEndOfTurn(ptc.characterID)

        updateLocks(turnEnded: true)
        checkVictoryDefeat(turnEnded: true)
        if scenarioResult == nil {
            advanceToNextFigure()
        }
    }

    /// End-of-turn looting: money tokens and treasure in the character's hex (p.28), on every
    /// turn — resting or stunned too, as it isn't an ability.
    func lootAtEndOfTurn(_ characterID: String) {
        let pieceID = PieceID.character(characterID)
        if let pos = boardState.piecePositions[pieceID] {
            lootHexes(for: pieceID, coords: [pos])
        }
    }

    // MARK: - End of Round

    private func endRound() {
        // Round bonuses end before the players may short rest, so those cards are in the
        // discard pile for it (p.30).
        for character in gameManager?.game.characters ?? [] {
            for cardId in character.roundBonusCards { character.removeFromActiveArea(cardId) }
        }
        // Offer short rests before transitioning to the next round — unless the scenario ends
        // with this round, when a rest changes nothing.
        if pendingResult != nil {
            proceedAfterShortRests()
        } else {
            offerShortRests()
        }
    }

    // MARK: - Victory / Defeat

    /// `turnEnded`: a turn or the round has just ended, which is when a goal about where the
    /// characters stand (on pressure plates, on the exit) is judged.
    func checkVictoryDefeat(turnEnded: Bool = false) {
        guard let gameManager = gameManager, scenarioResult == nil else { return }

        // Everyone has left through the exit: with no one on the board, that is the win.
        if everyoneEscaped {
            let brief = gameManager.game.scenario.map { ScenarioBrief.make(for: $0.data, labels: gameManager.editionStore) }
            endReason = .goalMet(brief?.goal ?? "Everyone escaped.")
            endScenario(.victory, message: "VICTORY! Scenario complete.")
            return
        }

        // Defeat: every character is exhausted — nobody is left to act, so it's immediate.
        let allChars = gameManager.game.characters.filter { !$0.absent }
        if !allChars.isEmpty && allChars.allSatisfy({ $0.exhausted }) {
            endReason = .partyExhausted
            endScenario(.defeat, message: "DEFEAT! All characters exhausted.")
            return
        }

        // Other results resolve at the end of the round (p.47): "Once a scenario's success or
        // failure conditions are triggered, play out the remainder of the round."
        guard pendingResult == nil else { return }

        if let finish = gameManager.game.scenario?.pendingFinish {
            let brief = gameManager.game.scenario.map { ScenarioBrief.make(for: $0.data, labels: gameManager.editionStore) }
            if finish == "won" {
                pendingResult = .victory
                endReason = .goalMet(brief?.goal ?? "The scenario's goal is met.")
                log("Scenario goal achieved — the scenario ends at the end of this round.", category: .round)
            } else if finish == "lost" {
                pendingResult = .defeat
                endReason = .ruleLost(brief?.defeat.dropFirst().first ?? "A special rule is triggered.")
                log("Scenario failed — the scenario ends at the end of this round.", category: .death)
            }
            return
        }

        // The goal and losses the scenario book prints (`ScenarioPlacements.Goal`).
        let written = scenarioGoal
        if let written, let lost = goalLost(written) {
            pendingResult = .defeat
            endReason = .ruleLost(lost)
            log("Scenario failed — the scenario ends at the end of this round.", category: .death)
            return
        }

        // Default goal: every enemy killed, with every room revealed — unless the scenario defines
        // its own win condition (e.g. survive until round 10), and only once enemies have been
        // in play (some scenarios start empty and spawn monsters every round).
        let hasOwnWinCondition = gameManager.game.scenario?.data.rules?.contains { $0.finish == "won" } ?? false
        let hostile = gameManager.game.monsters.filter { !MonsterAI.isAllyFaction($0) }
        let enemiesHaveAppeared = hostile.contains { !$0.entities.isEmpty }
        let allEnemiesDead = hostile.allSatisfy { monster in monster.off || monster.aliveEntities.isEmpty }
        let allRoomsRevealed = boardState.doors.allSatisfy { $0.isOpen }
        if let written, written.replacesKillAll, !hasOwnWinCondition {
            if goalMet(written, turnEnded: turnEnded) && gameManager.game.round > 0 {
                let brief = gameManager.game.scenario.map { ScenarioBrief.make(for: $0.data, labels: gameManager.editionStore) }
                pendingResult = .victory
                endReason = .goalMet(brief?.goal ?? "The scenario's goal is met.")
                log("Scenario goal achieved — the scenario ends at the end of this round.", category: .round)
            }
            return
        }
        if !hasOwnWinCondition && enemiesHaveAppeared && allEnemiesDead && allRoomsRevealed
            && gameManager.game.round > 0 {
            pendingResult = .victory
            endReason = .enemiesDefeated
            log("All enemies defeated — the scenario ends at the end of this round.", category: .round)
        }
    }

    /// Resolve a result triggered during the round once the round is over.
    private func resolvePendingResult() {
        letCharactersLeave()
        checkVictoryDefeat(turnEnded: true)
        guard scenarioResult == nil, let result = pendingResult else { return }
        endScenario(result, message: result == .victory ? "VICTORY! Scenario complete." : "DEFEAT! Scenario failed.")
    }

    private func endScenario(_ result: ScenarioResult, message: String) {
        scenarioResult = result
        boardPhase = .scenarioEnd
        interactionMode = .idle
        log(message, category: result == .victory ? .round : .death)
    }

    /// Increment the kill count for a monster name in the current scenario.
    func recordMonsterKill(name: String) {
        gameManager?.game.scenario?.killCounts[name, default: 0] += 1
    }

    /// Apply scenario result and clean up.
    func confirmScenarioEnd(choices: ScenarioRewardChoices = ScenarioRewardChoices()) {
        guard let gameManager = gameManager, let result = scenarioResult else { return }

        gameManager.completeScenario(success: result == .victory, choices: choices)
    }

    // MARK: - Turn Execution Actions

    /// Board positions of a character's enemies (block movement) and allies (can be passed
    /// through but not stopped on).
    func movementSets(for pieceID: PieceID) -> (enemies: Set<HexCoord>, allies: Set<HexCoord>) {
        var enemies = Set<HexCoord>()
        var allies = Set<HexCoord>()
        for (id, coord) in boardState.piecePositions where id != pieceID {
            if areEnemies(pieceID, id) { enemies.insert(coord) } else { allies.insert(coord) }
        }
        return (enemies, allies)
    }

    /// Begin a player's move action (normal, jump or flying movement, GH p.17).
    func beginMoveAction(pieceID: PieceID, moveRange: Int, mode: MoveMode = .normal) {
        guard let pos = boardState.piecePositions[pieceID] else { return }
        if case .character = pieceID { teach(.moving) }

        if isConditionActive(.immobilize, on: pieceID) {
            log("\(name(pieceID)) is immobilized and can\u{2019}t move", category: .condition)
            interactionMode = .idle
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }

        let (enemies, allies) = movementSets(for: pieceID)
        let reachable = Pathfinder.reachableHexes(
            board: boardState, from: pos, range: moveRange, mode: mode,
            avoidTraps: false, canOpenDoors: true,
            occupiedByEnemy: enemies, occupiedByAlly: allies
        )

        var validHexes = Set(reachable.keys).subtracting([pos])
        // A move with text that happens as it ends may be Move 0: the character's own hex.
        if canStayPut(pieceID) { validHexes.insert(pos) }
        if validHexes.isEmpty {
            log("\(name(pieceID)) has nowhere to move", category: .move)
            interactionMode = .idle
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }
        interactionMode = .selectingMove(pieceID: pieceID, range: moveRange, validHexes: validHexes, mode: mode)
        let style: HighlightStyle = mode == .jump ? .jump : (mode == .fly ? .fly : .move)
        boardScene?.highlightHexes(validHexes, style: style, offsetCol: offsetCol, offsetRow: offsetRow)
    }

    /// Whether the acting character's move prints something that happens as it ends, so moving
    /// no hexes is worth choosing (GH: any ability may be performed for 0).
    func canStayPut(_ pieceID: PieceID) -> Bool {
        guard case .character(let id) = pieceID, let turn = activePlayerTurn, turn.characterID == id else { return false }
        return !turn.afterMoveTexts.isEmpty
    }

    /// Begin a jump move action — ignores figures and terrain except on the last hex.
    func beginJumpMoveAction(pieceID: PieceID, moveRange: Int) {
        beginMoveAction(pieceID: pieceID, moveRange: moveRange, mode: .jump)
    }

    /// Begin a fly move action — ignores figures and terrain for the whole move.
    func beginFlyMoveAction(pieceID: PieceID, moveRange: Int) {
        beginMoveAction(pieceID: pieceID, moveRange: moveRange, mode: .fly)
    }

    /// Begin a teleport action — can move to any empty revealed hex within range,
    /// ignoring obstacles, figures, traps, and terrain along the way.
    func beginTeleportAction(pieceID: PieceID, range: Int) {
        guard let pos = boardState.piecePositions[pieceID] else { return }
        if isConditionActive(.immobilize, on: pieceID) {
            log("\(name(pieceID)) is immobilized and can\u{2019}t move", category: .condition)
            interactionMode = .idle
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }

        var validHexes = Set<HexCoord>()
        for (coord, cell) in boardState.cells {
            guard cell.passable, !boardState.isOccupied(coord) else { continue }
            guard pos.distance(to: coord) <= range else { continue }
            validHexes.insert(coord)
        }

        interactionMode = .selectingMove(pieceID: pieceID, range: range, validHexes: validHexes, teleport: true)
        boardScene?.highlightHexes(validHexes, style: .teleport, offsetCol: offsetCol, offsetRow: offsetRow)
    }

    /// Execute a move to a target hex: the path that avoids traps and hazards when one fits the
    /// movement, otherwise the cheapest. Terrain and doors resolve on every hex entered.
    func executeMove(pieceID: PieceID, to target: HexCoord, range: Int, mode: MoveMode = .normal) {
        guard let pos = boardState.piecePositions[pieceID] else { return }
        let (enemies, allies) = movementSets(for: pieceID)

        guard let path = target == pos ? [pos] : Pathfinder.findPath(
            board: boardState, from: pos, to: target, mode: mode,
            canOpenDoors: true, maxCost: range,
            occupiedByEnemy: enemies, occupiedByAlly: allies
        ) else { return }

        boardScene?.clearHighlights()
        interactionMode = .idle
        let style: MovementStyle = mode == .jump ? .jump : (mode == .fly ? .fly : .normal)
        let turn = activePlayerTurn
        let generation = boardGeneration
        Task { @MainActor in
            await self.moveAlong(pieceID, path: path, style: style)
            guard self.isCurrentBoard(generation) else { return }
            // The move may end early (a trap that immobilizes, or one that exhausts the figure).
            if let end = self.boardState.piecePositions[pieceID] {
                let steps = path.firstIndex(of: end) ?? path.count - 1
                self.log("\(self.name(pieceID)) moves \(steps) hex\(steps == 1 ? "" : "es")", category: .move, trace: "to \(end)")
            }
            self.checkVictoryDefeat()
            turn?.advanceAfterAsyncAction()
        }
    }

    /// Where the board's grid starts in the scene (see `HexMath.gridOrigin`).
    static func sceneOffsets(for board: BoardState) -> (col: Int, row: Int) {
        HexMath.gridOrigin(minCol: board.bounds.minCol, minRow: board.bounds.minRow)
    }

    /// Execute a teleport to a target hex — direct placement, no pathfinding.
    /// Teleporting bypasses traps, hazards, and obstacles.
    func executeTeleport(pieceID: PieceID, to target: HexCoord) {
        guard let pos = boardState.piecePositions[pieceID] else { return }

        boardScene?.clearHighlights()
        interactionMode = .idle
        let turn = activePlayerTurn
        let generation = boardGeneration
        Task { @MainActor in
            await self.animateMove(pieceID, along: [pos, target], as: .teleport)
            guard self.isCurrentBoard(generation) else { return }
            self.boardState.movePiece(pieceID, to: target)
            self.log("\(self.name(pieceID)) teleports", category: .move, trace: "to \(target)")
            turn?.advanceAfterAsyncAction()
        }
    }

    /// Enemies of `pieceID` that it may target: in range, in line of sight, not invisible (p.21).
    func targetableEnemies(of pieceID: PieceID, range: Int) -> Set<PieceID> {
        guard let pos = boardState.piecePositions[pieceID] else { return [] }
        var targets = Set<PieceID>()
        // Eyes of the Night: invisible enemies can be targeted.
        let seesInvisible = chargedBonuses(of: pieceID).contains { $0.bonus == .advantageAndSeeInvisible }
        for (id, coord) in boardState.piecePositions where id != pieceID && areEnemies(pieceID, id) {
            guard entity(for: id) != nil, seesInvisible || !isConditionActive(.invisible, on: id) else { continue }
            guard pos.distance(to: coord) <= max(1, range),
                  LineOfSight.hasLOS(from: pos, to: coord, board: boardState) else { continue }
            targets.insert(id)
        }
        return targets
    }

    /// Allies of `pieceID` within range and line of sight (optionally including itself).
    func alliesInRange(of pieceID: PieceID, range: Int, includeSelf: Bool) -> Set<PieceID> {
        guard let pos = boardState.piecePositions[pieceID] else { return [] }
        var allies: Set<PieceID> = includeSelf ? [pieceID] : []
        for (id, coord) in boardState.piecePositions where id != pieceID && areAllies(pieceID, id) {
            guard entity(for: id) != nil, pos.distance(to: coord) <= max(1, range),
                  LineOfSight.hasLOS(from: pos, to: coord, board: boardState) else { continue }
            allies.insert(id)
        }
        return allies
    }

    /// Attack every visible enemy within `range` (each a separate attack of one action).
    func attackAllEnemies(from pieceID: PieceID, within range: Int, exactly: Bool = false) {
        if isConditionActive(.disarm, on: pieceID) {
            log("\(name(pieceID)) is disarmed and can\u{2019}t attack", category: .condition)
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }
        guard let pos = boardState.piecePositions[pieceID] else {
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }
        let targets = targetableEnemies(of: pieceID, range: range)
            .filter { !exactly || boardState.piecePositions[$0].map { pos.distance(to: $0) == range } == true }
            .sorted { $0.description < $1.description }
        attackEach(targets, from: pieceID, range: range)
    }

    /// "Attack all enemies moved through" (Trample): every enemy standing on a hex the
    /// character passed over in this half's move. An invisible one can't be targeted (p.21).
    func attackEnemiesMovedThrough(from pieceID: PieceID, hexes: [HexCoord]) {
        if isConditionActive(.disarm, on: pieceID) {
            log("\(name(pieceID)) is disarmed and can\u{2019}t attack", category: .condition)
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }
        let passed = Set(hexes)
        let targets = boardState.piecePositions
            .filter { passed.contains($0.value) && areEnemies(pieceID, $0.key) && !isConditionActive(.invisible, on: $0.key) }
            .map(\.key).sorted { $0.description < $1.description }
        if targets.isEmpty { log("\(name(pieceID)) moved through no enemy", category: .attack) }
        attackEach(targets, from: pieceID, range: 1)
    }

    /// One attack of the current action against each target in turn, then the action ends.
    private func attackEach(_ targets: [PieceID], from pieceID: PieceID, range: Int) {
        let value = activePlayerTurn?.currentAttackValue() ?? 2
        let turn = activePlayerTurn, generation = boardGeneration
        Task { @MainActor in
            for target in targets where self.isOnBoard(target) && self.isOnBoard(pieceID) {
                guard self.isCurrentBoard(generation) else { return }
                await self.resolvePlayerAttack(attacker: pieceID, target: target, attackValue: value,
                                               range: range, advanceAction: false)
            }
            guard self.isCurrentBoard(generation) else { return }
            turn?.advanceAfterAsyncAction()
        }
    }

    /// Enemies hit by an area attack aimed at `primary` (pattern oriented to hit the most others).
    func areaTargets(pattern: String, attacker: PieceID, primary: PieceID, range: Int) -> [PieceID] {
        guard let pos = boardState.piecePositions[attacker] else { return [] }
        let enemies = boardState.piecePositions.keys.sorted().filter { id in
            id != attacker && areEnemies(attacker, id) && entity(for: id) != nil && !isConditionActive(.invisible, on: id)
        }
        return AoEResolver.resolveTargets(pattern: pattern, attackerPos: pos, focusTarget: primary,
                                          enemies: Array(enemies), board: boardState, range: range)
    }

    /// The hexes an area attack aimed at `primary` covers.
    func areaPlacementHexes(pattern: String, attacker: PieceID, primary: PieceID, range: Int) -> Set<HexCoord> {
        guard let pos = boardState.piecePositions[attacker] else { return [] }
        let enemies = boardState.piecePositions.keys.sorted().filter { id in
            id != attacker && areEnemies(attacker, id) && entity(for: id) != nil && !isConditionActive(.invisible, on: id)
        }
        let placement = AoEResolver.bestPlacement(pattern: pattern, attackerPos: pos, focusTarget: primary,
                                                  enemies: Array(enemies), board: boardState, range: range)
        return Set(placement?.targetHexes ?? [])
    }

    /// Begin a player's attack action.
    func beginAttackAction(pieceID: PieceID, range: Int, targetCount: Int = 1) {
        if case .character = pieceID { teach(.attacking) }
        abilityTargets = []
        extraTargetsEarned = 0
        if isConditionActive(.disarm, on: pieceID) {
            log("\(name(pieceID)) is disarmed and can\u{2019}t attack", category: .condition)
            interactionMode = .idle
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }

        var validTargets = targetableEnemies(of: pieceID, range: range)
        if activePlayerTurn?.attackTexts.contains(where: { $0.contains("doomed enemy at any range") }) == true {
            validTargets = validTargets.filter(isDoomed)
        }
        if let pattern = activePlayerTurn?.pendingAreaPattern {
            // Area attack: any enemy the pattern can cover is a valid primary target.
            validTargets = Set(boardState.piecePositions.keys.filter { id in
                areEnemies(pieceID, id) && !areaTargets(pattern: pattern, attacker: pieceID, primary: id, range: range).isEmpty
            })
        }
        if validTargets.isEmpty {
            log("\(name(pieceID)) has no target within range \(range)", category: .attack)
            interactionMode = .idle
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }

        if targetCount > 1 {
            interactionMode = .selectingMultiAttackTargets(
                pieceID: pieceID, range: range, validTargets: validTargets,
                targetCount: targetCount, selected: []
            )
            log("\(name(pieceID)): choose up to \(targetCount) targets", category: .attack)
        } else {
            interactionMode = .selectingAttackTarget(pieceID: pieceID, range: range, validTargets: validTargets)
        }
        let targetHexes = Set(validTargets.compactMap { boardState.piecePositions[$0] })
        boardScene?.highlightHexes(targetHexes, style: .attack, offsetCol: offsetCol, offsetRow: offsetRow)
        showAttackPreviews(attacker: pieceID, targets: validTargets)
    }

    /// Begin an interactive condition-apply action (player taps a single enemy target).
    /// Choose who gets a condition: an enemy, or (`onAllies`) an ally. Returns false when no one
    /// is in range (the action is over).
    @discardableResult
    func beginConditionAction(pieceID: PieceID, condition: ConditionName, range: Int, onAllies: Bool = false) -> Bool {
        let validTargets = onAllies ? alliesInRange(of: pieceID, range: range, includeSelf: false)
                                    : targetableEnemies(of: pieceID, range: range)
        if validTargets.isEmpty {
            log("\(name(pieceID)) has no \(onAllies ? "ally" : "target") within range \(range) for \(GameText.conditionName(condition))",
                category: .condition)
            interactionMode = .idle
            if !onAllies { activePlayerTurn?.advanceAfterAsyncAction() }
            return false
        }

        interactionMode = .selectingConditionTarget(pieceID: pieceID, condition: condition, validTargets: validTargets)
        let targetHexes = Set(validTargets.compactMap { boardState.piecePositions[$0] })
        boardScene?.highlightHexes(targetHexes, style: .condition, offsetCol: offsetCol, offsetRow: offsetRow)
        return true
    }

    /// Begin an interactive heal action — the player picks themself or an ally (character or
    /// summon) within range and line of sight (p.25).
    func beginHealAction(pieceID: PieceID, healValue: Int, range: Int, conditions: [ConditionName] = []) {
        let validTargets = alliesInRange(of: pieceID, range: range, includeSelf: true)
        pendingHealConditions = conditions
        interactionMode = .selectingHealTarget(pieceID: pieceID, healValue: healValue, validTargets: validTargets)
        let targetHexes = Set(validTargets.compactMap { boardState.piecePositions[$0] })
        boardScene?.highlightHexes(targetHexes, style: .heal, offsetCol: offsetCol, offsetRow: offsetRow)
    }

    /// Apply a condition to all enemies within range from the acting piece (auto, no target selection).
    func applyConditionToAllEnemies(from pieceID: PieceID, condition: ConditionName, range: Int) {
        let targets = targetableEnemies(of: pieceID, range: range)
        for target in targets { applyCondition(condition, to: target) }
        if targets.isEmpty {
            log("\(name(pieceID)) has no enemy within range \(range) for \(GameText.conditionName(condition))", category: .condition)
        }
    }

    /// Apply a condition to all allies within range from the acting piece (auto, no target selection).
    func applyConditionToAllAllies(from pieceID: PieceID, condition: ConditionName, range: Int) {
        for ally in alliesInRange(of: pieceID, range: range, includeSelf: false) {
            applyCondition(condition, to: ally)
        }
    }

    /// Resolve a player attack on a single target. Called once per target.
    /// When `advanceAction` is true (default), calls `advanceAfterAsyncAction()` when done.
    /// Pass false when resolving multiple targets — the caller advances after all are resolved.
    @MainActor func resolvePlayerAttack(attacker: PieceID, target: PieceID, attackValue: Int, range: Int, advanceAction: Bool = true) async {
        let turn = activePlayerTurn
        let generation = boardGeneration
        abilityTargets.insert(target)
        lastAttackTarget = target
        lastAttackerPos = boardState.piecePositions[attacker]
        boardScene?.clearHighlights()

        let targetHex = boardState.piecePositions[target]
        // Bonuses in the attack's own text, judged for this target (Backstab, Perverse Edge…).
        var printed = turn.map { attackTextBonus($0.attackTexts, attacker: attacker, target: target) } ?? (attack: 0, experience: 0)
        // Skullbane Axe: more against the undead only.
        if case .monster(let monsterName, _) = target, let bonus = turn?.attackBonusAgainst[monsterName] {
            printed.attack += bonus
            turn?.attackBonusAgainst = [:]   // "to a single attack"
        }
        await performAttack(
            attacker: attacker, target: target,
            attack: AttackParameters(value: attackValueWithBonuses(attackValue + printed.attack, attacker: attacker, target: target),
                                     isRanged: range > 1,
                                     pierce: turn?.pendingPierce ?? 0,
                                     conditions: turn?.pendingConditions ?? [],
                                     push: turn?.pendingPush ?? 0,
                                     pull: turn?.pendingPull ?? 0,
                                     advantage: turn?.pendingAdvantage ?? false))
        guard isCurrentBoard(generation) else { return }

        // Massive Boulder: "all allies and enemies adjacent to the target suffer 1 damage".
        for text in turn?.attackTexts ?? [] where text.contains("adjacent to the target suffer") {
            await printedDamage(text, amount: PlayerTurnController.damageAmount(in: text), by: attacker, around: targetHex)
        }
        if printed.experience > 0, case .character(let id) = attacker,
           let character = gameManager?.game.characters.first(where: { $0.id == id }) {
            character.experience += printed.experience
            log("\(name(attacker)) gains \(printed.experience) XP", category: .info)
        }
        interactionMode = .idle
        if advanceAction { finishPlayerAttack(attacker: attacker, range: range, turn: turn) }
    }

    // MARK: - +1 Target

    /// Enemies the current attack ability has attacked, so an added target is another one.
    @ObservationIgnored var abilityTargets: Set<PieceID> = []
    /// Targets "+1 Target" modifier cards added to the current attack ability, not yet offered.
    @ObservationIgnored var extraTargetsEarned = 0

    /// End a character's attack ability: first offer the target a "+1 Target" card added (another
    /// enemy in range, attacked with its own draw; Skip declines), then move on.
    func finishPlayerAttack(attacker: PieceID, range: Int, turn: PlayerTurnController?) {
        if extraTargetsEarned > 0, turn?.pendingAreaPattern == nil, isOnBoard(attacker) {
            extraTargetsEarned -= 1
            let options = targetableEnemies(of: attacker, range: range).subtracting(abilityTargets)
            if !options.isEmpty {
                log("\(name(attacker)): choose another target", category: .attack)
                interactionMode = .selectingAttackTarget(pieceID: attacker, range: range, validTargets: options)
                let hexes = Set(options.compactMap { boardState.piecePositions[$0] })
                boardScene?.highlightHexes(hexes, style: .attack, offsetCol: offsetCol, offsetRow: offsetRow)
                return
            }
            log("\(name(attacker)) has no other enemy in range to add", category: .attack)
        }
        extraTargetsEarned = 0
        turn?.advanceAfterAsyncAction()
    }

    // MARK: - Push / Pull

    /// "Push/Pull X, all adjacent enemies": each enemy within reach is moved in turn.
    func forceMoveAllEnemies(from pieceID: PieceID, within reach: Int, steps: Int, isPush: Bool) {
        let targets = targetableEnemies(of: pieceID, range: reach).sorted { $0.description < $1.description }
        let turn = activePlayerTurn, generation = boardGeneration
        Task { @MainActor in
            for target in targets {
                guard self.isCurrentBoard(generation) else { return }
                guard let origin = self.boardState.piecePositions[pieceID], self.isOnBoard(target) else { continue }
                await self.performPushPull(target: target, attackerPos: origin, steps: steps, isPush: isPush)
            }
            guard self.isCurrentBoard(generation) else { return }
            turn?.advanceAfterAsyncAction()
        }
    }

    /// "Push/Pull X" on one enemy within range: the player picks the target.
    func beginForcedMoveTarget(pieceID: PieceID, range: Int, steps: Int, isPush: Bool) {
        let targets = targetableEnemies(of: pieceID, range: range)
        guard !targets.isEmpty else {
            log("\(name(pieceID)) has no enemy within range \(range) to \(isPush ? "push" : "pull")", category: .move)
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }
        interactionMode = .selectingForcedMoveTarget(pieceID: pieceID, steps: steps, isPush: isPush, validTargets: targets)
        let hexes = Set(targets.compactMap { boardState.piecePositions[$0] })
        boardScene?.highlightHexes(hexes, style: .forcedMove, offsetCol: offsetCol, offsetRow: offsetRow)
    }

    /// Begin a standalone push/pull action (top-level action, not attack sub-action).
    /// Applies to the target of the attack just made this turn.
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

    /// Start the interactive push/pull flow for a target.
    func beginPushPull(target: PieceID, attackerPos: HexCoord, remainingSteps: Int, isPush: Bool) {
        guard remainingSteps > 0,
              let targetPos = boardState.piecePositions[target] else {
            interactionMode = .idle
            completePushPullAction()
            return
        }

        let candidates = isPush
            ? targetPos.pushCandidates(awayFrom: attackerPos)
            : targetPos.pullCandidates(toward: attackerPos)

        // Each step must be into an empty-of-figures, passable hex; figures can't be forced
        // through a closed door. Difficult terrain doesn't matter (p.20, p.42).
        // Heaving Swing: "You may push the target into hexes containing obstacles."
        let intoObstacles = isPush && pushesIntoObstacles
        let valid = candidates.filter { coord in
            (boardState.isPassable(coord) || (intoObstacles && boardState.cells[coord]?.overlay == .obstacle))
                && !boardState.isOccupied(coord) && !boardState.isClosedDoor(coord)
        }

        if valid.isEmpty {
            let label = isPush ? "Push" : "Pull"
            log("\(name(target)) can\u{2019}t be \(isPush ? "pushed" : "pulled") any further", category: .move, trace: label)
            interactionMode = .idle
            completePushPullAction()
            return
        }

        if valid.count == 1 || autoResolvePrompts {
            executePushPullStep(target: target, to: valid[0], attackerPos: attackerPos, remainingSteps: remainingSteps, isPush: isPush)
        } else {
            let validSet = Set(valid)
            interactionMode = .selectingPushPullHex(
                target: target, attackerPos: attackerPos, validHexes: validSet,
                remainingSteps: remainingSteps, isPush: isPush
            )
            boardScene?.highlightHexes(validSet, style: .forcedMove, offsetCol: offsetCol, offsetRow: offsetRow)
        }
    }

    /// Execute one step of a push/pull. Traps and hazardous terrain trigger on every hex the
    /// target is forced into.
    func executePushPullStep(target: PieceID, to destination: HexCoord, attackerPos: HexCoord, remainingSteps: Int, isPush: Bool) {
        boardScene?.clearHighlights()
        interactionMode = .idle
        // The target left the board meanwhile: the push ends, or the attack waiting on it hangs.
        guard let currentPos = boardState.piecePositions[target] else { return completePushPullAction() }

        // Heaving Swing: pushed into an obstacle, it's destroyed; the target suffers 2 damage and
        // the character gains 1 experience.
        if isPush, pushesIntoObstacles, boardState.cells[destination]?.overlay == .obstacle {
            boardState.removeObstacle(at: destination)
            boardScene?.removeOverlaySprite(at: destination, offsetCol: offsetCol, offsetRow: offsetRow)
            log("\(name(target)) is driven into an obstacle and suffers 2 damage", category: .damage)
            if let id = activePlayerTurn?.characterID, let character = gameManager?.game.characters.first(where: { $0.id == id }) {
                character.experience += 1
                log("\(name(.character(id))) gains 1 XP", category: .info)
            }
            if sufferDamage(2, to: target, killer: activePlayerTurn.map { .character($0.characterID) }) {
                completePushPullAction()
                return
            }
        }
        let generation = boardGeneration
        Task { @MainActor in
            let alive = await self.moveAlong(target, path: [currentPos, destination], style: .forced)
            guard self.isCurrentBoard(generation) else { return }
            let stepsLeft = remainingSteps - 1
            if alive && stepsLeft > 0 {
                self.beginPushPull(target: target, attackerPos: attackerPos, remainingSteps: stepsLeft, isPush: isPush)
            } else {
                let label = isPush ? "Push" : "Pull"
                self.log("\(self.name(target)) is \(isPush ? "pushed" : "pulled")", category: .move, trace: "\(label) to \(destination)")
                self.completePushPullAction()
            }
        }
    }

    /// Whether the attack being made may push into obstacles (Heaving Swing).
    private var pushesIntoObstacles: Bool {
        activePlayerTurn?.attackTexts.contains { $0.contains("push the target into hexes containing obstacles") } == true
    }

    /// Resume the active player turn OR the pending push/pull continuation.
    private func completePushPullAction() {
        if let cont = pendingPushPullContinuation {
            pendingPushPullContinuation = nil
            cont.resume()
        } else {
            activePlayerTurn?.advanceAfterAsyncAction()
        }
    }

    /// Asynchronously execute a push/pull. Suspends until the push/pull is fully resolved
    /// (either auto-executed or after the player selects the direction).
    @MainActor func performPushPull(target: PieceID, attackerPos: HexCoord, steps: Int, isPush: Bool) async {
        // An objective on the map (an altar, a door) is never moved.
        guard steps > 0, boardState.piecePositions[target] != nil, !isScenery(target) else { return }
        // Some can't be forced to move (the Sightless Eye, the Elder Drake).
        if entity(for: target)?.immunities.contains(isPush ? .push : .pull) == true {
            log("\(name(target)) can\u{2019}t be \(isPush ? "pushed" : "pulled")", category: .move)
            return
        }
        if case .character(let id) = target,
           gameManager?.game.characters.first(where: { $0.id == id })?.carriedItems.contains(PassiveItems.unmovable) == true {
            log("\(name(target))\u{2019}s Heavy Greaves hold them in place", category: .move)
            return
        }
        let monstersTurn = isAutomatedTurn, generation = boardGeneration
        await withCheckedContinuation { [weak self] continuation in
            self?.pendingPushPullContinuation = continuation
            self?.beginPushPull(target: target, attackerPos: attackerPos, remainingSteps: steps, isPush: isPush)
        }
        // The push leaves the board idle; a monster's turn goes on, with Pause and fast-forward.
        if monstersTurn && isCurrentBoard(generation) { interactionMode = .watchingMonsterTurn }
    }

    // MARK: - Loot

    /// Drop a loot token at the current position of a killed monster.
    /// Must be called BEFORE removing the piece from the board.
    func dropLoot(for pieceID: PieceID) {
        guard case .monster = pieceID,
              let pos = boardState.piecePositions[pieceID] else { return }
        boardState.placeLoot(at: pos)
        boardScene?.addLootSprite(at: pos, offsetCol: offsetCol, offsetRow: offsetRow)
        log("A money token drops", category: .loot, trace: "at \(pos)")
    }

    /// Loot X: pick up every money token and treasure tile within range X and line of sight,
    /// regardless of monsters or obstacles in between (GH p.28).
    func collectLootInRange(pieceID: PieceID, range: Int) {
        guard let pos = boardState.piecePositions[pieceID] else { return }
        let coords = boardState.cells.keys.filter { coord in
            guard pos.distance(to: coord) <= range, hasLoot(at: coord) else { return false }
            return coord == pos || LineOfSight.hasLOS(from: pos, to: coord, board: boardState)
        }
        if coords.isEmpty {
            log("\(name(pieceID)) finds nothing to loot within range \(range)", category: .loot)
            return
        }
        lootHexes(for: pieceID, coords: coords.sorted(), byLootAction: true)
    }

    /// Whether a hex holds a money token or an unlooted treasure tile.
    func hasLoot(at coord: HexCoord) -> Bool {
        (boardState.lootTokens[coord] ?? 0) > 0 || boardState.cells[coord]?.overlay == .treasure
    }

    /// Loot every money token and treasure tile in `coords` for a character. Money tokens are
    /// worth the scenario level's gold conversion; numbered treasures give their reward from the
    /// treasure index. Summons and monsters never loot this way.
    /// `byLootAction`: a Loot ability is doing the looting — in some scenarios the only way
    /// to pick up the goal treasure.
    func lootHexes(for pieceID: PieceID, coords: [HexCoord], byLootAction: Bool = false) {
        guard case .character(let charID) = pieceID,
              let gameManager = gameManager,
              let character = gameManager.game.characters.first(where: { $0.id == charID }) else { return }

        var gold = 0
        var tokens = 0
        for coord in coords {
            // Money tokens dropped by monsters
            let dropped = boardState.takeLoot(at: coord)
            if dropped > 0 {
                boardScene?.removeLootSprite(at: coord, offsetCol: offsetCol, offsetRow: offsetRow)
                tokens += dropped
            }

            // Scenario treasure tiles: coins, or numbered/goal treasure chests
            guard let cell = boardState.cells[coord], cell.overlay == .treasure else { continue }
            if cell.overlaySubType == "coin" || cell.treasureID == nil {
                tokens += max(1, cell.treasureAmount ?? 1)
            } else if let id = cell.treasureID {
                // Where every character must loot one goal treasure tile, each loots only one.
                if id == Self.goalTreasureID {
                    guard byLootAction || !goalTreasureNeedsLootAction else { continue }
                    guard mayLootGoalTreasure(charID) else { continue }
                    noteGoalTreasureLooted(by: charID)
                    boardState.goalTreasuresLooted += 1
                }
                let reward = gameManager.scenarioManager.lootTreasure(id, by: character)
                log("\(characterName(charID)) loots treasure \(id)\(reward.map { ": \($0)" } ?? "")", category: .loot)
            }
            boardState.removeTreasure(at: coord)
            boardScene?.removeOverlaySprite(at: coord, offsetCol: offsetCol, offsetRow: offsetRow)
        }

        for _ in 0..<tokens {
            if let card = gameManager.lootManager.drawCard() {
                // Frosthaven loot deck
                let value = gameManager.lootManager.getValue(for: card)
                gameManager.lootManager.applyLoot(card, to: character)
                gold += value
            } else {
                // GH money token: worth the scenario level's gold conversion value.
                let value = gameManager.levelManager.loot()
                character.loot += value
                gold += value
            }
        }
        if tokens > 0 {
            gameManager.scenarioStatsManager.recordCoinsLooted(by: character.name, amount: tokens)
            log("\(characterName(charID)) loots \(tokens) money token\(tokens == 1 ? "" : "s") (\(gold) gold)", category: .loot)
            boardScene?.pieceLoot(id: pieceID, text: "+\(gold)g")
        }
        // Treasure can deal damage (e.g. a trapped chest).
        sweepDeadFigures()
        updateLocks()
    }

    // MARK: - Room Reveal

    /// Get adjacent unopened doors for a position.
    func adjacentDoors(from coord: HexCoord) -> [DoorInfo] {
        boardState.doors.filter {
            !$0.isOpen && !boardState.isLockedDoor($0.coord) && (coord.isAdjacent(to: $0.coord) || coord == $0.coord)
        }
    }

    /// Open a door and reveal the room behind it.
    func openDoor(at coord: HexCoord) {
        guard let door = boardState.doors.first(where: { $0.coord == coord && !$0.isOpen }),
              let scenario = scenarioData,
              let gameManager = gameManager, !isDoorBarred(at: coord) else { return }
        // Explorer: a door opened on a character's turn is theirs.
        if let character = creditedCharacter(for: actingPiece) {
            gameManager.scenarioStatsManager.recordDoor(by: character.name)
        }

        boardPhase = .roomReveal
        guard let reveal = BoardBuilder.revealRoomSlots(door: door, scenario: scenario, board: boardState) else {
            boardPhase = .execution
            return
        }

        // Monsters come from the scenario's room data, counted for every character in the
        // scenario including exhausted ones (p.17); the map supplies their positions.
        let playerCount = max(2, gameManager.game.characters.filter { !$0.absent }.count)
        let refs = Set(reveal.tileRefs.map { $0.lowercased() })
        let rooms = (gameManager.game.scenario?.data.rooms ?? []).filter { room in
            refs.contains((room.ref ?? "").lowercased())
                && !(gameManager.game.scenario?.revealedRooms.contains(room.roomNumber) ?? true)
        }
        for room in rooms {
            gameManager.scenarioManager.openRoom(room)
        }
        // Everything not yet on the board goes into this room — including monsters of a room a
        // scenario rule opened before its door was reached.
        let hasRoomData = !(gameManager.game.scenario?.data.rooms ?? []).isEmpty
        let placed = placeRevealedMonsters(slots: reveal.slots, newEntities: unplacedMonsterEntities(),
                                           playerCount: playerCount, useMapMonsters: !hasRoomData)
        let objectives = placeRevealedObjectives()

        // New monster types draw an ability card this round; all get their stat bonuses.
        for monster in gameManager.game.monsters where placed.contains(where: { $0.name == monster.name }) {
            if isMidRound, !monster.abilityDrawn {
                gameManager.monsterManager.drawAbility(for: monster)
            }
            gameManager.monsterManager.applyStatEffects(
                for: monster, only: Set(placed.filter { $0.name == monster.name }.map(\.standee)))
        }
        if isMidRound {
            for piece in placed { pendingRevealedStandees[piece.name, default: []].insert(piece.standee) }
        }

        // Draw the new room into the board as it stands (the grid offset stays put, so nothing
        // already drawn moves), and frame the board so the room is seen.
        boardScene?.revealRooms(from: boardState, scenario: scenario)
        syncPieceVisuals()
        boardScene?.fitCamera(animated: true)

        boardPhase = .execution
        log("A door opens and a new room is revealed", category: .door, trace: door.childTileRef)
        for piece in placed {
            let id = PieceID.monster(name: piece.name, standee: piece.standee)
            if let pos = boardState.piecePositions[id] {
                log("\(name(id)) appears", category: .setup, trace: "at \(pos)")
            }
        }
        for piece in objectives {
            log("\(name(piece)) is here", category: .setup, trace: boardState.piecePositions[piece].map { "at \($0)" })
        }
        // Rules gated on revealed rooms can fire now.
        gameManager.scenarioRulesManager.evaluateRules(phase: .figureChange)
        sweepDeadFigures()
        // The room's own doors may be locked, and its pressure plates are now in sight.
        updateLocks()
    }

    /// Reveal rooms opened by a scenario rule: through the door leading to the room's tile, or —
    /// if no door leads there — by opening the room's data and placing its monsters nearby.
    func openScenarioRooms(_ roomNumbers: [Int]) {
        guard let gameManager, let scenario = gameManager.game.scenario else { return }
        for number in roomNumbers {
            guard let room = scenario.data.rooms?.first(where: { $0.roomNumber == number }),
                  !scenario.revealedRooms.contains(number) else { continue }
            let ref = (room.ref ?? "").lowercased()
            // The door into the room: its tile may sit behind a corridor from the door's own.
            let scenarioMap = scenarioData
            if let door = boardState.doors.first(where: { door in
                !door.isOpen && (door.childTileRef.lowercased() == ref
                                 || (scenarioMap.map { BoardBuilder.roomRefs(behind: door, in: $0).contains(ref) } ?? false))
            }) {
                openDoor(at: door.coord)
            } else {
                gameManager.scenarioManager.openRoom(room)
                let playerCount = max(2, gameManager.game.characters.filter { !$0.absent }.count)
                let placed = placeRevealedMonsters(slots: [], newEntities: unplacedMonsterEntities(),
                                                   playerCount: playerCount)
                placeRevealedObjectives()
                for monster in gameManager.game.monsters where placed.contains(where: { $0.name == monster.name }) {
                    if isMidRound, !monster.abilityDrawn {
                        gameManager.monsterManager.drawAbility(for: monster)
                    }
                    gameManager.monsterManager.applyStatEffects(
                        for: monster, only: Set(placed.filter { $0.name == monster.name }.map(\.standee)))
                }
                if isMidRound {
                    for piece in placed { pendingRevealedStandees[piece.name, default: []].insert(piece.standee) }
                }
            }
        }
    }

    /// Whether figures are taking turns right now (not card selection, round start or round end).
    var isMidRound: Bool {
        boardPhase != .cardSelection && boardPhase != .setup && gameManager?.game.state == .next
            && currentTurnIndex >= 0 && currentTurnIndex < turnOrder.count
    }

    /// Alive monster entities that have no piece on the board yet.
    func unplacedMonsterEntities() -> [(GameMonster, GameMonsterEntity)] {
        guard let game = gameManager?.game else { return [] }
        var result: [(GameMonster, GameMonsterEntity)] = []
        for monster in game.monsters {
            for entity in monster.entities where !entity.dead {
                if boardState.piecePositions[.monster(name: monster.name, standee: entity.number)] == nil {
                    result.append((monster, entity))
                }
            }
        }
        return result
    }

    /// Place newly revealed monsters on the map's monster positions. Map positions are matched by
    /// monster name (preferring the same normal/elite marking); a scenario boss takes an unused
    /// position of a monster that isn't in the room (the map data uses stand-ins for bosses).
    /// With `useMapMonsters` (the scenario has no room data for these tiles) the map's own
    /// monster list is used instead. Returns the pieces placed.
    @discardableResult
    func placeRevealedMonsters(slots: [MonsterSlot], newEntities: [(GameMonster, GameMonsterEntity)],
                               playerCount: Int, useMapMonsters: Bool = false) -> [(name: String, standee: Int)] {
        guard gameManager != nil else { return [] }
        var placed: [(name: String, standee: Int)] = []

        if useMapMonsters && newEntities.isEmpty {
            for slot in slots {
                let type = slot.type(forPlayerCount: playerCount)
                guard type != "none" else { continue }
                if let piece = spawnMonster(name: slot.name, type: type == "elite" ? .elite : .normal,
                                            at: slot.coord, origin: .placed),
                   case .monster(let name, let standee) = piece {
                    placed.append((name, standee))
                }
            }
            return placed
        }

        var used = Set<Int>()
        let names = Set(newEntities.map { $0.0.name })
        let ordered = newEntities.sorted { a, b in
            if a.1.type != b.1.type { return a.1.type == .boss || (a.1.type == .elite && b.1.type == .normal) }
            return a.1.number < b.1.number
        }
        let anchor = slots.first?.coord ?? boardState.startingLocations.first ?? boardState.cells.keys.min()

        for (monster, entity) in ordered {
            func pick(_ predicate: (MonsterSlot) -> Bool) -> Int? {
                slots.indices.first { !used.contains($0) && predicate(slots[$0]) }
            }
            let wanted = entity.type == .elite ? "elite" : "normal"
            let index = pick { $0.name == monster.name && $0.type(forPlayerCount: playerCount) == wanted }
                ?? pick { $0.name == monster.name && $0.type(forPlayerCount: playerCount) != "none" }
                ?? pick { $0.name == monster.name }
                ?? pick { !names.contains($0.name) && $0.type(forPlayerCount: playerCount) != "none" }
                ?? pick { !names.contains($0.name) }
            var coord = index.map { slots[$0].coord } ?? anchor
            if let index { used.insert(index) }
            if let c = coord, boardState.isOccupied(c) || !boardState.isPassable(c) {
                coord = nearestEmptyHex(to: c)
            }
            guard let destination = coord else {
                log("No room to place \(name(.monster(name: monster.name, standee: entity.number)))", category: .setup)
                continue
            }
            let pieceID = PieceID.monster(name: monster.name, standee: entity.number)
            boardState.placePiece(pieceID, at: destination)
            if entity.type == .elite { boardState.eliteStandees.insert(pieceID) }
            boardScene?.addPieceSprite(id: pieceID, at: destination, offsetCol: offsetCol, offsetRow: offsetRow)
            placed.append((monster.name, entity.number))
        }
        return placed
    }

    /// A monster spawned by a scenario rule: on its lettered hex where one is written
    /// (`ScenarioPlacements`), otherwise near the other monsters. Spawned monsters act this round
    /// if spawned during it and drop no money.
    func spawnFromScenarioRule(name: String, type: MonsterType, marker: String?, health: String?) -> Bool {
        guard let gameManager, boardScene != nil || !boardState.cells.isEmpty else { return false }
        let monsterPositions = boardState.piecePositions.sorted { $0.key < $1.key }.compactMap { id, coord -> HexCoord? in
            if case .monster = id, !isPlayerSide(id) { return coord }
            return nil
        }
        let anchor = marker.flatMap(spawnHex(forMarker:)) ?? monsterPositions.first ?? boardState.cells.keys.max { a, b in
            let da = boardState.startingLocations.map { a.distance(to: $0) }.min() ?? 0
            let db = boardState.startingLocations.map { b.distance(to: $0) }.min() ?? 0
            return da == db ? a > b : da < db
        }
        guard let anchor,
              let piece = spawnMonster(name: name, type: type, at: anchor, origin: .spawned,
                                       health: health.map { .string($0) }) else { return false }
        if let marker, case .monster(let monsterName, let standee) = piece {
            gameManager.game.monsters.first { $0.name == monsterName }?
                .entities.last { $0.number == standee }?.markers.append(marker)
        }
        log("\(self.name(piece)) appears", category: .setup, trace: marker.map { "marker \($0)" })
        return true
    }

    // MARK: - Input Handling

    /// The sound of a tap on a figure while the board asks for one: an attack target chosen, or a
    /// figure that isn't among the choices.
    private func soundPieceTap(asked: InteractionMode, accepted: Bool) {
        switch asked {
        case .selectingAttackTarget, .selectingMultiAttackTargets:
            boardScene?.play(accepted ? .target : .invalid)
        case .selectingConditionTarget, .selectingHealTarget, .selectingForcedMoveTarget, .choosingPerformer:
            if !accepted { boardScene?.play(.invalid) }
        default:
            break
        }
    }

    func handleHexTap(_ coord: HexCoord) {
        if explainMode { return explainHex(at: coord) }
        let asked = String(describing: interactionMode)
        // A choice accepted can't be cancelled any more.
        defer { if String(describing: interactionMode) != asked { activePlayerTurn?.choiceMade() } }
        switch interactionMode {
        case .placingCharacter(let charID):
            placeCharacter(characterID: charID, at: coord)

        case .selectingMove(let pieceID, let range, let validHexes, let isTeleport, let mode):
            if validHexes.contains(coord) {
                if isTeleport {
                    executeTeleport(pieceID: pieceID, to: coord)
                } else {
                    executeMove(pieceID: pieceID, to: coord, range: range, mode: mode)
                }
            }

        case .placingSummon(let summonID, let characterID, let validHexes):
            if validHexes.contains(coord) {
                placeSummon(summonID: summonID, characterID: characterID, at: coord)
            }

        case .placingToken(let pieceID, let token, let remaining, let validHexes):
            if validHexes.contains(coord) {
                placeToken(token, at: coord, by: pieceID, remaining: remaining)
            }

        case .selectingPushPullHex(let target, let attackerPos, let validHexes, let remaining, let isPush):
            if validHexes.contains(coord) {
                executePushPullStep(target: target, to: coord, attackerPos: attackerPos, remainingSteps: remaining, isPush: isPush)
            }

        default:
            // Doors open only when a character enters the door hex during its movement (p.17).
            break
        }
    }

    func handlePieceTap(_ piece: PieceID) {
        if explainMode { return explain(.piece(piece)) }
        let asked = String(describing: interactionMode), askedMode = interactionMode
        defer {
            let accepted = String(describing: interactionMode) != asked
            if accepted { activePlayerTurn?.choiceMade() }
            soundPieceTap(asked: askedMode, accepted: accepted)
        }
        switch interactionMode {
        case .selectingMove(let mover, let range, let validHexes, false, let mode):
            // Move 0: the character taps themselves.
            if piece == mover, let pos = boardState.piecePositions[mover], validHexes.contains(pos) {
                executeMove(pieceID: mover, to: pos, range: range, mode: mode)
            }
        case .selectingAttackTarget(let attackerID, _, let validTargets):
            if validTargets.contains(piece), let forced = pendingForcedAttack {
                pendingForcedAttack = nil
                interactionMode = .idle
                boardScene?.clearHighlights()
                let turn = activePlayerTurn, generation = boardGeneration
                Task { @MainActor in
                    await self.performAttack(attacker: attackerID, target: piece, attack: forced)
                    guard self.isCurrentBoard(generation) else { return }
                    turn?.advanceAfterAsyncAction()
                }
            } else if validTargets.contains(piece) {
                let attackValue = activePlayerTurn?.currentAttackValue() ?? 2
                let range = activePlayerTurn?.currentAttackRange() ?? 1
                if let pattern = activePlayerTurn?.pendingAreaPattern {
                    // Area attack: every enemy in the pattern is a separate attack.
                    let targets = areaTargets(pattern: pattern, attacker: attackerID, primary: piece, range: range)
                    let ranged = !AoEResolver.isMeleePattern(pattern)
                    let areaHexes = areaPlacementHexes(pattern: pattern, attacker: attackerID, primary: piece, range: range)
                    let areaTexts = activePlayerTurn?.attackTexts ?? []
                    interactionMode = .idle
                    log("\(name(attackerID))\u{2019}s area attack hits \(targets.count) enem\(targets.count == 1 ? "y" : "ies")", category: .attack)
                    let turn = activePlayerTurn, generation = boardGeneration
                    Task { @MainActor in
                        for target in targets where self.isOnBoard(target) && self.isOnBoard(attackerID) {
                            guard self.isCurrentBoard(generation) else { return }
                            await self.resolvePlayerAttack(attacker: attackerID, target: target, attackValue: attackValue,
                                                           range: ranged ? max(2, range) : 1, advanceAction: false)
                        }
                        guard self.isCurrentBoard(generation) else { return }
                        // Unstable Explosives: "All allies in the attack area suffer 3 damage."
                        for text in areaTexts where text.contains("allies in the attack area suffer") {
                            let amount = PlayerTurnController.damageAmount(in: text)
                            let allies = self.boardState.piecePositions.filter {
                                areaHexes.contains($0.value) && $0.key != attackerID && self.areAllies(attackerID, $0.key)
                            }.map(\.key).sorted()
                            for ally in allies where self.isOnBoard(ally) && self.isCurrentBoard(generation) {
                                self.log("\(self.name(ally)) suffers \(amount) damage", category: .damage)
                                await self.sufferDamageWithMitigation(amount, to: ally, source: "the explosion", killer: attackerID)
                            }
                            guard self.isCurrentBoard(generation) else { return }
                        }
                        // Dirt Tornado: "Muddle all allies and enemies in the targeted area."
                        for text in areaTexts where text.contains("in the targeted area") && text.contains("allies and enemies") {
                            for action in PlayerTurnController.actions(fromText: text) where action.type == .condition {
                                guard let condition = action.value.flatMap({ ConditionName(rawValue: $0.stringValue) }) else { continue }
                                for figure in self.boardState.piecePositions.filter({ areaHexes.contains($0.value) && $0.key != attackerID })
                                    .map(\.key).sorted() {
                                    self.applyCondition(condition, to: figure)
                                }
                            }
                        }
                        turn?.advanceAfterAsyncAction()
                    }
                } else if activePlayerTurn?.attackTexts.contains(where: { $0.contains("all enemies on the path to the primary target") }) == true,
                          let from = boardState.piecePositions[attackerID], let to = boardState.piecePositions[piece] {
                    // Impaling Eruption: every enemy on the way to the target is attacked too.
                    let path = Set(from.line(to: to).dropFirst().dropLast())
                    // Invisible enemies can't be targeted, on the way or not.
                    let onTheWay = boardState.piecePositions.filter {
                        path.contains($0.value) && areEnemies(attackerID, $0.key) && !isConditionActive(.invisible, on: $0.key)
                    }.map(\.key).sorted()
                    interactionMode = .idle
                    let turn = activePlayerTurn, generation = boardGeneration
                    Task { @MainActor in
                        for target in onTheWay + [piece] where self.isOnBoard(target) {
                            guard self.isCurrentBoard(generation) else { return }
                            await self.resolvePlayerAttack(attacker: attackerID, target: target, attackValue: attackValue,
                                                           range: range, advanceAction: false)
                        }
                        guard self.isCurrentBoard(generation) else { return }
                        turn?.advanceAfterAsyncAction()
                    }
                } else {
                    interactionMode = .idle
                    Task { @MainActor in
                        await self.resolvePlayerAttack(attacker: attackerID, target: piece, attackValue: attackValue, range: range)
                    }
                }
            }

        case .selectingMultiAttackTargets(let attackerID, let range, let validTargets, let targetCount, var selected):
            if validTargets.contains(piece) && !selected.contains(piece) {
                selected.append(piece)
                log("\(name(attackerID)) targets \(name(piece)) (\(selected.count) of \(targetCount))", category: .attack)

                if selected.count >= targetCount || selected.count >= validTargets.count {
                    // All targets selected — resolve each attack in turn (each a separate attack)
                    let attackValue = activePlayerTurn?.currentAttackValue() ?? 2
                    let attackRange = activePlayerTurn?.currentAttackRange() ?? 1
                    let targets = selected
                    interactionMode = .idle
                    let turn = activePlayerTurn, generation = boardGeneration
                    Task { @MainActor in
                        for target in targets {
                            guard self.isCurrentBoard(generation) else { return }
                            await self.resolvePlayerAttack(attacker: attackerID, target: target, attackValue: attackValue, range: attackRange, advanceAction: false)
                        }
                        guard self.isCurrentBoard(generation) else { return }
                        self.finishPlayerAttack(attacker: attackerID, range: attackRange, turn: turn)
                    }
                } else {
                    // Update mode with new selected list, highlight remaining valid targets
                    let remaining = validTargets.subtracting(selected)
                    interactionMode = .selectingMultiAttackTargets(
                        pieceID: attackerID, range: range, validTargets: validTargets,
                        targetCount: targetCount, selected: selected
                    )
                    let targetHexes = Set(remaining.compactMap { boardState.piecePositions[$0] })
                    boardScene?.highlightHexes(targetHexes, style: .attack, offsetCol: offsetCol, offsetRow: offsetRow)
                }
            }

        case .selectingConditionTarget(let attackerID, let condition, let validTargets):
            if validTargets.contains(piece) {
                log("\(name(attackerID)) applies \(GameText.conditionName(condition)) to \(name(piece))", category: .condition)
                applyCondition(condition, to: piece)
                // Pendant of the Plague: Poison and Curse on the one target.
                for extra in pendingExtraConditions { applyCondition(extra, to: piece) }
                pendingExtraConditions = []
                boardScene?.clearHighlights()
                interactionMode = .idle
                activePlayerTurn?.advanceAfterAsyncAction()
            }

        case .selectingForcedMoveTarget(let moverID, let steps, let isPush, let validTargets):
            if validTargets.contains(piece), let origin = boardState.piecePositions[moverID] {
                boardScene?.clearHighlights()
                interactionMode = .idle
                let turn = activePlayerTurn, generation = boardGeneration
                Task { @MainActor in
                    await self.performPushPull(target: piece, attackerPos: origin, steps: steps, isPush: isPush)
                    guard self.isCurrentBoard(generation) else { return }
                    turn?.advanceAfterAsyncAction()
                }
            }

        case .choosingPerformer(_, let action, let candidates):
            if candidates.contains(piece) {
                boardScene?.clearHighlights()
                interactionMode = .idle
                perform(action, by: piece)
            }

        case .selectingHealTarget(let healerID, let healValue, let validTargets):
            if validTargets.contains(piece) {
                let healed = heal(piece, amount: healValue, source: healerID)
                log(healLine(healerID, healed: piece, for: healed), category: .heal, trace: "Heal \(healValue)")
                for condition in pendingHealConditions { applyCondition(condition, to: piece) }
                pendingHealConditions = []
                boardScene?.clearHighlights()
                interactionMode = .idle
                activePlayerTurn?.advanceAfterAsyncAction()
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
        let targets = selected
        interactionMode = .idle
        let turn = activePlayerTurn, generation = boardGeneration
        Task { @MainActor in
            for target in targets {
                guard self.isCurrentBoard(generation) else { return }
                await self.resolvePlayerAttack(attacker: attackerID, target: target, attackValue: attackValue, range: attackRange, advanceAction: false)
            }
            guard self.isCurrentBoard(generation) else { return }
            self.finishPlayerAttack(attacker: attackerID, range: attackRange, turn: turn)
        }
    }

    // MARK: - Snapshot

    func snapshot() -> BoardSnapshot {
        var snapshot = BoardSnapshot.from(boardState)
        if !characterTraps.isEmpty {
            snapshot.characterTraps = characterTraps.keys.sorted().map {
                BoardSnapshot.CharacterTrap(hex: $0, characterID: characterTraps[$0]!.characterID,
                                            experience: characterTraps[$0]!.experience)
            }
        }
        return snapshot
    }

    private func restoreCharacterTraps(from snapshot: BoardSnapshot) {
        characterTraps = Dictionary(uniqueKeysWithValues: (snapshot.characterTraps ?? []).map {
            ($0.hex, (characterID: $0.characterID, experience: $0.experience))
        })
    }

    func restore(from snapshot: BoardSnapshot) {
        snapshot.restore(to: boardState)
        restoreCharacterTraps(from: snapshot)
        // Rebuild visuals
        if let scenario = scenarioData {
            boardScene?.buildBoard(from: boardState, scenario: scenario, offsetCol: offsetCol, offsetRow: offsetRow,
                                   characterAppearances: buildCharacterAppearances())
            syncPieceVisuals()
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

    /// Add a line to the battle log. `message` is what the player reads, so it uses display names
    /// (`name(_:)`); grid coordinates and other technical detail go in `trace`.
    func log(_ message: String, category: TurnLogCategory = .info, trace: String? = nil) {
        var entry = TurnLogEntry(message: message, category: category, trace: trace)
        teachFromLog(category, message)
        // A monster's move and attack lines can say why it did them.
        if let why = currentWhyID, category == .move || category == .attack { entry.whyID = why }
        turnLog.append(entry)
    }

    /// The player-facing name of a piece: "Brute", "Bandit Guard 2", "Harmless Contraption".
    func name(_ piece: PieceID) -> String {
        GameText.pieceName(piece, game: gameManager?.game, labels: gameManager?.editionStore)
    }

    /// The player-facing name of a character, from its id.
    func characterName(_ id: String) -> String {
        name(.character(id))
    }

    /// The name of a monster type, e.g. "Bandit Guard".
    func monsterTypeName(_ name: String) -> String {
        let edition = gameManager?.game.monsters.first { $0.name == name }?.edition ?? gameManager?.game.edition
        return GameText.monsterName(name, edition: edition, labels: gameManager?.editionStore)
    }

    func logRoundHeader(_ round: Int) {
        turnLog.append(TurnLogEntry(message: "Round \(round)", category: .round, isRoundHeader: true))
    }
}
