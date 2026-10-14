import Foundation

/// State machine for a player's turn.
enum PlayerTurnPhase {
    case selectTopCard
    case executeTopAction
    case executeBottomAction
    /// A card played in addition to the turn's two (Ring of Haste, Staff of Command): one of
    /// its halves, before the turn goes on from where it was.
    case executeExtraHalf
    case turnComplete
}

/// Controls a single player character's turn on the board.
///
/// On their turn a character performs the top action of one of their two cards and the bottom
/// action of the other, in either order; any card can instead be used for a default Attack 2
/// (top) or Move 2 (bottom), and is then always discarded (GH p.16).
@Observable
final class PlayerTurnController {
    var phase: PlayerTurnPhase = .selectTopCard
    var characterID: String

    /// The character's name as the battle log shows it.
    private var who: String {
        coordinator?.characterName(characterID) ?? GameText.titleCased(characterID)
    }
    var topCard: AbilityModel?
    var bottomCard: AbilityModel?
    var topActions: [ActionModel] = []
    var bottomActions: [ActionModel] = []
    var currentActionIndex: Int = 0
    var isLongRest: Bool = false

    /// A card played in addition to the turn's two, while its half is performed.
    struct ExtraPlay {
        let card: AbilityModel
        let top: Bool
        /// Where the turn goes on from once the half is done.
        let resumePhase: PlayerTurnPhase
        let resumeIndex: Int
    }
    private(set) var extraPlay: ExtraPlay?
    var extraActions: [ActionModel] = []

    /// The half just finished, for the items that follow a kind of action (Staff of Command
    /// after a Command, Master's Lute after a Song): its side, and those kinds.
    struct FinishedHalf: Equatable {
        let top: Bool
        var kinds: Set<String>
    }
    var finishedHalf: FinishedHalf?

    /// Perform the bottom half before the top half.
    private(set) var bottomFirst: Bool = false
    /// Whether any action has been performed yet (cards can only be rearranged before that).
    private(set) var hasActed: Bool = false
    /// Halves played as the default Attack 2 / Move 2 — such cards always go to the discard pile.
    private(set) var topUsedAsDefault = false
    private(set) var bottomUsedAsDefault = false
    /// Halves ("top", "bottom", "extra") with at least one printed ability performed. A half
    /// skipped whole puts its card in the discard pile, lost or persistent icon or not (GH p.16).
    private(set) var performedHalves: Set<String> = []
    /// XP and infusions printed on their own in a half, met before any of its abilities was
    /// performed: they come only once one is (FAQ: "at least one ability on the action must be
    /// performed"), so they wait here until then.
    private var owedEffects: [String: [ActionModel]] = [:]
    /// The step being executed turned out to do nothing (an attack with no target, a Loot with
    /// nothing in range, a consume that couldn't be paid): it isn't performing the half.
    private var stepDidNothing = false
    /// A step is being executed right now (it may finish before `executeAction` returns).
    private var executingStep = false
    /// Markers ("round", "persistent") inside element bonuses that were paid for, by half: the
    /// card goes to the active area for them only then (Crackling Air's Fire: Retaliate).
    private var paidMarkers: [String: Set<String>] = [:]
    /// The half ("top": true) each card played for an active bonus this turn was played for.
    private(set) var halfInPlayThisTurn: [Int: Bool] = [:]
    /// A default Attack 2 / Move 2 is waiting for its target or destination.
    private var defaultAttackPending = false
    /// An action is waiting for player input or still resolving (attack, summon placement…).
    private(set) var awaitingAsync = false

    /// Pierce, push, pull, and conditions extracted from the current attack's sub-actions.
    var pendingPierce: Int = 0
    var pendingPush: Int = 0
    var pendingPull: Int = 0
    var pendingConditions: [ConditionName] = []
    /// Advantage on the attack being resolved (Eagle-Eye Goggles).
    var pendingAdvantage = false
    /// The printed text of the attack being made, for bonuses judged per target (Backstab).
    var attackTexts: [String] = []
    /// Hexes the character has moved this turn (not pushed or pulled), for movement items.
    var hexesMoved = 0
    /// Damage the character has dealt this turn (Balanced Measure's Move X).
    var damageInflicted = 0
    /// Extra loot range for the next Loot ability (Thief's Hood).
    var lootBonus = 0
    /// Whether a step is waiting for the player (a target, a hex).
    var isWaiting: Bool { awaitingAsync || defaultAttackPending }
    /// Damage the character chose to suffer this turn (Flurry of Axes' X).
    var damageSuffered = 0
    /// Hexes moved by the latest move action (Hook and Chain).
    var lastMoveLength = 0
    /// Hexes passed over (not ended on) during the latest move action, for "enemies moved through".
    var hexesPassed: [HexCoord] = []
    /// Cards whose persistent half was performed this turn: their charged bonus is in effect
    /// before they reach the active area. A bonus used up this turn never gets there.
    var persistentCardsThisTurn: [Int] = []
    /// Of those, the cards whose round half (not a persistent one) was played.
    var roundCardsThisTurn: [Int] = []
    /// Targets the next attack gains (Grim Bargain: Curse an ally for two).
    private var extraTargetsForNextAttack = 0
    /// Conditions the current move gives every enemy it passes over (Feedback Loop), and whether
    /// the move must end where it started for them to apply.
    var movedThroughConditions: [ConditionName] = []
    var movedThroughNeedsLoop = false
    /// Where the current move began: a move that must end there is made in legs.
    var moveStartHex: HexCoord?
    /// Text printed inside the current move, done when it ends (Rumbling Advance, Swift Bow).
    var afterMoveTexts: [String] = []
    var usedUpThisTurn: Set<Int> = []
    var magmaWadersHealed = false
    private var hornedHelmUsed = false
    /// Attack value and range of the attack being resolved (including element bonuses).
    private var pendingAttackValue: Int = 2
    private var pendingAttackRange: Int = 1
    /// Area-of-effect pattern of the attack being resolved, if any.
    private(set) var pendingAreaPattern: String?

    private weak var coordinator: BoardCoordinator?
    private weak var gameManager: GameManager?

    /// The turn as it stood when the current printed action began, so a target choice can be
    /// cancelled: everything the action did before asking (an element consumed, a charge
    /// marked, XP) is put back, and the action waits to be performed again.
    private struct ActionCheckpoint {
        let character: CharacterSnapshot
        let elements: [ElementModel]
        let elementsInfused: Set<ElementType>
        let positions: [PieceID: HexCoord]
        let cells: [HexCoord: HexCell]
        let logCount: Int
        let hasActed: Bool
        let topUsedAsDefault: Bool, bottomUsedAsDefault: Bool
        let performedHalves: Set<String>
        let owedEffects: [String: [ActionModel]]
        let paidMarkers: [String: Set<String>]
        let halfInPlayThisTurn: [Int: Bool]
        let roundCardsThisTurn: [Int]
        let topActions: [ActionModel], bottomActions: [ActionModel], extraActions: [ActionModel]
        let hexesMoved: Int, damageInflicted: Int, lootBonus: Int, damageSuffered: Int, lastMoveLength: Int
        let hexesPassed: [HexCoord]
        let persistentCardsThisTurn: [Int]
        let movedThroughConditions: [ConditionName]
        let movedThroughNeedsLoop: Bool
        let afterMoveTexts: [String]
        let usedUpThisTurn: Set<Int>
        let magmaWadersHealed: Bool, hornedHelmUsed: Bool
        let pendingHealConditions: [ConditionName], pendingExtraConditions: [ConditionName]
    }
    private var checkpoint: ActionCheckpoint?

    init(characterID: String, coordinator: BoardCoordinator, gameManager: GameManager) {
        self.characterID = characterID
        self.coordinator = coordinator
        self.gameManager = gameManager
    }

    private var character: GameCharacter? {
        gameManager?.game.characters.first { $0.id == characterID }
    }

    // MARK: - Card Selection

    /// Set the two selected cards and which is used for top/bottom.
    func selectCards(top: AbilityModel, bottom: AbilityModel) {
        self.topCard = top
        self.bottomCard = bottom
        self.topActions = halfSteps(of: top, top: true)
        self.bottomActions = halfSteps(of: bottom, top: false)
        self.phase = bottomFirst ? .executeBottomAction : .executeTopAction
        self.currentActionIndex = 0
        placeTurnBonusSteps()
    }

    /// A half of a card as the turn's steps, with the enhancements bought in town (GH p.42).
    private func halfSteps(of card: AbilityModel, top: Bool) -> [ActionModel] {
        let enhancements = character?.enhancements ?? []
        let labels = gameManager?.editionStore, edition = character?.edition ?? "gh"
        let printed = (top ? card.actions : card.bottomActions) ?? []
        return Self.steps(Self.attachingTargets(
            CardEnhancing.apply(enhancements, to: printed, cardId: card.cardId, half: top ? "top" : "bottom")),
            labels: labels, edition: edition)
    }

    /// Play another card from the hand and perform one of its halves now (Ring of Haste: the
    /// bottom; Ring of Brutality: the top). The turn goes on afterwards from where it was, and
    /// the card goes to the discard pile, or the lost pile or the active area as its half says.
    func playExtraHalf(_ card: AbilityModel, top: Bool) {
        guard extraPlay == nil, !isWaiting, let cardId = card.cardId,
              character?.handCards.contains(cardId) == true,
              cardId != topCard?.cardId || phase == .turnComplete,
              cardId != bottomCard?.cardId || phase == .turnComplete else { return }
        extraPlay = ExtraPlay(card: card, top: top, resumePhase: phase, resumeIndex: currentActionIndex)
        extraActions = halfSteps(of: card, top: top)
        performedHalves.remove("extra")
        finishedHalf = nil
        phase = .executeExtraHalf
        currentActionIndex = 0
        coordinator?.log("\(who) plays \(card.name ?? "a card") for its \(top ? "top" : "bottom") half", category: .round)
    }

    /// The half being performed is a Command (the Beast Tyrant's): its abilities are his bear's.
    var isCommandHalf: Bool {
        switch phase {
        case .executeTopAction: return Self.halfKinds(topCard?.actions ?? []).contains("command")
        case .executeBottomAction: return Self.halfKinds(bottomCard?.bottomActions ?? []).contains("command")
        case .executeExtraHalf:
            return extraPlay.map { Self.halfKinds(($0.top ? $0.card.actions : $0.card.bottomActions) ?? []).contains("command") } ?? false
        default: return false
        }
    }

    /// The figure performing the step being executed when it isn't the character: the bear, for
    /// a Command half. The character's own items and bonuses don't come with it.
    private(set) var commandedFigure: PieceID?
    /// How many enemies the last attack on "all enemies within range" targeted (Darkened Skies'
    /// experience for each two).
    private var allTargetsAttacked = 0
    /// Conditions the attack being made gives its own attacker once it is over.
    private var conditionsAfterAttack: [(piece: PieceID, condition: ConditionName)] = []
    private var bonusesApply: Bool { commandedFigure == nil }

    /// Kinds of action a printed half is, from the class tag at its start ("command", "song").
    static func halfKinds(_ printed: [ActionModel]) -> Set<String> {
        var kinds = Set<String>()
        func visit(_ action: ActionModel) {
            if action.type == .box, let tag = action.value?.stringValue {
                if tag.hasSuffix(".command%") { kinds.insert("command") }
                if tag.hasSuffix(".song%") { kinds.insert("song") }
            }
            (action.subActions ?? []).forEach(visit)
        }
        printed.forEach(visit)
        return kinds
    }

    /// Steps from charged bonuses that act at the start or end of the turn (Lumbering Bash,
    /// Auto Turret): before the first half's actions and after the second half's. Each is
    /// tagged with its card so performing it marks a charge.
    private func placeTurnBonusSteps() {
        func untagged(_ steps: [ActionModel]) -> [ActionModel] { steps.filter { Self.bonusCard(of: $0) == nil } }
        topActions = untagged(topActions)
        bottomActions = untagged(bottomActions)
        let (starts, ends) = turnBonusSteps()
        if bottomFirst {
            bottomActions = starts + bottomActions
            topActions += ends
        } else {
            topActions = starts + topActions
            bottomActions += ends
        }
    }

    /// The steps the character's charged bonuses add at the start and at the end of a turn, each
    /// tagged with its card.
    private func turnBonusSteps() -> (starts: [ActionModel], ends: [ActionModel]) {
        guard let character, let coordinator else { return ([], []) }
        var starts: [ActionModel] = [], ends: [ActionModel] = []
        for (cardId, bonus) in coordinator.chargedBonuses(of: character) {
            let tag = ActionModel(type: .card, value: .string("bonus:\(cardId)"))
            switch bonus {
            case .turnStartAction(var step):
                step.subActions = (step.subActions ?? []) + [tag]
                starts.append(step)
            case .turnEndAction(var step):
                step.subActions = (step.subActions ?? []) + [tag]
                ends.append(step)
            default:
                continue
            }
        }
        return (starts, ends)
    }

    // MARK: - Bonus steps on a long-rest turn

    /// What follows the rest turn's bonus steps being performed, while they are.
    private var afterRestSteps: (() -> Void)?

    /// A long rest is a turn (FAQ), so the bonuses that act "at the start/end of your next
    /// turns" act on it as well, a charge each: Lumbering Bash's and Triage's heal before the
    /// rest's card is chosen, Auto Turret's attack and Gas Canister's recovery before the turn
    /// ends. With no two halves to hold them, the steps are performed here one after another —
    /// a heal or an attack waits for its target as on any turn and may be skipped from the
    /// instruction — and `done` runs after the last (at once when there is none).
    func performRestBonusSteps(atStart: Bool, then done: @escaping () -> Void) {
        let steps = atStart ? turnBonusSteps().starts : turnBonusSteps().ends
        guard isLongRest, phase == .turnComplete, !steps.isEmpty, !(character?.exhausted ?? true) else { return done() }
        extraActions = steps
        phase = .executeExtraHalf
        currentActionIndex = 0
        afterRestSteps = done
        performNextRestStep()
    }

    /// The next of the rest turn's bonus steps; a finished step comes back here (`stepFinished`).
    private func performNextRestStep() {
        guard afterRestSteps != nil, phase == .executeExtraHalf, !isWaiting else { return }
        if currentActionIndex < extraActions.count, !(character?.exhausted ?? true) {
            executeCurrentAction()
        } else {
            finishRestSteps()
        }
    }

    private func finishRestSteps() {
        guard let done = afterRestSteps else { return }
        afterRestSteps = nil
        extraActions = []
        phase = .turnComplete
        currentActionIndex = 0
        done()
    }

    /// Steps from charged bonuses that go with the half's own moves and attacks: Wings of the
    /// Night's Move 2 before an attack, Black Knives' Attack 2, Range 3 after one made while
    /// invisible, Claws of the Night's attack on adjacent enemies after a move while invisible.
    /// Placed as the step is about to be performed, each tagged with its card for its charge.
    private func placeActionBonusSteps(at index: Int) {
        guard let character, let coordinator, index < currentSteps.count else { return }
        var step = currentSteps[index]
        // A step is given its bonus steps once (the mark is kept with the steps, so undo agrees).
        let placed = ActionModel(type: .card, value: .string("bonusStepsPlaced"))
        guard Self.bonusCard(of: step) == nil,
              !(step.subActions ?? []).contains(where: { $0.type == .card && $0.value?.stringValue == "bonusStepsPlaced" }) else { return }
        let invisible = coordinator.isConditionActive(.invisible, on: .character(characterID))
        var before: [ActionModel] = [], after: [ActionModel] = []
        for (cardId, bonus) in coordinator.chargedBonuses(of: character) {
            let tag = ActionModel(type: .card, value: .string("bonus:\(cardId)"))
            switch bonus {
            case .curseAllyForTargets(let range, let targets) where step.type == .attack:
                // Asked before the attack; a charge only if the player takes the bargain.
                before.append(ActionModel(type: .custom, value: .string("bonusChoice:curseAlly:\(cardId):\(range):\(targets)")))
            case .moveBeforeAttack(let n) where step.type == .attack:
                before.append(ActionModel(type: .move, value: .int(n), subActions: [tag]))
            case .attackAfterAttackWhileInvisible(let value, let range) where step.type == .attack && invisible:
                after.append(ActionModel(type: .attack, value: .int(value),
                                         subActions: [ActionModel(type: .range, value: .int(range)), tag]))
            case .attackAdjacentAfterMoveWhileInvisible(let value) where step.type == .move && invisible:
                after.append(ActionModel(type: .attack, value: .int(value),
                                         subActions: [ActionModel(type: .specialTarget, value: .string("enemiesAdjacent")), tag]))
            default:
                continue
            }
        }
        guard !before.isEmpty || !after.isEmpty else { return }
        step.subActions = (step.subActions ?? []) + [placed]
        var steps = currentSteps
        steps[index] = step
        steps.insert(contentsOf: after, at: index + 1)
        steps.insert(contentsOf: before, at: index)
        switch phase {
        case .executeTopAction: topActions = steps
        case .executeBottomAction: bottomActions = steps
        case .executeExtraHalf: extraActions = steps
        default: break
        }
    }

    /// Grim Bargain: "Curse one ally within Range 2 to gain two Target" on this attack, if the
    /// player wants to. A charge is marked only when they do.
    private func offerCurseForTargets(_ step: ActionModel, coordinator: BoardCoordinator) -> Bool {
        let parts = (step.value?.stringValue ?? "").split(separator: ":")
        guard parts.count == 5, let cardId = Int(parts[2]), let range = Int(parts[3]), let targets = Int(parts[4]),
              let character else { return false }
        let me = PieceID.character(characterID)
        let allies = coordinator.alliesInRange(of: me, range: range, includeSelf: false).sorted()
        guard !allies.isEmpty else { return false }
        let generation = coordinator.boardGeneration
        Task { @MainActor in
            let ally = await coordinator.chooseFigure(allies, title: "Grim Bargain",
                                                      question: "Curse an ally within Range \(range) for \(targets) more targets on this attack?",
                                                      declineTitle: "No Bargain")
            guard coordinator.isCurrentBoard(generation) else { return }
            if let ally {
                coordinator.applyCondition(.curse, to: ally)
                coordinator.useCharge(cardId, of: character)
                self.extraTargetsForNextAttack += targets
                coordinator.log("\(self.who) curses \(coordinator.name(ally)) for \(targets) more targets", category: .condition)
            }
            self.advanceAfterAsyncAction()
        }
        return true
    }

    /// The charged-bonus card a turn step comes from, if any.
    static func bonusCard(of step: ActionModel) -> Int? {
        (step.subActions ?? []).lazy.compactMap { sub -> Int? in
            guard sub.type == .card, let value = sub.value?.stringValue, value.hasPrefix("bonus:") else { return nil }
            return Int(value.dropFirst("bonus:".count))
        }.first
    }

    /// Use the other card for the top half (allowed until the first action is performed).
    func swapCards() {
        guard !hasActed, let top = topCard, let bottom = bottomCard else { return }
        selectCards(top: bottom, bottom: top)
        coordinator?.log("\(who) takes the top half from \(bottom.name ?? "the other card") and the bottom half from \(top.name ?? "the first card")", category: .round)
    }

    /// Choose whether to perform the bottom half first (allowed until the first action).
    func setBottomFirst(_ value: Bool) {
        guard !hasActed else { return }
        bottomFirst = value
        phase = value ? .executeBottomAction : .executeTopAction
        currentActionIndex = 0
        placeTurnBonusSteps()
    }

    /// Select long rest instead of cards.
    func selectLongRest() {
        isLongRest = true
        phase = .turnComplete
    }

    // MARK: - Action Execution

    /// Execute the current action in the current phase.
    func executeCurrentAction() {
        guard let coordinator = coordinator else { return }
        guard !defaultAttackPending, !awaitingAsync else { return }

        // A character exhausted during its own turn (e.g. by retaliate) takes no further actions;
        // its cards were already moved to the lost pile.
        if character?.exhausted ?? true {
            phase = .turnComplete
            return
        }
        if endIfStunned() { return }

        let actions: [ActionModel]
        switch phase {
        case .executeTopAction: actions = topActions
        case .executeBottomAction: actions = bottomActions
        case .executeExtraHalf: actions = extraActions
        default: return
        }

        guard currentActionIndex < actions.count else {
            advancePhase()
            return
        }

        finishedHalf = nil
        checkpoint = makeCheckpoint()
        hasActed = true
        placeActionBonusSteps(at: currentActionIndex)
        let action = currentSteps[currentActionIndex]
        // Performing one of the half's abilities is performing the half (its XP, its standalone
        // infusion and its lost icon follow); a step that turns out to do nothing isn't.
        let performedBefore = performedHalves
        if Self.bonusCard(of: action) == nil, Self.isAbilityStep(action), let half = halfKey { performedHalves.insert(half) }
        // Async actions (target/hex selection) advance in advanceAfterAsyncAction() — which may
        // already have happened synchronously (e.g. an attack with no valid target).
        awaitingAsync = true
        stepDidNothing = false
        executingStep = true
        let isAsync = executeAction(action, coordinator: coordinator)
        executingStep = false
        if stepDidNothing { performedHalves = performedBefore }
        if !isAsync {
            awaitingAsync = false
            currentActionIndex += 1
        }
        if !awaitingAsync { stepFinished() }
    }

    /// Advance the action index after an async action (attack/summon/condition/heal) resolves.
    func advanceAfterAsyncAction() {
        // A turn that is no longer the board's (the board was left, or the turn ended) stays put.
        guard coordinator?.activePlayerTurn === self else { return }
        for (piece, condition) in conditionsAfterAttack where coordinator?.isOnBoard(piece) == true {
            coordinator?.applyCondition(condition, to: piece)
        }
        conditionsAfterAttack = []
        if defaultAttackPending {
            defaultAttackPending = false
            awaitingAsync = false
            finishHalfAfterBasicAction()
            return
        }
        guard awaitingAsync else {
            // Exhausted by a rest turn's own bonus step (a retaliate on Auto Turret's attack):
            // nothing more is performed, and the turn goes on to its end.
            if character?.exhausted ?? true { finishRestSteps() }
            return
        }
        awaitingAsync = false
        currentActionIndex += 1
        if !executingStep { stepFinished() }
    }

    /// The step being executed could not be performed at all (no target, nothing to loot, no room
    /// for a summon): it doesn't count as performing the half, and what comes with performing
    /// it (XP, infusions) isn't gained.
    func abilityDidNothing() { stepDidNothing = true }

    /// Whether a step is one of the half's abilities, rather than what comes with performing
    /// them: experience, an infusion printed on its own, the card's markers.
    static func isAbilityStep(_ action: ActionModel) -> Bool {
        switch action.type {
        case .card, .experience: return false
        case .element: return MonsterAbility.isConsume(action)
        default: return true
        }
    }

    /// Whether the half being played has had one of its abilities performed.
    private var halfPerformed: Bool { halfKey.map(performedHalves.contains) ?? true }

    /// A step that harms the character or their allies ("suffer 2 damage", "all adjacent allies
    /// suffer 1 damage"): once the action is being performed it can't be left out (GH p.16).
    private func harmsOwnSide(_ step: ActionModel) -> Bool {
        switch step.type {
        case .suffer, .sufferDamage:
            return true
        case .custom:
            let text = customTextOfStep(step)
            guard text.contains("suffer") else { return false }
            return text.contains("allies") || !text.contains("enem")
        default:
            return false
        }
    }

    /// Steps that follow from performing the half without a choice: its XP and infusions (never
    /// optional, FAQ), and harm to the character's own side.
    private func isOwedOncePerformed(_ step: ActionModel) -> Bool {
        guard Self.bonusCard(of: step) == nil else { return false }
        return !Self.isAbilityStep(step) || (halfPerformed && harmsOwnSide(step))
    }

    /// A step has finished: what was waiting on the half being performed is gained, and the
    /// steps that need no choice are performed in turn.
    private func stepFinished() {
        performingHeal = false   // a heal made between steps (an item's) is its own Heal action
        settleOwedEffects()
        guard let coordinator, !(character?.exhausted ?? true) else { return }
        while !awaitingAsync, !defaultAttackPending, currentActionIndex < currentSteps.count,
              isOwedOncePerformed(currentSteps[currentActionIndex]) {
            executingStep = true
            let waits = executeAction(currentSteps[currentActionIndex], coordinator: coordinator)
            executingStep = false
            if waits {
                awaitingAsync = true
                return
            }
            currentActionIndex += 1
        }
        settleOwedEffects()
        performNextRestStep()
    }

    /// XP and infusions that were waiting for the half to be performed.
    private func settleOwedEffects() {
        guard let half = halfKey, performedHalves.contains(half), let owed = owedEffects.removeValue(forKey: half),
              let coordinator else { return }
        for effect in owed {
            if effect.type == .element {
                applyElementAction(effect, coordinator: coordinator)
            } else if effect.type == .experience {
                grantExperience(effect.value?.intValue ?? 1)
            } else if let xp = Self.experience(in: effect) {
                grantExperience(xp)
            }
        }
    }

    /// Keep a standalone XP or infusion for when (if) the half is performed.
    private func owe(_ effect: ActionModel) {
        guard let half = halfKey else { return }
        owedEffects[half, default: []].append(effect)
    }

    /// Skip remaining actions in the current phase. A pending target/hex selection is
    /// cancelled; an attack that is already resolving must finish first.
    func skipRemainingActions() {
        guard let coordinator else { return }
        // A move going on past a door ends in the doorway first (what it does as it ends happens).
        if coordinator.continuedMove != nil {
            coordinator.stopContinuedMove()
            return
        }
        if defaultAttackPending || awaitingAsync {
            switch coordinator.interactionMode {
            case .idle, .watchingMonsterTurn, .selectingPushPullHex:
                return
            default:
                abandonPendingChoice(coordinator: coordinator)
            }
        }
        // What performing the half has made due still happens: its XP and infusions aren't
        // optional, and harm to the character's own side can't be left out (GH p.16, FAQ).
        settleOwedEffects()
        if halfPerformed, !(character?.exhausted ?? true) {
            while currentActionIndex < currentSteps.count {
                let step = currentSteps[currentActionIndex]
                if isOwedOncePerformed(step) {
                    executingStep = true
                    let waits = executeAction(step, coordinator: coordinator)
                    executingStep = false
                    if waits {
                        awaitingAsync = true
                        return
                    }
                }
                currentActionIndex += 1
            }
        }
        advancePhase()
    }

    /// Drop the choice the board is waiting for. While nothing has come of the step yet it is
    /// taken back whole (an element paid, XP, its part in performing the half), as Cancel does.
    private func abandonPendingChoice(coordinator: BoardCoordinator) {
        if canCancelChoice {
            cancelChoice()
        } else {
            coordinator.interactionMode = .idle
            coordinator.pendingForcedAttack = nil
            coordinator.abandonSummonPlacement()
            coordinator.dropChoiceExtras()
            coordinator.boardScene?.clearHighlights()
            defaultAttackPending = false
            awaitingAsync = false
        }
    }

    /// Skip just the current ability of this half (any ability may be skipped, GH p.16) and go
    /// on to the next one. A pending target or hex selection for it is cancelled; an attack that
    /// is already resolving must finish first.
    func skipCurrentAction() {
        guard let coordinator else { return }
        // A push or pull not yet begun is turned down whole; the attack it follows stands.
        if coordinator.pushPullDeclinable {
            coordinator.declinePushPull()
            return
        }
        // A move going on past a door it opened: skipping the rest stops in the doorway.
        if coordinator.continuedMove != nil {
            coordinator.stopContinuedMove()
            return
        }
        if defaultAttackPending {
            skipRemainingActions()
            return
        }
        if awaitingAsync {
            switch coordinator.interactionMode {
            case .idle, .watchingMonsterTurn, .selectingPushPullHex:
                return
            default:
                abandonPendingChoice(coordinator: coordinator)
            }
        }
        let count = currentSteps.count
        guard phase == .executeTopAction || phase == .executeBottomAction || phase == .executeExtraHalf else { return }
        hasActed = true
        // XP, an infusion or harm to one's own side that performing the half has made due can't
        // be skipped: it happens instead.
        if currentActionIndex < count, halfPerformed, isOwedOncePerformed(currentSteps[currentActionIndex]) {
            executeCurrentAction()
            return
        }
        if currentActionIndex + 1 < count {
            currentActionIndex += 1
            stepFinished()
        } else {
            advancePhase()
        }
    }

    // MARK: - Cancelling a choice

    private func makeCheckpoint() -> ActionCheckpoint? {
        guard let character, let coordinator, let game = gameManager?.game else { return nil }
        return ActionCheckpoint(
            character: character.toSnapshot(), elements: game.elementBoard, elementsInfused: game.elementsInfusedThisTurn,
            positions: coordinator.boardState.piecePositions, cells: coordinator.boardState.cells,
            logCount: coordinator.turnLog.count, hasActed: hasActed,
            topUsedAsDefault: topUsedAsDefault, bottomUsedAsDefault: bottomUsedAsDefault,
            performedHalves: performedHalves, owedEffects: owedEffects, paidMarkers: paidMarkers,
            halfInPlayThisTurn: halfInPlayThisTurn, roundCardsThisTurn: roundCardsThisTurn,
            topActions: topActions, bottomActions: bottomActions, extraActions: extraActions,
            hexesMoved: hexesMoved, damageInflicted: damageInflicted, lootBonus: lootBonus,
            damageSuffered: damageSuffered, lastMoveLength: lastMoveLength, hexesPassed: hexesPassed,
            persistentCardsThisTurn: persistentCardsThisTurn, movedThroughConditions: movedThroughConditions,
            movedThroughNeedsLoop: movedThroughNeedsLoop, afterMoveTexts: afterMoveTexts,
            usedUpThisTurn: usedUpThisTurn, magmaWadersHealed: magmaWadersHealed, hornedHelmUsed: hornedHelmUsed,
            pendingHealConditions: coordinator.pendingHealConditions,
            pendingExtraConditions: coordinator.pendingExtraConditions)
    }

    /// Whether the choice the board is waiting for can be cancelled: it's the first choice of a
    /// printed action, nothing on the board has changed since the action began, and no other
    /// question is open.
    var canCancelChoice: Bool {
        guard let checkpoint, let coordinator, awaitingAsync || defaultAttackPending else { return false }
        switch coordinator.interactionMode {
        case .selectingMove, .selectingAttackTarget, .selectingMultiAttackTargets, .placingSummon, .placingToken,
             .choosingPerformer, .selectingConditionTarget, .selectingHealTarget, .selectingForcedMoveTarget:
            break
        case .idle, .placingCharacter, .selectingPushPullHex, .choosingHex, .watchingMonsterTurn:
            return false
        }
        if case .selectingMultiAttackTargets(_, _, _, _, let selected) = coordinator.interactionMode, !selected.isEmpty {
            return false
        }
        return coordinator.boardState.piecePositions == checkpoint.positions
            && coordinator.boardState.cells == checkpoint.cells
            && coordinator.pendingItemUse == nil && coordinator.pendingModifierDraw == nil
            && coordinator.pendingDamage == nil
            && (coordinator.pendingSummonPlacement == nil || { if case .placingSummon = coordinator.interactionMode { return true }; return false }())
    }

    /// Whether `action` is a single-target attack with no enemy in range right now, so its
    /// button can say so before it's spent on nothing.
    func attackHasNoTarget(_ action: ActionModel) -> Bool {
        guard action.type == .attack, let coordinator,
              !(action.subActions ?? []).contains(where: { $0.type == .area || $0.type == .specialTarget }) else { return false }
        return coordinator.targetableEnemies(of: .character(characterID), range: max(1, attackRange(of: action))).isEmpty
    }

    /// The player answered the board's question: from here the action can't be cancelled.
    func choiceMade() { checkpoint = nil }

    /// Cancel the choice: undo what the action did before asking, and wait to perform it again.
    func cancelChoice() {
        guard canCancelChoice, let checkpoint, let coordinator, let gameManager, let character else { return }
        coordinator.abandonSummonPlacement()
        checkpoint.character.apply(to: character, editionStore: gameManager.editionStore)
        gameManager.game.elementBoard = checkpoint.elements
        gameManager.game.elementsInfusedThisTurn = checkpoint.elementsInfused
        if coordinator.turnLog.count > checkpoint.logCount {
            coordinator.turnLog.removeLast(coordinator.turnLog.count - checkpoint.logCount)
        }
        hasActed = checkpoint.hasActed
        topUsedAsDefault = checkpoint.topUsedAsDefault
        bottomUsedAsDefault = checkpoint.bottomUsedAsDefault
        performedHalves = checkpoint.performedHalves
        owedEffects = checkpoint.owedEffects
        paidMarkers = checkpoint.paidMarkers
        halfInPlayThisTurn = checkpoint.halfInPlayThisTurn
        roundCardsThisTurn = checkpoint.roundCardsThisTurn
        defaultAttackPending = false
        topActions = checkpoint.topActions
        bottomActions = checkpoint.bottomActions
        extraActions = checkpoint.extraActions
        hexesMoved = checkpoint.hexesMoved
        damageInflicted = checkpoint.damageInflicted
        lootBonus = checkpoint.lootBonus
        damageSuffered = checkpoint.damageSuffered
        lastMoveLength = checkpoint.lastMoveLength
        hexesPassed = checkpoint.hexesPassed
        persistentCardsThisTurn = checkpoint.persistentCardsThisTurn
        movedThroughConditions = checkpoint.movedThroughConditions
        movedThroughNeedsLoop = checkpoint.movedThroughNeedsLoop
        afterMoveTexts = checkpoint.afterMoveTexts
        usedUpThisTurn = checkpoint.usedUpThisTurn
        magmaWadersHealed = checkpoint.magmaWadersHealed
        hornedHelmUsed = checkpoint.hornedHelmUsed
        resetPendingAttack(value: 2, range: 1)
        coordinator.pendingHealConditions = checkpoint.pendingHealConditions
        coordinator.pendingExtraConditions = checkpoint.pendingExtraConditions
        coordinator.pendingForcedAttack = nil
        coordinator.interactionMode = .idle
        coordinator.boardScene?.clearHighlights()
        coordinator.syncPieceVisuals()
        awaitingAsync = false
        self.checkpoint = nil
        // A rest turn has no button to perform the step again: it is asked anew.
        performNextRestStep()
    }

    /// The steps of the half being played.
    var currentSteps: [ActionModel] {
        switch phase {
        case .executeTopAction: return topActions
        case .executeBottomAction: return bottomActions
        case .executeExtraHalf: return extraActions
        default: return []
        }
    }

    /// The half being performed, as `performedHalves` keys it.
    private var halfKey: String? {
        switch phase {
        case .executeTopAction: return "top"
        case .executeBottomAction: return "bottom"
        case .executeExtraHalf: return "extra"
        default: return nil
        }
    }

    /// The card whose half is being performed.
    var currentCard: AbilityModel? {
        switch phase {
        case .executeTopAction: return topCard
        case .executeBottomAction: return bottomCard
        case .executeExtraHalf: return extraPlay?.card
        default: return nil
        }
    }

    /// Whether the half's basic action can still replace its printed abilities: none of them has
    /// been performed yet (start-of-turn bonus steps, Lumbering Bash's heal, don't count).
    var canUseDefaultAction: Bool {
        guard phase == .executeTopAction || phase == .executeBottomAction,
              !defaultAttackPending, !awaitingAsync, !(character?.exhausted ?? true) else { return false }
        let alreadyBasic = phase == .executeTopAction ? topUsedAsDefault : bottomUsedAsDefault
        return !alreadyBasic && currentSteps.prefix(currentActionIndex).allSatisfy { Self.bonusCard(of: $0) != nil }
    }

    /// The basic action's button: "Use Basic Attack 3" with a Versatile Dagger.
    var defaultActionTitle: String {
        let items = character?.carriedItems ?? []
        return phase == .executeTopAction
            ? "Use Basic Attack \(PassiveItems.defaultAttack(for: items))"
            : "Use Basic Move \(PassiveItems.defaultMove(for: items))"
    }

    /// What the scenario lets this character do instead of the half's abilities, where the basic
    /// action could still be used: the captives beside them, to free.
    var forgoTargets: [PieceID] {
        canUseDefaultAction ? (coordinator?.forgoTargets(for: characterID, bottomAction: phase == .executeBottomAction) ?? []) : []
    }

    /// The button that frees `target`: "Free Captive Orchid 3".
    func forgoTitle(_ target: PieceID) -> String {
        "\((coordinator?.forgoRule(for: target)?.verb ?? "free").capitalized) \(coordinator?.name(target) ?? "it")"
    }

    /// The goal treasure tiles beside the character that the half could be given up to loot.
    var forgoLootHexes: [HexCoord] {
        canUseDefaultAction ? (coordinator?.forgoLootHexes(for: characterID, bottomAction: phase == .executeBottomAction) ?? []) : []
    }

    /// Give up the half to free `target`: its abilities are passed over and the card is
    /// discarded, as after a basic action (no experience, no lost icon).
    func forgoAction(toFree target: PieceID) {
        guard let coordinator, forgoTargets.contains(target), giveUpTheHalf() else { return }
        coordinator.free(target, by: characterID)
        finishHalfAfterBasicAction()
    }

    /// Give up the half to loot the treasure tile on `hex`, beside the character.
    func forgoAction(toLoot hex: HexCoord) {
        guard let coordinator, forgoLootHexes.contains(hex), giveUpTheHalf() else { return }
        coordinator.lootForAnActionGivenUp(hex, by: characterID)
        finishHalfAfterBasicAction()
    }

    /// The half's abilities are passed over and its card will be discarded; false when the
    /// character can do nothing (stunned).
    private func giveUpTheHalf() -> Bool {
        if endIfStunned() { return false }
        finishedHalf = nil
        checkpoint = nil   // what the action is given up for isn't taken back
        hasActed = true
        let steps = currentSteps
        let kept = Array(steps.prefix(currentActionIndex)) + steps.dropFirst(currentActionIndex).filter { Self.bonusCard(of: $0) != nil }
        if phase == .executeTopAction {
            topActions = kept
            topUsedAsDefault = true
        } else {
            bottomActions = kept
            bottomUsedAsDefault = true
        }
        return true
    }

    /// After a basic action the half's printed abilities are done, but the turn's bonus steps in
    /// it still come (Auto Turret's attack at the end of the turn).
    private func finishHalfAfterBasicAction() {
        if currentActionIndex >= currentSteps.count { advancePhase() }
    }

    /// Use the default action for the current half instead of the printed one:
    /// Attack 2 on the top half, Move 2 on the bottom half.
    func useDefaultAction() {
        guard let coordinator = coordinator, !defaultAttackPending else { return }
        if character?.exhausted ?? true {
            endForExhaustion()
            return
        }
        if endIfStunned() { return }
        guard canUseDefaultAction else { return }
        finishedHalf = nil
        checkpoint = makeCheckpoint()
        hasActed = true
        // The basic action replaces the half's printed abilities; the turn's bonus steps in it
        // still to come stay, to be performed after it.
        let steps = currentSteps
        let kept = Array(steps.prefix(currentActionIndex)) + steps.dropFirst(currentActionIndex).filter { Self.bonusCard(of: $0) != nil }
        if phase == .executeTopAction { topActions = kept } else { bottomActions = kept }

        let pieceID = PieceID.character(characterID)
        switch phase {
        case .executeTopAction:
            // Versatile Dagger, Balanced Blade: a stronger basic attack.
            let value = PassiveItems.defaultAttack(for: character?.carriedItems ?? [])
            topUsedAsDefault = true
            resetPendingAttack(value: value, range: 1)
            pendingPierce += PassiveItems.meleePierce(for: character?.carriedItems ?? [])
            pendingPush += PassiveItems.meleePush(for: character?.carriedItems ?? [])
            pendingAttackValue += coordinator.roundAttackBonus(for: pieceID, ranged: false)
            defaultAttackPending = true
            coordinator.log("\(who) uses the basic Attack \(value)", category: .attack)
            coordinator.beginAttackAction(pieceID: pieceID, range: 1)
        case .executeBottomAction:
            // Comfortable Shoes, Serene Sandals: a longer basic move.
            let value = PassiveItems.defaultMove(for: character?.carriedItems ?? [])
            bottomUsedAsDefault = true
            defaultAttackPending = true // ends the half once the move resolves
            coordinator.log("\(who) uses the basic Move \(value)", category: .move)
            coordinator.beginMoveAction(pieceID: pieceID, moveRange: value,
                                        mode: PassiveItems.flies(character?.carriedItems ?? []) ? .fly : .normal)
        default:
            break
        }
    }

    /// The character was exhausted during its own turn (e.g. by retaliate): it takes no further
    /// actions, and its cards are already in the lost pile (GH p.27).
    func endForExhaustion() {
        defaultAttackPending = false
        awaitingAsync = false
        phase = .turnComplete
    }

    /// The character was stunned in the middle of its own turn (a Stun trap sprung on the way):
    /// it performs no more abilities this turn (GH p.22). What is left of both halves is passed
    /// over and the cards are put away as played; the Stun lasts to the end of its next turn.
    /// True when the turn was ended.
    private func endIfStunned() -> Bool {
        var performing: Bool { phase == .executeTopAction || phase == .executeBottomAction || phase == .executeExtraHalf }
        guard let coordinator, performing, coordinator.isConditionActive(.stun, on: .character(characterID)) else { return false }
        coordinator.log("\(who) is stunned and can do nothing more this turn", category: .condition)
        defaultAttackPending = false
        awaitingAsync = false
        // An extra half first, then what is left of the turn's two.
        for _ in 0..<3 where performing { advancePhase() }
        return true
    }

    // MARK: - Queries

    /// The attack value of the attack currently being resolved.
    func currentAttackValue() -> Int { pendingAttackValue }

    /// The value and range of an attack another figure performs for the character (Possession).
    func preparePerformedAttack(value: Int, range: Int) { resetPendingAttack(value: value, range: range) }

    /// Add to the attack being resolved (Minor Power Potion).
    func addToAttack(_ bonus: Int) { pendingAttackValue += bonus }

    /// Turn the attack being targeted into an area attack (Battle-Axe).
    func setAreaPattern(_ pattern: String) { pendingAreaPattern = pattern }

    /// More range for the attack being targeted (Hawk Helm).
    func extendAttackRange(by extra: Int) { pendingAttackRange += extra }

    /// The range of the attack currently being resolved.
    func currentAttackRange() -> Int { pendingAttackRange }

    // MARK: - Private

    private func advancePhase() {
        settleOwedEffects()
        if let half = halfKey { owedEffects[half] = nil }
        // The tag is printed on the card (the steps leave it out).
        switch phase {
        case .executeTopAction: finishedHalf = FinishedHalf(top: true, kinds: Self.halfKinds(topCard?.actions ?? []))
        case .executeBottomAction:
            finishedHalf = FinishedHalf(top: false, kinds: Self.halfKinds(bottomCard?.bottomActions ?? []))
        case .executeExtraHalf:
            if let extra = extraPlay {
                finishedHalf = FinishedHalf(top: extra.top,
                                            kinds: Self.halfKinds((extra.top ? extra.card.actions : extra.card.bottomActions) ?? []))
            }
        default: break
        }
        switch (phase, bottomFirst) {
        case (.executeTopAction, false):
            phase = .executeBottomAction
            currentActionIndex = 0
        case (.executeBottomAction, true):
            phase = .executeTopAction
            currentActionIndex = 0
        case (.executeTopAction, true), (.executeBottomAction, false):
            phase = .turnComplete
            finishTurn()
        case (.executeExtraHalf, _):
            if afterRestSteps != nil { finishRestSteps() } else { finishExtraHalf() }
        default:
            break
        }
    }

    /// The extra card's half is done: the card is put away, and the turn goes on.
    private func finishExtraHalf() {
        guard let extra = extraPlay else { return }
        if let character, !character.exhausted {
            putAway(extra.card, half: extraActions, lostFlag: extra.top ? extra.card.lost == true : extra.card.bottomLost == true,
                    usedAsDefault: false, key: "extra", top: extra.top, character: character)
        }
        extraPlay = nil
        extraActions = []
        paidMarkers["extra"] = nil
        phase = extra.resumePhase
        currentActionIndex = extra.resumeIndex
    }

    private func resetPendingAttack(value: Int, range: Int) {
        pendingAttackValue = value
        pendingAttackRange = range
        pendingAreaPattern = nil
        pendingAdvantage = false
        attackTexts = []
        pendingPierce = 0
        pendingPush = 0
        pendingPull = 0
        pendingConditions = []
        attackBonusAgainst = [:]
        bonusPerAttack = nil
    }

    /// What a bonus counted in attacks adds to each attack of the action being made (Crackling
    /// Air: +1, or +2 with Air consumed), while it has charges left.
    var bonusPerAttack: Int?
    /// The Heal action being performed, for a bonus counted in Heal actions (Master Physician):
    /// whether its charge has been marked, and so whether this action's heals cleanse.
    var healActionCleanses: Bool?
    private(set) var performingHeal = false

    /// More attack against monsters of these types only, for the attack being made (Skullbane Axe).
    var attackBonusAgainst: [String: Int] = [:]

    /// The Psychic Knife: an attack an augment shapes gets +1 more.
    static let psychicKnife = "gh-139"

    // MARK: - Consuming elements, by choice

    /// An element bonus printed on the current step, which the player may pay for or not
    /// (consuming is optional: an element may be kept for an ally — iPad playthrough 2026-10-09,
    /// Mana Bolt took the Earth the Cragheart had infused for Earthen Clod).
    struct ConsumeOption: Identifiable, Equatable {
        /// Its place among the step's consume bonuses.
        let id: Int
        let elements: [ElementType]
        /// "Earth: Push 2", "Fire: Wound".
        let label: String
        /// The elements are there to consume.
        let payable: Bool
        /// The player chose to keep the elements.
        let declined: Bool
        /// For "any element": what it would take, one per slot, and what the player may pick from.
        var anyElement: [ElementType] = []
        var anyElementChoices: [ElementType] = []
    }

    /// Consume bonuses of the current step the player turned down, by `ConsumeOption.id`.
    private var declinedConsumes: Set<Int> = []
    /// The step those choices belong to; another step starts with every bonus taken.
    private var declinedConsumesStep: String = ""
    /// The elements the player picked for a bonus's "any element", by `ConsumeOption.id`, for the
    /// step `declinedConsumesStep`.
    private var anyElementPicks: [Int: [ElementType]] = [:]

    private var stepKey: String { "\(phase)-\(currentActionIndex)" }

    /// Ids of `ConsumeOption`s for an element an active bonus consumes by itself at an attack
    /// (Nature's Lift, Foul Wind): after the step's own printed bonuses.
    private static let bonusConsumeIds = 100

    /// The element bonuses on `action`, whether each can be paid and whether it's turned down;
    /// for an attack, the Air that Nature's Lift and Foul Wind would consume too.
    func consumeOptions(for action: ActionModel) -> [ConsumeOption] {
        guard let game = gameManager?.game else { return [] }
        // Clearing's penalty: no element can be consumed for the rest of the scenario.
        if coordinator?.cannotConsume(.character(characterID)) == true { return [] }
        let declined = declinedConsumesStep == stepKey ? declinedConsumes : []
        var options = (action.subActions ?? []).filter(MonsterAbility.isConsume).enumerated().map { index, sub in
            let elements = MonsterAbility.elements(of: sub)
            let paying = payment(for: index, of: elements)
            let names = GameText.list(elements.enumerated().map { slot, element in
                guard element == .wild else { return GameText.elementName(element) }
                let wilds = elements.prefix(slot).filter { $0 == .wild }.count
                let named = elements.filter { $0 != .wild }.count
                return paying.indices.contains(named + wilds) && paying[named + wilds] != .wild
                    ? "any element (\(GameText.elementName(paying[named + wilds])))" : "any element"
            })
            let reward = bonusWords(sub)
            var option = ConsumeOption(id: index, elements: elements,
                                       label: reward.isEmpty ? names : "\(names): \(reward)",
                                       payable: game.canConsumeElements(elements), declined: declined.contains(index))
            if elements.contains(.wild) {
                let named = elements.filter { $0 != .wild }
                option.anyElement = Array(paying.dropFirst(named.count)).filter { $0 != .wild }
                option.anyElementChoices = game.wildCandidates(besides: named).sorted { $0.rawValue < $1.rawValue }
            }
            return option
        }
        if action.type == .attack, let character, let coordinator {
            let ranged = (action.subActions ?? []).contains { $0.type == .range && ($0.value?.intValue ?? 0) > 1 }
            for (index, entry) in elementConsumingBonuses(of: character, coordinator: coordinator).enumerated() {
                let id = Self.bonusConsumeIds + index
                let (element, words, needsRange) = entry.what
                options.append(ConsumeOption(id: id, elements: [element],
                                             label: "\(GameText.elementName(element)): \(words) (\(entry.name))",
                                             payable: game.isElementAvailable(element) && (!needsRange || ranged),
                                             declined: declined.contains(id)))
            }
        }
        return options
    }

    /// The active bonuses that consume an element by themselves at an attack, in order: Nature's
    /// Lift (+2 Range on a ranged attack), Foul Wind (+1 Attack).
    private func elementConsumingBonuses(of character: GameCharacter, coordinator: BoardCoordinator)
        -> [(cardId: Int, name: String, what: (ElementType, String, Bool))] {
        if coordinator.cannotConsume(.character(character.id)) { return [] }
        let deck = gameManager?.characterManager.abilities(for: character) ?? []
        return coordinator.chargedBonuses(of: character).compactMap { cardId, bonus in
            let name = deck.first { $0.cardId == cardId }?.name ?? "a bonus"
            switch bonus {
            case .consumeForRange(let element, let extra): return (cardId, name, (element, "+\(extra) Range", true))
            case .consumeForAttack(let element, let extra): return (cardId, name, (element, "+\(extra) Attack", false))
            default: return nil
            }
        }
    }

    /// What a consume of `elements` takes: its "any element" slots filled with the player's
    /// picks where those are still there, else strong elements first. A slot nothing can fill
    /// stays `.wild` (and the bonus can't be paid).
    private func payment(for id: Int, of elements: [ElementType]) -> [ElementType] {
        guard elements.contains(.wild), let game = gameManager?.game else { return elements }
        let named = elements.filter { $0 != .wild }
        let wilds = elements.count - named.count
        var picks: [ElementType] = []
        for element in (declinedConsumesStep == stepKey ? anyElementPicks[id] ?? [] : [])
        where game.isElementAvailable(element) && !named.contains(element) && !picks.contains(element) && picks.count < wilds {
            picks.append(element)
        }
        for element in game.wildCandidates(besides: named + picks) where picks.count < wilds { picks.append(element) }
        return named + picks + Array(repeating: .wild, count: wilds - picks.count)
    }

    /// The player picks the element a bonus's "any element" takes (its `slot`th, for one that
    /// names two).
    func pickAnyElement(_ id: Int, slot: Int = 0, _ element: ElementType) {
        if declinedConsumesStep != stepKey {
            declinedConsumes = []
            anyElementPicks = [:]
            declinedConsumesStep = stepKey
        }
        let step = currentSteps.indices.contains(currentActionIndex) ? currentSteps[currentActionIndex] : ActionModel(type: .attack)
        let elements = consumeOptions(for: step).first { $0.id == id }?.anyElement ?? []
        var picks = anyElementPicks[id] ?? elements
        while picks.count <= slot { picks.append(element) }
        picks[slot] = element
        anyElementPicks[id] = picks
    }

    /// Whether the player turned down the element of `ConsumeOption` `id` at this step.
    private func declinedConsume(_ id: Int) -> Bool {
        declinedConsumesStep == stepKey && declinedConsumes.contains(id)
    }

    /// Take or turn down one of the current step's element bonuses.
    func toggleConsume(_ id: Int) {
        if declinedConsumesStep != stepKey {
            declinedConsumes = []
            anyElementPicks = [:]
            declinedConsumesStep = stepKey
        }
        if declinedConsumes.contains(id) { declinedConsumes.remove(id) } else { declinedConsumes.insert(id) }
    }

    /// What a consume bonus gives, in words: "Push 2", "Wound", "+1 Attack".
    private func bonusWords(_ consume: ActionModel) -> String {
        var words: [String] = []
        for effect in consume.subActions ?? [] {
            switch effect.type {
            case .concatenation: words += (effect.subActions ?? []).filter { $0.type != .experience }.map(GameText.actionTitle)
            case .experience: continue
            case .custom:
                if let key = effect.value?.stringValue, let character,
                   let text = gameManager?.editionStore.resolveCustomText(key, edition: character.edition) {
                    words.append(text.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))
                }
            default:
                words.append(GameText.actionTitle(effect))
            }
        }
        return words.joined(separator: ", ")
    }

    /// Pay for every element-consume augment on the action that can be paid for and that the
    /// player hasn't turned down, and return their bonus effects (GH p.24: all listed elements
    /// are needed for one augment).
    private func consumeAugments(of action: ActionModel) -> [ActionModel] {
        guard let game = gameManager?.game else { return [] }
        let declined = declinedConsumesStep == stepKey ? declinedConsumes : []
        var bonus: [ActionModel] = []
        for (index, sub) in (action.subActions ?? []).filter(MonsterAbility.isConsume).enumerated() {
            if declined.contains(index) {
                guard game.canConsumeElements(MonsterAbility.elements(of: sub)) else { continue }
                coordinator?.log("\(who) keeps \(GameText.list(MonsterAbility.elements(of: sub).map(GameText.elementName)))", category: .element)
                continue
            }
            let elements = payment(for: index, of: MonsterAbility.elements(of: sub))
            guard let used = game.consumeElements(elements) else { continue }
            coordinator?.log("\(who) consumes \(GameText.list(used.map(GameText.elementName)))", category: .element)
            notePaidConsume(sub)
            for effect in sub.subActions ?? [] {
                if effect.type == .concatenation {
                    bonus.append(contentsOf: effect.subActions ?? [])
                } else if effect.type == .custom, let key = effect.value?.stringValue, let character,
                          let text = gameManager?.editionStore.resolveCustomText(key, edition: character.edition) {
                    // A bonus printed as text ("Immobilize, XP +1", "Push 2"): read what the board can.
                    bonus.append(contentsOf: Self.actions(fromText: text))
                } else {
                    bonus.append(effect)
                }
            }
        }
        return bonus
    }

    /// Crackling Air: "Air: add +2 Attack instead" is paid once, as the card is played, and the
    /// card remembers it for all four attacks (FAQ) — unless the player keeps the Air.
    private func payElementAsPlayed(_ action: ActionModel, coordinator: BoardCoordinator) {
        guard let character, let card = currentCard, let cardId = card.cardId,
              case .attackBonusOrElement(_, let element, _)? = ChargedBonus.bonus(edition: character.edition, card: card,
                                                                                                    top: phase == .executeTopAction),
              let index = (action.subActions ?? []).filter(MonsterAbility.isConsume).firstIndex(where: {
                  MonsterAbility.elements(of: $0) == [element] }),
              let game = gameManager?.game else { return }
        character.elementBonusesPaid.remove(cardId)
        guard game.isElementAvailable(element) else { return }
        if declinedConsume(index) {
            coordinator.log("\(who) keeps \(GameText.elementName(element))", category: .element)
            return
        }
        _ = game.consumeElements([element])
        character.elementBonusesPaid.insert(cardId)
        coordinator.log("\(who) consumes \(GameText.elementName(element)) for \(card.name ?? "the card")\u{2019}s attacks", category: .element)
    }

    /// Experience printed in a bonus (e.g. "card experience:1" inside a consume augment).
    private func grantBonusExperience(_ bonus: [ActionModel]) {
        for effect in bonus {
            if effect.type == .experience, let xp = effect.value?.intValue {
                grantExperience(xp)
            } else if effect.type == .card, let value = effect.value?.stringValue, value.hasPrefix("experience:"),
                      let xp = Int(value.dropFirst("experience:".count)) {
                grantExperience(xp)
            }
        }
    }

    /// XP printed as "card experience:N".
    static func experience(in action: ActionModel) -> Int? {
        guard action.type == .card, let value = action.value?.stringValue, value.hasPrefix("experience:") else { return nil }
        return Int(value.dropFirst("experience:".count))
    }

    /// The half's card counts as in play for its active bonus from now on (before it reaches
    /// the active area at the end of the turn): its markers, leaving out those inside element
    /// bonuses that haven't been paid for.
    private func noteCardInPlay() {
        guard let half = halfKey, let cardId = currentCard?.cardId else { return }
        let markers = Self.markers(in: currentSteps, outsideConsumes: true).union(paidMarkers[half] ?? [])
        guard markers.contains("persistent") || markers.contains("round") else { return }
        if !persistentCardsThisTurn.contains(cardId) { persistentCardsThisTurn.append(cardId) }
        if !markers.contains("persistent"), !roundCardsThisTurn.contains(cardId) { roundCardsThisTurn.append(cardId) }
        halfInPlayThisTurn[cardId] = playingTopHalf
    }

    /// Whether the half being played is a card's top half.
    private var playingTopHalf: Bool {
        switch phase {
        case .executeBottomAction: return false
        case .executeExtraHalf: return extraPlay?.top ?? true
        default: return true
        }
    }

    /// An element bonus was paid for: markers printed inside it now count for its card.
    private func notePaidConsume(_ consume: ActionModel) {
        guard let half = halfKey else { return }
        let inside = Self.markers(in: consume.subActions ?? [])
        guard !inside.isEmpty else { return }
        paidMarkers[half, default: []].formUnion(inside)
        noteCardInPlay()
    }

    private func grantExperience(_ xp: Int) {
        guard let character, xp > 0 else { return }
        character.experience += xp
        coordinator?.log("\(who) gains \(xp) XP", category: .info)
        coordinator?.teach(.experience)
    }

    /// Execute one action. Returns true if it waits for player input (and advances later).
    @discardableResult
    private func executeAction(_ action: ActionModel, coordinator: BoardCoordinator) -> Bool {
        var pieceID = PieceID.character(characterID)
        // A Command is performed by the bear; with the bear gone, it does nothing.
        commandedFigure = nil
        if isCommandHalf, let character {
            guard let bear = coordinator.companionPiece(of: character) else {
                if Self.isAbilityStep(action) {
                    coordinator.log("\(who)\u{2019}s Command does nothing: the bear is gone", category: .info)
                    abilityDidNothing()
                }
                return false
            }
            pieceID = bear
            commandedFigure = bear
        }
        // A turn step from a charged bonus marks its charge (Lumbering Bash's heal) — unless the
        // player has ended that bonus since the step was placed.
        if let cardId = Self.bonusCard(of: action), let character {
            guard coordinator.chargedBonuses(of: character).contains(where: { $0.cardId == cardId }) else {
                abilityDidNothing()
                return false
            }
            coordinator.useCharge(cardId, of: character)
        }
        // A persistent or round half's bonus applies once the half is being performed.
        if Self.isAbilityStep(action) { noteCardInPlay() }
        // Each Heal step is a Heal action of its own.
        performingHeal = action.type == .heal
        healActionCleanses = nil

        switch action.type {
        case .move, .jump, .fly:
            let bonus = consumeAugments(of: action)
            var moveValue = variableValue(action) ?? action.value?.intValue ?? 2
            var mode: MoveMode = action.type == .jump ? .jump : (action.type == .fly ? .fly : .normal)
            // Sinister Opportunity: "Force one adjacent enemy to perform Move 1" is printed inside
            // the move; that Move 1 is the enemy's, not added to the character's.
            let movesForSomeoneElse = customText(of: action).contains("perform")
            for effect in (action.subActions ?? []) + bonus {
                if effect.type == .jump { mode = .jump }
                if effect.type == .fly { mode = .fly }
                if effect.type == .move && !movesForSomeoneElse { moveValue += MonsterAbility.signedValue(effect) }
            }
            // Boots of Levitation, Cloak of Phasing: every move is a flight.
            if bonusesApply, PassiveItems.flies(character?.carriedItems ?? []) { mode = .fly }
            grantBonusExperience(bonus)
            hexesPassed = []
            // Rumbling Advance ("then all adjacent figures suffer 1 damage"), Swift Bow ("loot
            // every hex you enter"): text printed inside the move, done when it ends.
            afterMoveTexts = customTexts(of: action)
            // Feedback Loop: "If you end the movement in the same hex you started in, perform Muddle,
            // all enemies moved through" printed inside the move.
            movedThroughNeedsLoop = customText(of: action).contains("same hex you started in")
            moveStartHex = coordinator.boardState.piecePositions[pieceID]
            if (action.subActions ?? []).contains(where: {
                $0.type == .specialTarget && $0.value?.stringValue.lowercased() == "enemiesmovedthrough" }) {
                movedThroughConditions = (action.subActions ?? []).compactMap {
                    $0.type == .condition ? $0.value.flatMap { ConditionName(rawValue: $0.stringValue) } : nil
                }
            }
            let label = mode == .jump ? "Jump" : (mode == .fly ? "Fly" : "Move")
            coordinator.log("\(who): \(label) \(moveValue)", category: .move)
            applyPrintedEffects(of: action, coordinator: coordinator)
            coordinator.beginMoveAction(pieceID: pieceID, moveRange: moveValue, mode: mode)
            return true

        case .teleport:
            let teleportValue = action.value?.intValue ?? 2
            coordinator.log("\(who): Teleport \(teleportValue)", category: .move)
            coordinator.beginTeleportAction(pieceID: pieceID, range: teleportValue)
            return true

        case .attack:
            var range = 1
            var targetCount = 1
            var allTargets: String?
            resetPendingAttack(value: variableValue(action) ?? action.value?.intValue ?? 2, range: 1)
            // Element augments are paid only when the attack has a target (and can be made).
            // Inferno: "Target all enemies in the same room as you".
            let roomWide = customTexts(of: action).contains { $0.contains("all enemies in the same room") }
            let hasTarget = !coordinator.isConditionActive(.disarm, on: pieceID)
                && (roomWide ? !coordinator.enemiesInRoom(of: pieceID).isEmpty
                             : !coordinator.targetableEnemies(of: pieceID, range: attackRange(of: action)).isEmpty)
            let bonus = hasTarget ? consumeAugments(of: action) : []
            // A condition printed for the attacker itself (Energizing Strike: "Strengthen self"),
            // gained as the attack is made.
            var ownConditions: [ConditionName] = []
            for sub in (action.subActions ?? []) + bonus {
                switch sub.type {
                case .condition where hasSpecialTargetSelf(sub):
                    if let name = sub.value?.stringValue, let cond = ConditionName(rawValue: name) { ownConditions.append(cond) }
                case .attack: pendingAttackValue += MonsterAbility.signedValue(sub)
                case .range:
                    if let r = sub.value?.intValue {
                        range = sub.valueType == .add || sub.valueType == .plus ? range + r : r
                    }
                case .target: if let t = sub.value?.intValue { targetCount = max(targetCount, t) }
                case .pierce: if let p = sub.value?.intValue { pendingPierce += p }
                case .push: if let p = sub.value?.intValue { pendingPush += p }
                case .pull: if let p = sub.value?.intValue { pendingPull += p }
                case .condition:
                    if let name = sub.value?.stringValue, let cond = ConditionName(rawValue: name) {
                        pendingConditions.append(cond)
                    }
                case .area:
                    if let pattern = sub.value?.stringValue, !pattern.isEmpty { pendingAreaPattern = pattern }
                case .specialTarget:
                    allTargets = sub.value?.stringValue
                default: break
                }
            }
            attackTexts = customTexts(of: action)
            // Wild Command: "Target one Doomed enemy at any range."
            if attackTexts.contains(where: { $0.contains("doomed enemy at any range") }) { range = 99 }
            pendingAttackRange = range
            // This round's bonuses: Wall of Doom, Forceful Storm, an adjacent Enhancement Field.
            pendingAttackValue += coordinator.roundAttackBonus(for: pieceID, ranged: range > 1)
            // The character's own bonuses and items are theirs: not the bear's on a Command.
            if bonusesApply {
                // Grim Bargain's targets, taken just before this attack.
                targetCount += extraTargetsForNextAttack
                extraTargetsForNextAttack = 0
                // Eyes of the Night: advantage on every attack.
                if let character, coordinator.chargedBonuses(of: character).contains(where: { $0.bonus == .advantageAndSeeInvisible }) {
                    pendingAdvantage = true
                }
                // Mindthief augments shape every melee attack.
                if range <= 1 { applyAugments(coordinator: coordinator) }
            }
            // Bonuses counted in Attack actions — Backup Ammunition (one more target on a ranged
            // attack), Angelic Ascension, Grim Bargain's doubling — are counted in here, and their
            // charge is marked once the attack is made (`applyPerformedEffects`): an Attack
            // action that finds no target isn't one of "your next four".
            var actionCharges: [Int] = []
            if range > 1, let backup = coordinator.firstCharge(of: pieceID, where: { $0 == .extraTargetOnRanged }) {
                actionCharges.append(backup.cardId)
                targetCount += 1
                coordinator.log("\(who): one more target", category: .attack)
            }
            if let package = coordinator.firstCharge(of: pieceID, where: { if case .attackPackage = $0 { return true }; return false }),
               case .attackPackage(let bonus, let conditions, let advantage) = package.bonus {
                actionCharges.append(package.cardId)
                pendingAttackValue += bonus
                pendingConditions.append(contentsOf: conditions)
                pendingAdvantage = pendingAdvantage || advantage
            }
            // Crackling Air: "on your next four attacks" — what it adds is settled for the action
            // (Air consumed: +2), and a charge is marked with each attack then made, one for
            // every target (`attackValueWithBonuses`).
            // (Its Air was consumed, or not, as the card was played: FAQ.)
            if bonusesApply, let character, let crackling = coordinator.chargedBonuses(of: character).first(where: {
                if case .attackBonusOrElement = $0.bonus { return true }; return false }),
               case .attackBonusOrElement(let bonus, _, let upgraded) = crackling.bonus {
                bonusPerAttack = character.elementBonusesPaid.contains(crackling.cardId) ? upgraded : bonus
            }
            // Nature's Lift (+2 Range on a ranged attack), Foul Wind (+1 Attack): consume Air,
            // unless the player keeps it.
            if let game = gameManager?.game, let character, bonusesApply {
                for (index, entry) in elementConsumingBonuses(of: character, coordinator: coordinator).enumerated() {
                    let (element, _, needsRange) = entry.what
                    guard game.isElementAvailable(element), !needsRange || range > 1 else { continue }
                    if declinedConsume(Self.bonusConsumeIds + index) {
                        coordinator.log("\(who) keeps \(GameText.elementName(element)) (\(entry.name))", category: .element)
                        continue
                    }
                    guard let bonus = coordinator.chargedBonuses(of: character).first(where: { $0.cardId == entry.cardId })?.bonus else { continue }
                    _ = game.consumeElements([element])
                    switch bonus {
                    case .consumeForRange(_, let extra):
                        range += extra
                        coordinator.log("\(who) consumes \(GameText.elementName(element)): +\(extra) Range", category: .element)
                    case .consumeForAttack(_, let extra):
                        pendingAttackValue += extra
                        coordinator.log("\(who) consumes \(GameText.elementName(element)): +\(extra) Attack", category: .element)
                    default:
                        break
                    }
                    coordinator.useCharge(entry.cardId, of: character)
                }
                pendingAttackRange = range
            }
            // Voice of the Night ("on your next five attacks while invisible, add Stun") marks
            // its charges attack by attack too (`conditionsFromBonuses`).
            // Silent Stiletto: Pierce 1 on every melee attack.
            if range <= 1, bonusesApply {
                pendingPierce += PassiveItems.meleePierce(for: character?.carriedItems ?? [])
                pendingPush += PassiveItems.meleePush(for: character?.carriedItems ?? [])   // Mask of Terror
                if character?.health == 1, character?.carriedItems.contains(PassiveItems.maskOfDeath) == true {
                    pendingAttackValue += 2
                    coordinator.log("\(who)\u{2019}s Mask of Death: +2 Attack", category: .attack)
                }
                if !hornedHelmUsed, hexesMoved >= 4, character?.carriedItems.contains(PassiveItems.hornedHelm) == true {
                    hornedHelmUsed = true
                    pendingAttackValue += 1
                    coordinator.log("\(who)\u{2019}s Horned Helm: +1 Attack", category: .attack)
                }
            }
            // Grim Bargain's bottom: this round's next attack is doubled (after every other bonus).
            if let doubling = coordinator.firstCharge(of: pieceID, where: { $0 == .doubleNextAttack }) {
                actionCharges.append(doubling.cardId)
                pendingAttackValue *= 2
                coordinator.log("\(who)\u{2019}s attack is doubled", category: .attack)
            }
            // XP and infusions printed on the attack itself (e.g. Crushing Grasp's earth, Thief's
            // Knack's XP) and on paid augments come with performing it, which needs a target.
            func applyPerformedEffects() {
                grantBonusExperience(bonus)
                applyPrintedEffects(of: action, coordinator: coordinator)
                // (Once the attack is over: it isn't strengthened by its own Strengthen.)
                conditionsAfterAttack += ownConditions.map { (pieceID, $0) }
                if let character { for cardId in actionCharges { coordinator.useCharge(cardId, of: character) } }
            }

            if roomWide {
                coordinator.log("\(who): Attack \(pendingAttackValue) on every enemy in the room", category: .attack)
                if hasTarget { applyPerformedEffects() }
                let allyDamage = attackTexts.first { $0.contains("all allies in the same room") }.map(Self.damageAmount) ?? 0
                coordinator.attackAllEnemiesInRoom(from: pieceID, allyDamage: allyDamage)
                return true
            }
            if allTargets?.lowercased() == "enemiesmovedthrough" {
                coordinator.log("\(who): Attack \(pendingAttackValue) on every enemy moved through", category: .attack)
                if coordinator.hasEnemiesMovedThrough(by: pieceID, hexes: hexesPassed) { applyPerformedEffects() }
                coordinator.attackEnemiesMovedThrough(from: pieceID, hexes: hexesPassed)
                return true
            }
            // "Attack all adjacent enemies" / "all enemies within range N": every such enemy is
            // a separate attack of the same action.
            if let spec = allTargets?.lowercased(), spec.hasPrefix("enemiesadjacent") || spec.hasPrefix("enemiesrange") {
                let reach: Int = spec.hasPrefix("enemiesadjacent")
                    ? 1 : Int(spec.split(separator: ":").last ?? "") ?? range
                let exact = spec.hasPrefix("enemiesrangeexact")
                allTargetsAttacked = coordinator.enemiesToAttack(from: pieceID, within: reach, exactly: exact).count
                coordinator.log("\(who): Attack \(pendingAttackValue) on every enemy within \(reach)", category: .attack)
                if coordinator.hasEnemiesToAttack(from: pieceID, within: reach, exactly: exact) { applyPerformedEffects() }
                coordinator.attackAllEnemies(from: pieceID, within: reach, exactly: exact)
                return true
            }
            var extras: [String] = []
            if targetCount > 1 { extras.append("Target \(targetCount)") }
            if pendingPierce > 0 { extras.append("Pierce \(pendingPierce)") }
            if pendingPush > 0 { extras.append("Push \(pendingPush)") }
            if pendingPull > 0 { extras.append("Pull \(pendingPull)") }
            for cond in pendingConditions { extras.append(cond.rawValue.capitalized) }
            let extrasStr = extras.isEmpty ? "" : ", " + extras.joined(separator: ", ")
            coordinator.log("\(who): Attack \(pendingAttackValue), Range \(range)\(extrasStr)", category: .attack)
            // Halberd: a single-target melee attack reaches enemies 2 hexes away (still melee).
            let halberd = range <= 1 && targetCount == 1 && pendingAreaPattern == nil
                && character?.carriedItems.contains(PassiveItems.halberd) == true
            // XP and infusions printed on the attack come with making it, which needs a target.
            if coordinator.beginAttackAction(pieceID: pieceID, range: halberd ? 2 : range, targetCount: targetCount) {
                applyPerformedEffects()
            }
            return true

        case .heal:
            let bonus = consumeAugments(of: action)
            var healValue = action.value?.intValue ?? 0
            var range = 0
            var conditions: [ConditionName] = []
            for sub in (action.subActions ?? []) + bonus {
                if sub.type == .range, let r = sub.value?.intValue {
                    // "+1 Range" from an element adds to the printed range.
                    range = [.add, .addition, .plus].contains(sub.valueType) ? range + r : r
                }
                if sub.type == .heal { healValue += MonsterAbility.signedValue(sub) }
                if sub.type == .condition, let name = sub.value?.stringValue, let cond = ConditionName(rawValue: name) {
                    conditions.append(cond)
                }
            }
            grantBonusExperience(bonus)
            // Potent Potables: +2 on the next Heal actions — a charge for each one performed,
            // not for one with no one to heal.
            let potent = coordinator.firstCharge(of: pieceID, where: { if case .healBonus = $0 { return true }; return false })
            if case .healBonus(let extra)? = potent?.bonus { healValue += extra }
            func markHealCharge() {
                if let potent, let character { coordinator.useCharge(potent.cardId, of: character) }
            }
            // "All adjacent allies", "self and all allies", "one adjacent ally": who it heals.
            if let reach = allyReach(of: action, coordinator: coordinator, healing: true) {
                applyPrintedEffects(of: action, coordinator: coordinator)
                if reach.chooseOne {
                    guard !reach.pieces.isEmpty else {
                        coordinator.log("\(who) has no ally beside them to heal", category: .heal)
                        abilityDidNothing()
                        return false
                    }
                    coordinator.log("\(who): Heal \(healValue). Choose the ally", category: .heal)
                    markHealCharge()
                    coordinator.beginHealAction(pieceID: pieceID, healValue: healValue, range: 1, conditions: conditions)
                    if case .selectingHealTarget(let healer, let value, _) = coordinator.interactionMode {
                        coordinator.interactionMode = .selectingHealTarget(pieceID: healer, healValue: value, validTargets: Set(reach.pieces))
                    }
                    return true
                }
                if !reach.pieces.isEmpty { markHealCharge() }
                for figure in reach.pieces {
                    let healed = coordinator.heal(figure, amount: healValue, source: pieceID)
                    for cond in conditions { coordinator.applyCondition(cond, to: figure) }
                    coordinator.log(coordinator.healLine(pieceID, healed: figure, for: healed), category: .heal, trace: "Heal \(healValue)")
                }
                return false
            }
            if range > 0 {
                coordinator.log("\(who): Heal \(healValue), Range \(range). Choose who to heal", category: .heal)
                markHealCharge()
                applyPrintedEffects(of: action, coordinator: coordinator)
                coordinator.beginHealAction(pieceID: pieceID, healValue: healValue, range: range, conditions: conditions)
                return true
            }
            markHealCharge()
            let healed = coordinator.heal(pieceID, amount: healValue, source: pieceID)
            if !hasSpecialTargetSelf(action) {
                for cond in conditions { coordinator.applyCondition(cond, to: pieceID) }
            }
            coordinator.log("\(who) heals for \(healed)", category: .heal, trace: "Heal \(healValue), self")

        case .condition:
            guard let condName = action.value?.stringValue,
                  let cond = ConditionName(rawValue: condName) else { break }
            switch conditionTargetSpec(action) {
            case .singleEnemy(let range):
                let area = action.subActions?.first { $0.type == .area }?.value?.stringValue
                coordinator.beginConditionAction(pieceID: pieceID, condition: cond, range: range, area: area)
                coordinator.log("\(who): \(GameText.conditionName(cond)). Choose a target", category: .condition)
                return true
            case .allEnemies(let range):
                coordinator.applyConditionToAllEnemies(from: pieceID, condition: cond, range: range ?? 1)
                coordinator.log("\(who) applies \(GameText.conditionName(cond)) to every enemy within range \(range ?? 1)", category: .condition)
            case .allAllies(let range):
                coordinator.applyConditionToAllAllies(from: pieceID, condition: cond, range: range ?? 999)
                coordinator.log("\(who) applies \(GameText.conditionName(cond)) to every ally", category: .condition)
            case .selfAndAllAllies(let range):
                coordinator.applyCondition(cond, to: pieceID)
                coordinator.applyConditionToAllAllies(from: pieceID, condition: cond, range: range ?? 999)
            case .`self`:
                coordinator.applyCondition(cond, to: pieceID)
            case .enemiesMovedThrough:
                coordinator.applyCondition(cond, toEnemiesOn: hexesPassed, from: pieceID)
            case .enemiesBesideSummons:
                let summonHexes = (character?.summons ?? []).filter { !$0.dead }
                    .compactMap { coordinator.boardState.piecePositions[.summon(id: $0.id)] }
                coordinator.applyCondition(cond, toEnemiesOn: summonHexes.flatMap(coordinator.boardState.neighbors(of:)), from: pieceID)
            case .enemiesBesideEnemiesWith(let marker):
                let marked = coordinator.boardState.piecePositions
                    .filter { coordinator.areEnemies(pieceID, $0.key) && coordinator.isConditionActive(marker, on: $0.key) }
                coordinator.applyCondition(cond, toEnemiesOn: marked.values.flatMap(coordinator.boardState.neighbors(of:)), from: pieceID)
            case .everyoneElse:
                coordinator.applyConditionToAllEnemies(from: pieceID, condition: cond, range: 99)
                coordinator.applyConditionToAllAllies(from: pieceID, condition: cond, range: 99)
            case .singleAlly(let range):
                if coordinator.beginConditionAction(pieceID: pieceID, condition: cond, range: range, onAllies: true) {
                    coordinator.log("\(who): \(GameText.conditionName(cond)). Choose an ally", category: .condition)
                    return true
                }
            }

        case .shield, .retaliate:
            // "Shield 2, Retaliate 2 — affect all summoned allies" (Earthen Spikes, Patch Fur):
            // every summon on the party's side has them this round; the character doesn't.
            if customText(of: action).contains("all summoned allies"), let game = gameManager?.game {
                let bonuses = [action] + (action.subActions ?? []).filter { $0.type == .shield || $0.type == .retaliate }
                let summons = game.characters.filter { !$0.absent }.flatMap(\.summons)
                    .filter { !$0.dead && coordinator.isOnBoard(.summon(id: $0.id)) }
                for summon in summons {
                    for bonus in bonuses { Self.giveRoundBonus(bonus, to: summon) }
                }
                coordinator.log("\(who): \(GameText.list(bonuses.map(GameText.actionTitle))) to all summoned allies", category: .condition)
                if summons.isEmpty { abilityDidNothing() }
                break
            }
            // "Shield 1, self and all adjacent allies", "Retaliate 2, one adjacent ally"…
            if let reach = allyReach(of: action, coordinator: coordinator) {
                for figure in reach.chooseOne ? Array(reach.pieces.prefix(1)) : reach.pieces {
                    if figure == pieceID {
                        applyDefensiveBonus(action)
                    } else if case .character(let id) = figure, let ally = gameManager?.game.characters.first(where: { $0.id == id }) {
                        Self.giveRoundBonus(action, to: ally)
                        coordinator.log("\(coordinator.name(figure)): \(GameText.actionTitle(action))", category: .condition)
                    }
                }
                break
            }
            applyDefensiveBonus(action)
            // Unstable Upheaval: "Shield 2, affect all allies".
            if customText(of: action).contains("affect all allies"), let game = gameManager?.game {
                for ally in game.characters where ally.id != characterID && !ally.exhausted && !ally.absent {
                    let total = (ally.shield?.value?.intValue ?? 0) + (action.value?.intValue ?? 0)
                    ally.shield = ActionModel(type: .shield, value: .int(total))
                }
            }

        case .custom where action.value?.stringValue.hasPrefix("bonusChoice:curseAlly:") == true:
            return offerCurseForTargets(action, coordinator: coordinator)

        case .custom:
            payElementAsPlayed(action, coordinator: coordinator)
            return performPrintedText(action, coordinator: coordinator)

        case .experience:
            // Standalone XP comes with performing at least one of the half's abilities (FAQ).
            guard halfPerformed else { owe(action); break }
            grantExperience(action.value?.intValue ?? 1)

        case .loot:
            // Thief's Hood: Loot 1 becomes Loot 2.
            let lootRange = (action.value?.intValue ?? 1) + lootBonus
            lootBonus = 0
            coordinator.log("\(who): Loot \(lootRange)", category: .loot)
            // A Loot with nothing in range can't be performed (FAQ).
            if !coordinator.collectLootInRange(pieceID: pieceID, range: lootRange) { abilityDidNothing() }

        case .summon:
            // No empty hex beside the character: nothing is summoned (GH p.26).
            let placing = executeSummon(action, coordinator: coordinator)
            if !placing { abilityDidNothing() }
            return placing

        case .push, .pull:
            let steps = action.value?.intValue ?? 1
            let isPush = action.type == .push
            let spec = action.subActions?.first { $0.type == .specialTarget }?.value?.stringValue.lowercased()
            let rangeAction = action.subActions?.first { $0.type == .range }
            let targets = ((action.subActions ?? []) + (rangeAction?.subActions ?? [])).first { $0.type == .target }?.value?.intValue ?? 1
            coordinator.log("\(who): \(isPush ? "Push" : "Pull") \(steps)", category: .move)
            if spec?.hasPrefix("enemiesadjacent") == true {
                coordinator.forceMoveAllEnemies(from: pieceID, within: 1, steps: steps, isPush: isPush)
            } else {
                // One enemy, or as many as its Target says, within its range — an adjacent one
                // where no range is printed.
                coordinator.beginForcedMoveTarget(pieceID: pieceID, range: rangeAction?.value?.intValue ?? 1, steps: steps,
                                                  isPush: isPush, targets: targets)
            }
            return true

        case .suffer, .sufferDamage:
            let sufferValue = action.value?.intValue ?? 1
            coordinator.log("\(who) suffers \(sufferValue) damage", category: .damage)
            // Damage like any other: it may be negated by losing cards (GH p.22).
            return coordinator.sufferOwnDamage(sufferValue, characterID: characterID, source: currentCard?.name ?? "their own card") { [weak self] in
                self?.advanceAfterAsyncAction()
            }

        case .element:
            // A consume printed as its own step, with what it gives inside (Wretched Creature:
            // "consume Dark: Curse one adjacent enemy"): the reward happens if it's paid.
            let rewards = (action.subActions ?? []).filter { $0.type != .custom }
            if MonsterAbility.isConsume(action), !rewards.isEmpty, let game = gameManager?.game {
                guard let used = game.consumeElements(MonsterAbility.elements(of: action)) else {
                    abilityDidNothing()
                    break
                }
                coordinator.log("\(who) consumes \(GameText.list(used.map(GameText.elementName)))", category: .element)
                notePaidConsume(action)
                var waits = false
                for reward in Self.attachingTargets(rewards) where reward.type != .specialTarget {
                    if executeAction(reward, coordinator: coordinator) { waits = true; break }
                }
                return waits
            }
            // An infusion printed on its own comes with performing at least one of the half's
            // abilities (FAQ); a bare consume pays nothing for nothing.
            if !MonsterAbility.isConsume(action), !halfPerformed {
                owe(action)
                break
            }
            applyElementAction(action, coordinator: coordinator)

        case .refreshItem, .refreshSpent, .forceRefresh:
            coordinator.log("\(who) refreshes items", category: .info)

        case .removeNegativeConditions:
            character?.entityConditions.removeAll { $0.name.isNegative && !$0.permanent }
            coordinator.log("\(who) removes negative conditions", category: .condition)

        case .immune:
            if let condName = action.value?.stringValue, let cond = ConditionName(rawValue: condName),
               let character, !character.immunities.contains(cond) {
                character.immunities.append(cond)
                coordinator.log("\(who) becomes immune to \(GameText.conditionName(cond))", category: .condition)
            }

        case .box where Self.isAugment(action):
            // A Mindthief augment isn't performed: it shapes the character's melee attacks while
            // the card is active. Playing it discards any other augment, as the card says.
            retireOtherAugments(coordinator: coordinator)
            coordinator.log("\(who)\u{2019}s augment: on melee attacks, \(augmentSummary(action))", category: .round)

        case .box, .concatenation, .grid:
            for sub in action.subActions ?? [] {
                executeAction(sub, coordinator: coordinator)
            }

        case .card:
            // "experience:N" — XP for performing this half; persistent/round/lost markers are
            // handled when the card is put away.
            if let val = action.value?.stringValue, val.hasPrefix("experience:"),
               let xp = Int(val.dropFirst("experience:".count)) {
                // Not for an action none of whose abilities was performed (FAQ).
                guard halfPerformed else { owe(action); break }
                grantExperience(xp)
            }

        default:
            // Range/target/area modifiers belong to their parent action; text and custom
            // abilities are resolved by the players.
            break
        }

        // Infusions and XP printed inside an action happen when the action is performed (block
        // actions already ran their sub-actions, and attacks apply theirs once they have a
        // target); conditions on self-targeted actions apply to the character.
        if ![.element, .attack, .box, .concatenation, .grid].contains(action.type), !stepDidNothing {
            applyPrintedEffects(of: action, coordinator: coordinator)
        }
        if hasSpecialTargetSelf(action) && action.type != .condition {
            for sub in action.subActions ?? [] where sub.type == .condition {
                if let name = sub.value?.stringValue, let cond = ConditionName(rawValue: name) {
                    coordinator.applyCondition(cond, to: pieceID)
                }
            }
        }
        return false
    }

    /// Infusions and XP printed inside an action (Blind Destruction's earth, an element
    /// enhancement), which come with performing it.
    private func applyPrintedEffects(of action: ActionModel, coordinator: BoardCoordinator) {
        for sub in Self.attachedEffects(of: action) {
            if sub.type == .element {
                applyElementAction(sub, coordinator: coordinator)
            } else if let xp = Self.experience(in: sub) {
                grantExperience(xp)
            }
        }
    }

    /// The XP and infusions printed with an ability — beside it, grouped together beside it
    /// (Flamethrower's "XP 2, Fire"), or under the text or range that qualifies it (Explosive
    /// Punch, Kinetic Assault) — but not what an element bonus gives when paid for, nor what
    /// belongs to another ability printed inside it.
    static func attachedEffects(of action: ActionModel) -> [ActionModel] {
        let qualifiers: Set<ActionType> = [.concatenation, .grid, .custom, .range, .jump, .target, .specialTarget]
        return (action.subActions ?? []).flatMap { sub -> [ActionModel] in
            if MonsterAbility.isConsume(sub) { return [] }
            if sub.type == .element || experience(in: sub) != nil { return [sub] }
            return qualifiers.contains(sub.type) ? attachedEffects(of: sub) : []
        }
    }

    /// The player-facing text of an action's custom sub-actions, lowercased.
    /// The step's button: "Attack 3, Range 2", or for text the board performs, the card's own
    /// words ("Recover all of your lost cards", "All adjacent allies and enemies suffer 1
    /// damage") rather than "Special Effect"; an ability inside the text leads ("Move 4: …").
    func stepTitle(_ action: ActionModel) -> String {
        guard action.type == .custom || action.type == .special,
              let store = gameManager?.editionStore, let edition = character?.edition,
              let key = action.value?.stringValue, var text = store.resolveCustomText(key, edition: edition)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return GameText.actionTitle(action)
        }
        if text.hasSuffix(".") { text.removeLast() }
        func firstAbility(_ actions: [ActionModel]) -> ActionModel? {
            for sub in actions {
                if [.move, .attack, .heal, .loot, .jump].contains(sub.type) { return sub }
                if let found = firstAbility(sub.subActions ?? []) { return found }
            }
            return nil
        }
        if let ability = firstAbility(action.subActions ?? []) { text = "\(GameText.actionTitle(ability)): \(text)" }
        return text
    }

    private func customText(of action: ActionModel) -> String {
        customTexts(of: action).joined(separator: " ")
    }

    /// A text step's own words and those printed inside it, lowercased.
    private func customTextOfStep(_ step: ActionModel) -> String {
        let own = step.value.flatMap { value in
            gameManager?.editionStore.resolveCustomText(value.stringValue, edition: character?.edition ?? "gh") ?? value.stringValue
        } ?? ""
        return (own + " " + customText(of: step)).lowercased()
    }

    private func customTexts(of action: ActionModel) -> [String] {
        guard let store = gameManager?.editionStore, let edition = character?.edition else { return [] }
        return (action.subActions ?? []).filter { $0.type == .custom }
            .compactMap { $0.value?.stringValue }
            .compactMap { store.resolveCustomText($0, edition: edition) }
            .map { $0.lowercased() }
    }

    /// Who a heal, shield or retaliate printed for allies reaches ("alliesAdjacentAffect",
    /// "selfAlliesAffectRange:4", "allyAffectAdjacent"…), or nil when it's the character's own.
    private func allyReach(of action: ActionModel, coordinator: BoardCoordinator, healing: Bool = false) -> (pieces: [PieceID], chooseOne: Bool)? {
        guard let spec = action.subActions?.first(where: { $0.type == .specialTarget })?.value?.stringValue.lowercased(),
              spec != "self", spec.contains("all") else { return nil }
        let me = PieceID.character(characterID)
        let withSelf = spec.hasPrefix("self")
        let reach: Int = spec.contains("adjacent") ? 1
            : (spec.split(separator: ":").last.flatMap { Int($0.prefix(while: \.isNumber)) } ?? 99)
        let allies = coordinator.alliesInRange(of: me, range: reach, includeSelf: false, healing: healing).sorted()
        if spec.hasPrefix("ally") { return (allies, true) }   // one ally
        return ((withSelf ? [me] : []) + allies, false)
    }

    /// A round Shield or Retaliate for an ally (it stacks with theirs).
    private static func giveRoundBonus(_ action: ActionModel, to summon: GameSummon) {
        let value = action.value?.intValue ?? 0
        if action.type == .shield {
            summon.shield = ActionModel(type: .shield, value: .int((summon.shield?.value?.intValue ?? 0) + value))
        } else {
            summon.retaliate.append(ActionModel(type: .retaliate, value: .int(value)))
        }
    }

    private static func giveRoundBonus(_ action: ActionModel, to ally: GameCharacter) {
        let value = action.value?.intValue ?? 0
        if action.type == .shield {
            ally.shield = ActionModel(type: .shield, value: .int((ally.shield?.value?.intValue ?? 0) + value))
        } else {
            ally.retaliate.append(ActionModel(type: .retaliate, value: .int(value)))
        }
    }

    /// Range of an attack action before augments (melee = 1).
    /// How far the attack reaches: its printed range, or 2 for a single-target melee attack
    /// with the Halberd.
    private func attackRange(of action: ActionModel) -> Int {
        let subs = action.subActions ?? []
        let printed = subs.first { $0.type == .range }?.value?.intValue ?? 1
        let single = !subs.contains { $0.type == .area || ($0.type == .target && ($0.value?.intValue ?? 1) > 1) }
        if printed <= 1, single, character?.carriedItems.contains(PassiveItems.halberd) == true { return 2 }
        return printed
    }

    private func hasSpecialTargetSelf(_ action: ActionModel) -> Bool {
        action.subActions?.contains { $0.type == .specialTarget && $0.value?.stringValue == "self" } ?? false
    }

    /// Shield/Retaliate bonuses stack (GH p.24). A persistent bonus lasts while the card is in
    /// the active area; a round bonus until the end of the round.
    private func applyDefensiveBonus(_ action: ActionModel, forTheRound: Bool = false) {
        guard let character, let coordinator else { return }
        let value = action.value?.intValue ?? 0
        let persistent = !forTheRound && halfMarkers(for: phase).contains("persistent")
        if action.type == .shield {
            let existing = persistent ? character.shieldPersistent : character.shield
            let total = (existing?.value?.intValue ?? 0) + value
            let stacked = ActionModel(type: .shield, value: .int(total))
            if persistent { character.shieldPersistent = stacked } else { character.shield = stacked }
            coordinator.log("\(who): Shield \(value)", category: .condition)
        } else {
            var range = 1
            for sub in action.subActions ?? [] where sub.type == .range { range = sub.value?.intValue ?? 1 }
            let bonus = ActionModel(type: .retaliate, value: .int(value),
                                    subActions: range > 1 ? [ActionModel(type: .range, value: .int(range))] : nil)
            if persistent { character.retaliatePersistent.append(bonus) } else { character.retaliate.append(bonus) }
            coordinator.log("\(who): Retaliate \(value)\(range > 1 ? ", Range \(range)" : "")", category: .condition)
        }
    }

    // MARK: - Printed text

    /// A step that is only text: what the board can do from it (Reviving Ether, Thief's Knack,
    /// Crater's damage around the character, Proximity Mine's trap). Unknown text is left to the
    /// players. Returns true when it waits for the player (placing a trap).
    private func performPrintedText(_ action: ActionModel, coordinator: BoardCoordinator) -> Bool {
        guard let character else { return false }
        let me = PieceID.character(characterID)
        let own = action.value.flatMap { gameManager?.editionStore.resolveCustomText($0.stringValue, edition: character.edition)
            ?? $0.stringValue } ?? ""
        let text = (own + " " + customText(of: action)).lowercased()
        if text.contains("place your character token on"), let cardId = currentCard?.cardId {
            // A Doom: the character's token on one enemy, the card staying in play while it lasts.
            let options = coordinator.doomCandidates(for: character, normalOrEliteOnly: text.contains("normal or elite"))
            guard !options.isEmpty else {
                coordinator.log("\(who) has no enemy to Doom", category: .info)
                coordinator.endDoom(Doom(characterID: characterID, cardId: cardId), on: nil, reason: "no enemy to Doom")
                return false
            }
            let generation = coordinator.boardGeneration
            Task { @MainActor in
                let target = await coordinator.chooseFigure(options, title: currentCard?.name ?? "Doom",
                                                            question: "Which enemy does \(who) Doom?")
                guard coordinator.isCurrentBoard(generation) else { return }
                if let target { coordinator.placeDoom(cardId: cardId, by: character, on: target) }
                self.advanceAfterAsyncAction()
            }
            return true
        } else if text.contains("transfer all active") {
            // Lead to Slaughter: every doom to one enemy within range.
            let range = text.firstMatch(of: #/range (\d+)/#).flatMap { Int($0.1) } ?? 4
            let options = coordinator.targetableEnemies(of: me, range: range).sorted()
            guard coordinator.activeDooms.contains(where: { $0.doom.characterID == characterID }), !options.isEmpty else {
                coordinator.log("\(who) has no Doom to move, or no enemy within range \(range)", category: .info)
                return false
            }
            let generation = coordinator.boardGeneration
            Task { @MainActor in
                let target = await coordinator.chooseFigure(options, title: "Lead to Slaughter",
                                                            question: "Which enemy do the Dooms move to?")
                guard coordinator.isCurrentBoard(generation) else { return }
                if let target { coordinator.transferAllDooms(of: character, to: target) }
                self.advanceAfterAsyncAction()
            }
            return true
        } else if text.hasPrefix("target all enemies within"), text.contains("for each two enemies targeted") {
            // Darkened Skies: its targets were the attack's; the experience is for each two.
            let xp = (allTargetsAttacked / 2) * (text.firstMatch(of: #/xp \+?(\d+)/#).flatMap { Int($0.1) } ?? 1)
            if xp > 0 { grantExperience(xp) }
            return false
        } else if text.contains("when the trap is sprung"), !text.contains("trap in an adjacent empty hex") {
            // What a placed trap does when sprung (Flight of Flame's line): read as it is made.
            return false
        } else if Self.isDoomDescription(text, className: character.name) {
            // The Doomstalker's lines about a doom or doomed enemies describe what happens while
            // the card is in play (BoardCoordinator+Dooms); playing the half does nothing more.
            return false
        } else if text.contains("trap in an adjacent empty hex"), text.hasPrefix("create") || text.contains(" create") {
            // Proximity Mine: "Create one 6 damage trap…", "Gain XP +2 when the trap is sprung by
            // an enemy" (the next line of the half); Volatile Concoction: "2 damage Poison trap".
            let half = currentSteps
            let following = half.dropFirst(currentActionIndex + 1).first.map(customText(of:)) ?? ""
            let nextLine = half.dropFirst(currentActionIndex + 1).first.flatMap { $0.value }
                .flatMap { gameManager?.editionStore.resolveCustomText($0.stringValue, edition: character.edition) }?.lowercased() ?? following
            // What it does when sprung is printed with it, inside the step (Detonation) or as the
            // next line (Proximity Mine, Flight of Flame).
            let sprung = (customTexts(of: action) + [nextLine]).filter { $0.contains("trap is sprung") }
            let xp = sprung.lazy.compactMap { $0.firstMatch(of: #/xp \+(\d+)/#).flatMap { Int($0.1) } }.first ?? 0
            let around = TrapEffect.around(from: sprung)
            coordinator.trapAround = around.damage == nil && around.conditions.isEmpty ? nil : around
            let trap = PlacedToken.trap(damage: Self.damageAmount(in: text), subType: PlacedToken.trapCondition(in: text),
                                        experience: xp)
            return coordinator.beginPlacingTokens(trap, count: 1, by: me)
        } else if text.contains("destroy one adjacent obstacle") {
            // Rock Tunnel, Explosive Punch.
            return coordinator.beginPlacingTokens(.destroyObstacle, count: 1, by: me)
        } else if text.contains("obstacle") && text.contains("create") {
            // Avalanche: "Create two single-hex obstacles in empty hexes adjacent to you."
            let count = text.contains("two") ? 2 : 1
            return coordinator.beginPlacingTokens(.obstacle, count: count, by: me)
        } else if text.contains("perform") {
            let performed = (action.subActions ?? []).filter { [.attack, .move, .heal].contains($0.type) }
            let someoneElse = text.contains("ally") || text.contains("allies") || text.contains("enemy") || text.contains("enemies")
            if !someoneElse {
                // Growing Rage: "If you have fewer hit points than half your maximum hit point
                // value (rounded up), perform Attack…": the character's own, if the condition holds.
                let halfRoundedUp = (character.maxHealth + 1) / 2
                guard text.contains("fewer hit points than half"), let own = performed.first else {
                    coordinator.log("\(who): resolve this by hand", category: .info)
                    return false
                }
                guard character.health < halfRoundedUp else {
                    coordinator.log("\(who) isn't below half their hit points", category: .info)
                    abilityDidNothing()
                    return false
                }
                return executeAction(own, coordinator: coordinator)
            }
            // Possession ("One adjacent ally may perform Attack 6"), Parasitic Influence ("Force
            // one enemy within Range 4 to perform Move 1"), Submissive Affliction (a forced enemy
            // attacks another). Left to the players: several performers ("all allies", "two
            // summoned allies"), and several actions for one performer (Move, then Attack).
            let enemy = text.contains("enemy")
            guard performed.count == 1, let one = performed.first,
                  !text.contains("all "), !text.contains("two ") else {
                coordinator.log("\(who): resolve this by hand", category: .info)
                return false
            }
            let range = text.contains("adjacent") ? 1
                : text.contains("any one") ? 99
                : (text.firstMatch(of: #/range (\d+)/#).flatMap { Int($0.1) } ?? 1)
            return coordinator.beginChoosingPerformer(for: one, by: me, enemies: enemy, range: range,
                                                     summonsOnly: text.contains("summoned"))
        } else if text.contains("you may suffer up to") {
            // The Berserker: "You may suffer up to 4 damage", then "X is the amount you suffered".
            let most = Self.damageAmount(in: text)
            guard most > 0 else { return false }
            coordinator.pendingSufferChoice = BoardCoordinator.PendingSufferChoice(characterID: characterID, most: most)
            if coordinator.autoResolvePrompts { coordinator.resolveSufferChoice(0) }
            return true
        } else if text.contains("ally") && text.contains("recover") && text.contains("discarded") {
            // Reinvigorating Elixir ("one adjacent ally… all of their discarded cards"), Volatile
            // Concoction ("one ally within Range 2… one of their discarded cards"; consume Ice:
            // "up to two discarded cards instead").
            let range = text.contains("adjacent") ? 1 : (text.firstMatch(of: #/range (\d+)/#).flatMap { Int($0.1) } ?? 1)
            var count = text.contains("all of their discarded") ? Int.max : 1
            for sub in action.subActions ?? [] where MonsterAbility.isConsume(sub) {
                guard let game = gameManager?.game, let used = game.consumeElements(MonsterAbility.elements(of: sub)) else { continue }
                coordinator.log("\(who) consumes \(GameText.list(used.map(GameText.elementName)))", category: .element)
                if customText(of: sub).contains("up to two") { count = 2 }
            }
            let title = currentCard?.name ?? "Recover"
            coordinator.offerAllyRecovery(from: me, range: range, count: count, title: title)
        } else if text.contains("reduce your current hit point value to 1") {
            // Glass Hammer: "This is not considered damage."
            character.health = min(character.health, 1)
            coordinator.boardScene?.refreshStatus(of: me)
            coordinator.log("\(who) drops to 1 hit point", category: .info)
        } else if text.contains("all of your lost cards") && text.contains("recover") {
            let lost = character.lostCards
            character.handCards.append(contentsOf: lost)
            character.lostCards.removeAll()
            coordinator.log("\(who) recovers \(lost.count) lost card\(lost.count == 1 ? "" : "s")", category: .info)
        } else if text.contains("disarm one adjacent trap") {
            coordinator.disarmTrap(besides: me)
        } else if text.contains("suffer") && text.contains("damage") {
            var amount = Self.damageAmount(in: text)
            // "2 damage instead" when the element printed with it is consumed (Crater).
            for sub in action.subActions ?? [] where MonsterAbility.isConsume(sub) {
                guard let game = gameManager?.game, let used = game.consumeElements(MonsterAbility.elements(of: sub)) else { continue }
                coordinator.log("\(who) consumes \(GameText.list(used.map(GameText.elementName)))", category: .element)
                let instead = customText(of: sub) + " " + (sub.value.flatMap {
                    gameManager?.editionStore.resolveCustomText($0.stringValue, edition: character.edition) } ?? "").lowercased()
                if Self.damageAmount(in: instead) > 0 { amount = Self.damageAmount(in: instead) }
                if let xp = instead.firstMatch(of: #/xp \+(\d+)/#).flatMap({ Int($0.1) }) { grantExperience(xp) }
            }
            // Characters may negate it by losing cards: the turn waits for them.
            let generation = coordinator.boardGeneration
            Task { @MainActor in
                await coordinator.printedDamage(text, amount: amount, by: me, around: coordinator.boardState.piecePositions[me])
                guard coordinator.isCurrentBoard(generation) else { return }
                self.advanceAfterAsyncAction()
            }
            return true
        }
        return false
    }

    /// A Doomstalker line describing a doom's lasting effect, or a bonus against doomed enemies.
    static func isDoomDescription(_ text: String, className: String) -> Bool {
        guard className == "angry-face" else { return false }
        return text.contains("doom") || text.contains("this enemy") || text.contains("lose invisible")
    }

    /// "X" values the card defines in its text (Balanced Measure): hexes moved so far this
    /// turn, or damage inflicted so far this turn.
    private func variableValue(_ action: ActionModel) -> Int? {
        guard case .string(let printed)? = action.value, Int(printed) == nil, let character else { return nil }
        // "4+X": a printed base plus X.
        let base = printed.split(separator: "+").first.flatMap { Int($0) } ?? 0
        let text = customText(of: action)
        let x: Int
        if text.contains("hexes you have moved") {
            x = hexesMoved
        } else if text.contains("hexes you moved with this action") {
            x = lastMoveLength
        } else if text.contains("damage you have inflicted") {
            x = damageInflicted
        } else if text.contains("difference between your maximum hit point value and current hit point value") {
            x = max(0, character.maxHealth - character.health)
        } else if text.contains("number of cards you have lost") {
            x = character.lostCards.count
        } else if text.contains("your current hit point value") {
            x = character.health
        } else if text.contains("amount of damage you suffered") {
            x = damageSuffered
        } else if text.contains("number of all summoned allies") {
            x = (gameManager?.game.characters ?? []).flatMap(\.summons).filter { !$0.dead }.count
        } else {
            return nil
        }
        return base + x
    }

    /// The structured actions a short printed bonus names: conditions, "Push 2", "Pierce 1",
    /// "+1 Attack", "+1 Range", "XP +1", "target all enemies up to two hexes away".
    static func actions(fromText raw: String) -> [ActionModel] {
        let text = raw.lowercased()
        var result: [ActionModel] = []
        let words = Set(text.split(whereSeparator: { !$0.isLetter }).map(String.init))
        // Only true conditions: "shield", "heal", "push"… are values, not conditions to give.
        for condition in ConditionName.allCases
        where (condition.isNegative || condition.isPositive) && words.contains(condition.rawValue) {
            result.append(ActionModel(type: .condition, value: .string(condition.rawValue)))
        }
        for (type, pattern) in [(ActionType.push, #/push (\d+)/#), (.pull, #/pull (\d+)/#), (.pierce, #/pierce (\d+)/#)] {
            if let match = text.firstMatch(of: pattern), let n = Int(match.1) { result.append(ActionModel(type: type, value: .int(n))) }
        }
        if let match = text.firstMatch(of: #/\+(\d+) attack/#), let n = Int(match.1) {
            result.append(ActionModel(type: .attack, value: .int(n), valueType: .plus))
        }
        if let match = text.firstMatch(of: #/\+(\d+) range/#), let n = Int(match.1) {
            result.append(ActionModel(type: .range, value: .int(n), valueType: .add))
        }
        if let match = text.firstMatch(of: #/xp \+(\d+)/#), let n = Int(match.1) {
            result.append(ActionModel(type: .card, value: .string("experience:\(n)")))
        }
        let numbers = ["one": 1, "two": 2, "three": 3, "four": 4]
        if let match = text.firstMatch(of: #/all enemies up to (\w+)/#), let n = Int(match.1) ?? numbers[String(match.1)] {
            result.append(ActionModel(type: .specialTarget, value: .string("enemiesRange:\(n)")))
        }
        return result
    }

    static func damageAmount(in text: String) -> Int {
        text.firstMatch(of: #/(\d+) damage/#).flatMap { Int($0.1) } ?? 0
    }

    // MARK: - Mindthief augments

    static func isAugment(_ action: ActionModel) -> Bool {
        action.type == .box && action.value?.stringValue.contains(".augment%") == true
    }

    /// The effects an augment gives melee attacks (everything in its box but the "On your melee
    /// attacks:" heading and markers).
    private static func augmentEffects(_ box: ActionModel) -> [ActionModel] {
        func flatten(_ actions: [ActionModel]) -> [ActionModel] {
            actions.flatMap { $0.type == .grid ? flatten($0.subActions ?? []) : [$0] }
        }
        return flatten(box.subActions ?? []).filter { $0.type != .card }
    }

    /// The character's active augment cards: in the active area, or played this turn.
    private func activeAugments() -> [(cardId: Int, box: ActionModel)] {
        guard let character, let gameManager else { return [] }
        let deck = gameManager.characterManager.abilities(for: character)
        let ids = character.activeCards + persistentCardsThisTurn.filter { !character.activeCards.contains($0) }
        return ids.compactMap { id in
            guard !usedUpThisTurn.contains(id),
                  let box = deck.first(where: { $0.cardId == id })?.actions?.first(where: Self.isAugment) else { return nil }
            return (id, box)
        }
    }

    /// "When another augment is played, discard this card."
    private func retireOtherAugments(coordinator: BoardCoordinator) {
        guard let character, let playing = currentCard?.cardId else { return }
        for (id, _) in activeAugments() where id != playing {
            if character.activeCards.contains(id) {
                character.removeFromActiveArea(id)
            } else {
                usedUpThisTurn.insert(id)
            }
            coordinator.log("\(who) discards an earlier augment", category: .round)
        }
    }

    private func augmentSummary(_ box: ActionModel) -> String {
        let store = gameManager?.editionStore, edition = character?.edition ?? "gh"
        return Self.augmentEffects(box).compactMap { effect -> String? in
            if effect.type == .custom {
                let text = effect.value.flatMap { store?.resolveCustomText($0.stringValue, edition: edition) } ?? ""
                return text.lowercased().hasPrefix("on your melee attacks") ? nil : text
            }
            return GameText.actionTitle(effect)
        }.joined(separator: ", ")
    }

    /// Apply the active augments to the melee attack being made.
    private func applyAugments(coordinator: BoardCoordinator) {
        guard let character else { return }
        let me = PieceID.character(characterID)
        let store = gameManager?.editionStore
        // Psychic Knife: "any time you perform an Augment action, add +1 Attack to the entire action".
        if !activeAugments().isEmpty, character.carriedItems.contains(Self.psychicKnife) {
            pendingAttackValue += 1
        }
        for (_, box) in activeAugments() {
            for effect in Self.augmentEffects(box) {
                switch effect.type {
                case .custom:
                    let text = (effect.value.flatMap { store?.resolveCustomText($0.stringValue, edition: character.edition) } ?? "").lowercased()
                    if let match = text.firstMatch(of: #/\+(\d+) attack/#), let bonus = Int(match.1) {
                        pendingAttackValue += bonus   // The Mind's Weakness
                    } else if text.hasPrefix("gain"), let match = text.firstMatch(of: #/shield (\d+)/#), let amount = Int(match.1) {
                        applyDefensiveBonus(ActionModel(type: .shield, value: .int(amount)), forTheRound: true)   // Feedback Loop
                    } else if text.hasPrefix("gain") {
                        for sub in effect.subActions ?? [] where sub.type == .retaliate || sub.type == .shield {
                            applyDefensiveBonus(sub, forTheRound: true)   // Vicious Blood
                        }
                    }
                case .heal where (effect.subActions ?? []).contains(where: { $0.type == .specialTarget && $0.value?.stringValue == "self" }):
                    let amount = effect.value?.intValue ?? 0   // Parasitic Influence
                    let healed = coordinator.heal(me, amount: amount, source: me)
                    coordinator.log("\(who) heals for \(healed)", category: .heal, trace: "Heal \(amount), self")
                case .concatenation, .condition:
                    let conditions = effect.type == .condition ? [effect] : (effect.subActions ?? [])
                    for condition in conditions where condition.type == .condition {   // Withering Claw
                        if let cond = condition.value.flatMap({ ConditionName(rawValue: $0.stringValue) }) {
                            pendingConditions.append(cond)
                        }
                    }
                case .element:
                    // Frozen Mind: consume the element for what it adds.
                    let elements = MonsterAbility.elements(of: effect)
                    guard let game = gameManager?.game, let used = game.consumeElements(elements) else { continue }
                    coordinator.log("\(who) consumes \(GameText.list(used.map(GameText.elementName)))", category: .element)
                    for sub in effect.subActions ?? [] where sub.type == .condition {
                        if let cond = sub.value.flatMap({ ConditionName(rawValue: $0.stringValue) }) { pendingConditions.append(cond) }
                    }
                default:
                    continue
                }
            }
        }
    }

    // MARK: - Condition Target Helpers

    /// How a standalone condition action should be targeted.
    private enum ConditionTarget {
        case `self`
        case singleEnemy(range: Int)
        case allEnemies(range: Int?)
        case allAllies(range: Int?)
        case selfAndAllAllies(range: Int?)
        /// Every enemy passed over in this half's move (Rock Tunnel, Corrupting Embrace).
        case enemiesMovedThrough
        /// Every enemy next to one of the character's summons (Negative Energy).
        case enemiesBesideSummons
        /// Every enemy next to an enemy with the condition (Virulent Strain).
        case enemiesBesideEnemiesWith(ConditionName)
        /// Every other figure, enemy or ally (Mass Extinction).
        case everyoneElse
        /// One ally within range, the player choosing (Protective Blessing: "allyAffectRange:3").
        case singleAlly(range: Int)
    }

    /// A half as the steps the player performs one by one: groupings (concatenations, grids,
    /// boxes) and text that wraps printed actions (Crater's "suffer 1 damage" around its Move) are
    /// opened up, so a move or a target choice inside them is a step of its own and the turn
    /// waits for it. Augments stay whole: they aren't performed.
    static func steps(_ actions: [ActionModel], labels: EditionDataStore? = nil, edition: String = "gh") -> [ActionModel] {
        attachingTargetText(attachingModifierConsumes(attachingForcedMoveRange(attachingConditionArea(abilitiesUnderMovesAsSteps(
            flatSteps(actions, labels: labels, edition: edition)))).map(hoistingGroupedEffects)), labels: labels, edition: edition)
    }

    /// Darkened Skies: "Attack 3" and beside it the text "Target all enemies within Range 3. Gain
    /// XP 1 for each two enemies targeted" — the data has the text as a step of its own; its
    /// targets are the attack's (the text stays a step, for its experience).
    static func attachingTargetText(_ steps: [ActionModel], labels: EditionDataStore?, edition: String) -> [ActionModel] {
        var result = steps
        for index in result.indices.dropLast() where result[index].type == .attack {
            let next = result[index + 1]
            guard next.type == .custom, let key = next.value?.stringValue,
                  let text = labels?.resolveCustomText(key, edition: edition)?.lowercased(),
                  text.hasPrefix("target all enemies within"),
                  let reach = text.firstMatch(of: #/range (\d+)/#).flatMap({ Int($0.1) }),
                  !(result[index].subActions ?? []).contains(where: { $0.type == .specialTarget }) else { continue }
            result[index].subActions = (result[index].subActions ?? []) + [ActionModel(type: .specialTarget, value: .string("enemiesRange:\(reach)"))]
        }
        return result
    }

    /// A condition printed beside an area (Singing Arrow's "Curse, Range 3" and three red
    /// hexes): the data has the area as an action of its own, after a spacer; it is the
    /// condition's.
    static func attachingConditionArea(_ steps: [ActionModel]) -> [ActionModel] {
        var result: [ActionModel] = []
        for step in steps {
            if step.type == .area,
               let host = result.lastIndex(where: { $0.type != .concatenationSpacer }), result[host].type == .condition,
               !(result[host].subActions ?? []).contains(where: { $0.type == .area }) {
                result[host].subActions = (result[host].subActions ?? []) + [step]
            } else {
                result.append(step)
            }
        }
        return result
    }

    /// An ability printed under a Move — "Move 3" and below it "Curse, Range 3" (Tuning the
    /// Outcome), "Shield 2, affect all adjacent allies" (Warding Dagger), "Push 2, target all
    /// adjacent enemies" (Lash Out) — which the data has inside the Move: it is an ability of
    /// its own, performed after the Move. Not where the Move carries text or a target, which say
    /// what the nested ability is for (Feedback Loop, Sinister Opportunity, Hook and Chain).
    static func abilitiesUnderMovesAsSteps(_ steps: [ActionModel]) -> [ActionModel] {
        steps.flatMap { step -> [ActionModel] in
            guard step.type == .move, let subs = step.subActions,
                  !subs.contains(where: { $0.type == .custom || $0.type == .specialTarget }) else { return [step] }
            func isAbility(_ sub: ActionModel) -> Bool {
                [.condition, .shield, .retaliate, .push, .pull].contains(sub.type) && ![.add, .addition, .plus].contains(sub.valueType)
            }
            guard subs.contains(where: isAbility) else { return [step] }
            var move = step
            move.subActions = subs.filter { !isAbility($0) }
            return [move] + subs.filter(isAbility)
        }
    }

    /// A Push or Pull printed with its range on the line below it (Scroll of Recall's "Pull 1,
    /// Range 3, Target 3"): the data has that line as an action of its own, and it is the pull's.
    static func attachingForcedMoveRange(_ steps: [ActionModel]) -> [ActionModel] {
        var result: [ActionModel] = []
        for step in steps {
            if step.type == .range, var host = result.last, host.type == .push || host.type == .pull,
               !(host.subActions ?? []).contains(where: { $0.type == .range || $0.type == .specialTarget }) {
                host.subActions = (host.subActions ?? []) + [step]
                result[result.count - 1] = host
            } else {
                result.append(step)
            }
        }
        return result
    }

    /// What is printed in a group beside an ability and only qualifies it — XP, infusions and
    /// element bonuses (Flamethrower's "XP 2, Fire", Shaping the Ether's four bonuses in two
    /// rows) — belongs to the ability like what is printed singly.
    static func hoistingGroupedEffects(_ action: ActionModel) -> ActionModel {
        guard let subs = action.subActions, !isAugment(action) else { return action }
        func qualifies(_ sub: ActionModel) -> Bool {
            sub.type == .element || sub.type == .card || sub.type == .concatenationSpacer
        }
        var action = action
        action.subActions = subs.flatMap { sub -> [ActionModel] in
            guard sub.type == .concatenation || sub.type == .grid, !MonsterAbility.isConsume(sub),
                  let inner = sub.subActions, !inner.isEmpty, inner.allSatisfy(qualifies) else { return [sub] }
            return inner.filter { $0.type != .concatenationSpacer }
        }
        return action
    }

    /// A consume printed as its own step whose reward only modifies the action before it
    /// ("Heal 5, Range 3 / consume Air: +1 Heal, +1 Range"; an area for the attack before it)
    /// belongs to that action: it's paid and applied when that action is performed.
    private static func attachingModifierConsumes(_ steps: [ActionModel]) -> [ActionModel] {
        var result: [ActionModel] = []
        for step in steps {
            if MonsterAbility.isConsume(step), let host = modifiedType(by: step),
               let index = result.lastIndex(where: { $0.type == host }) {
                result[index].subActions = (result[index].subActions ?? []) + [step]
                continue
            }
            result.append(step)
        }
        return result
    }

    /// The one action type a consume's reward modifies, if all of it is a modifier.
    private static func modifiedType(by consume: ActionModel) -> ActionType? {
        func flatten(_ actions: [ActionModel]) -> [ActionModel] {
            actions.flatMap { $0.type == .concatenation ? flatten($0.subActions ?? []) : [$0] }
        }
        let rewards = flatten(consume.subActions ?? []).filter { $0.type != .card && $0.type != .custom }
        guard !rewards.isEmpty else { return nil }
        var hosts = Set<ActionType>()
        for reward in rewards {
            switch reward.type {
            case .area: hosts.insert(.attack)
            case .range: continue   // whichever action it goes with
            default:
                guard [.add, .addition, .plus].contains(reward.valueType) else { return nil }
                hosts.insert(reward.type)
            }
        }
        if hosts.isEmpty { return nil }
        return hosts.count == 1 ? hosts.first : nil
    }

    private static func flatSteps(_ actions: [ActionModel], labels: EditionDataStore?, edition: String) -> [ActionModel] {
        actions.flatMap { action -> [ActionModel] in
            switch action.type {
            case .concatenation, .grid:
                return flatSteps(action.subActions ?? [], labels: labels, edition: edition)
            case .box where !isAugment(action):
                return flatSteps(action.subActions ?? [], labels: labels, edition: edition)
            case .custom where (action.subActions ?? []).contains(where: { isWrapped($0) })
                && !performedBySomeoneElse(action, labels: labels, edition: edition):
                // The text stays a step (with the element it may consume, "2 damage instead");
                // the actions it wraps become steps of their own.
                var text = action
                text.subActions = (action.subActions ?? []).filter { !isWrapped($0) }
                return [text] + flatSteps((action.subActions ?? []).filter(isWrapped), labels: labels, edition: edition)
            default:
                return [action]
            }
        }
    }

    /// Text that hands its actions to another figure ("Force one enemy… to perform", "One
    /// adjacent ally may perform"): those actions aren't the character's to perform.
    static func performedBySomeoneElse(_ action: ActionModel, labels: EditionDataStore?, edition: String) -> Bool {
        guard let key = action.value?.stringValue else { return false }
        let text = (labels?.resolveCustomText(key, edition: edition) ?? key).lowercased()
        // Syringe: "Place this card in one adjacent ally's active area": its Shield is the ally's.
        return text.contains("perform") || key.contains("perform") || text.contains("ally's active area")
    }

    /// A printed action wrapped by text (not a marker, more text, or an element it consumes).
    private static func isWrapped(_ action: ActionModel) -> Bool {
        action.type != .card && action.type != .custom && !MonsterAbility.isConsume(action)
    }

    /// Cards that print a target beside their conditions rather than on them ("Immobilize and
    /// Push 1, one adjacent enemy"): the target is attached to each condition, so none of them
    /// falls back to the character.
    static func attachingTargets(_ actions: [ActionModel]) -> [ActionModel] {
        let target = actions.first { $0.type == .specialTarget }
        return actions.map { action in
            var action = action
            if action.type == .concatenation || action.type == .box || action.type == .grid {
                action.subActions = attachingTargets(action.subActions ?? [])
                if let target {
                    action.subActions = action.subActions?.map { attach(target, to: $0) }
                }
            } else if let target {
                action = attach(target, to: action)
            }
            return action
        }
    }

    private static func attach(_ target: ActionModel, to action: ActionModel) -> ActionModel {
        guard action.type == .condition,
              !(action.subActions ?? []).contains(where: { $0.type == .specialTarget || $0.type == .range }) else { return action }
        var action = action
        action.subActions = (action.subActions ?? []) + [target]
        return action
    }

    /// Parse the `specialTarget` subaction to determine how a condition should be targeted.
    private func conditionTargetSpec(_ action: ActionModel) -> ConditionTarget {
        guard let specValue = action.subActions?
            .first(where: { $0.type == .specialTarget })?.value?.stringValue else {
            // Some cards say who in their text only ("Target all enemies moved through").
            let text = customText(of: action)
            if text.contains("moved through") { return .enemiesMovedThrough }
            if text.contains("adjacent to any summoned ally") { return .enemiesBesideSummons }
            if text.contains("adjacent to all enemies with"),
               let condition = ConditionName.allCases.first(where: { text.contains("condition.\($0.rawValue)") || text.contains(" \($0.rawValue)") }) {
                return .enemiesBesideEnemiesWith(condition)
            }
            // A condition with a range targets one enemy in range; otherwise a positive one is the
            // character's own, and a negative one goes to an adjacent enemy (never the character).
            if let range = action.subActions?.first(where: { $0.type == .range })?.value?.intValue {
                return .singleEnemy(range: range)
            }
            if let name = action.value?.stringValue, ConditionName(rawValue: name)?.isNegative == true {
                return .singleEnemy(range: 1)
            }
            return .self
        }
        let lower = specValue.lowercased()

        func embeddedRange(_ prefix: String) -> Int? {
            guard lower.hasPrefix(prefix) else { return nil }
            let suffix = lower.dropFirst(prefix.count)
            return Int(suffix.trimmingCharacters(in: .init(charactersIn: ":")))
        }

        switch lower {
        case "self":
            return .self
        case "enemyadjacent":
            return .singleEnemy(range: 1)
        case "enemiesadjacent":
            return .allEnemies(range: 1)
        case "enemiesmovedthrough":
            return .enemiesMovedThrough
        case "enemies":
            return .allEnemies(range: nil)
        case "alliesenemies":
            return .everyoneElse
        case "allyadjacent", "allyaffectadjacent":
            return .singleAlly(range: 1)
        case "alliesadjacent", "alliesadjacentaffect":
            return .allAllies(range: 1)
        case "alliesaffect":
            return .allAllies(range: nil)
        case "selfalliesaffect", "selfalliesadjacentaffect":
            return .selfAndAllAllies(range: lower.contains("adjacent") ? 1 : nil)
        default:
            if let r = embeddedRange("enemiesrange:") { return .allEnemies(range: r) }
            if let r = embeddedRange("allyaffectrange:") { return .singleAlly(range: r) }
            if let r = embeddedRange("selfalliesaffectrange:") { return .selfAndAllAllies(range: r) }
            if let r = embeddedRange("alliesrangeaffect:") { return .allAllies(range: r) }
            if lower.contains("enemy") || lower.contains("enemies") { return .singleEnemy(range: 1) }
            if lower.contains("allie") || lower.contains("ally") { return .allAllies(range: 1) }
            return .self
        }
    }

    /// Execute a summon action: create the summon and enter interactive placement mode.
    /// Returns true when waiting for the player to place it.
    private func executeSummon(_ action: ActionModel, coordinator: BoardCoordinator) -> Bool {
        guard let gameManager = gameManager, let character else { return false }

        let summonName = action.summonValueObject?.name ?? action.value?.stringValue
        guard let summonName else {
            coordinator.log("\(who)\u{2019}s summon could not be found", category: .info, trace: "no summon name")
            return false
        }

        var summonData: SummonDataModel
        if let found = character.characterData?.availableSummons?.first(where: { $0.name == summonName }) {
            summonData = found
            // The card's own stats, with its enhancements (`CardEnhancing.apply`).
            if let printed = action.summonValueObject {
                summonData.health = printed.health
                if let attack = printed.attack { summonData.attack = attack }
                if let movement = printed.movement { summonData.movement = movement }
                if let range = printed.range { summonData.range = range }
            }
        } else if let embedded = action.summonValueObject {
            summonData = embedded.toSummonData()
        } else {
            coordinator.log("\(who)\u{2019}s summon could not be found", category: .info, trace: summonName)
            return false
        }

        return coordinator.beginSummonPlacement(summonData, for: character)
    }

    /// Infuse or consume an element based on the action's valueType.
    private func applyElementAction(_ action: ActionModel, coordinator: BoardCoordinator) {
        guard let game = gameManager?.game else { return }
        let elements = MonsterAbility.elements(of: action)
        guard !elements.isEmpty else { return }
        if MonsterAbility.isConsume(action) {
            if let used = game.consumeElements(elements) {
                coordinator.log("\(who) consumes \(GameText.list(used.map(GameText.elementName)))", category: .element)
            }
        } else {
            // Becomes strong at the end of this turn (it can't be consumed by this turn's actions).
            for element in elements where element != .wild {
                game.infuseElement(element)
                coordinator.log("\(who) infuses \(GameText.elementName(element))", category: .element)
            }
            // "Infuse any element" (Chromatic Explosion, an any-element enhancement): the player picks.
            let wild = elements.filter { $0 == .wild }.count
            if wild > 0 {
                coordinator.pendingElementChoice = BoardCoordinator.PendingElementChoice(
                    characterID: characterID, count: wild, itemName: "Any Element")
            }
        }
    }

    // MARK: - Putting cards away

    /// "card" markers (persistent / round / lost) printed on a half, at any nesting depth.
    private func halfMarkers(for phase: PlayerTurnPhase) -> Set<String> {
        let actions: [ActionModel]
        switch phase {
        case .executeBottomAction: actions = bottomActions
        case .executeExtraHalf: actions = extraActions
        default: actions = topActions
        }
        return Self.markers(in: actions)
    }

    /// With `outsideConsumes`, markers printed inside an element bonus are left out: they count
    /// only when the bonus is paid for.
    static func markers(in actions: [ActionModel], outsideConsumes: Bool = false) -> Set<String> {
        var result = Set<String>()
        for action in actions where !(outsideConsumes && MonsterAbility.isConsume(action)) {
            if action.type == .card, let value = action.value?.stringValue, !value.contains(":") {
                result.insert(value)
            }
            result.formUnion(markers(in: action.subActions ?? [], outsideConsumes: outsideConsumes))
        }
        return result
    }

    /// Put both played cards away (GH p.16): a card played for a default action, or whose half was
    /// skipped whole, is discarded; otherwise an active bonus (persistent or round) goes to the
    /// active area, a half with the lost icon goes to the lost pile, and the rest are discarded.
    private func finishTurn() {
        guard let character, !character.exhausted else { return }
        putAway(topCard, half: topActions, lostFlag: topCard?.lost == true, usedAsDefault: topUsedAsDefault,
                key: "top", top: true, character: character)
        putAway(bottomCard, half: bottomActions, lostFlag: bottomCard?.bottomLost == true,
                usedAsDefault: bottomUsedAsDefault, key: "bottom", top: false, character: character)
        coordinator?.log("\(who) ends the turn", category: .round)
    }

    private func putAway(_ card: AbilityModel?, half: [ActionModel], lostFlag: Bool, usedAsDefault: Bool,
                         key: String, top: Bool, character: GameCharacter) {
        guard let cardId = card?.cardId, let index = character.handCards.firstIndex(of: cardId) else { return }
        character.handCards.remove(at: index)

        // A basic action, or a half none of whose abilities was performed: discarded (FAQ: a
        // card is lost only if an ability printed on that action was performed).
        let skippedWhole = !performedHalves.contains(key) && half.contains { Self.bonusCard(of: $0) == nil }
        if usedAsDefault || skippedWhole {
            character.discardedCards.append(cardId)
            return
        }
        // Markers inside an element bonus count only if it was paid for.
        let markers = Self.markers(in: half, outsideConsumes: true).union(paidMarkers[key] ?? [])
        let lost = lostFlag || markers.contains("lost")
        if usedUpThisTurn.contains(cardId) {
            // Its charges ran out during this turn: it goes straight where it would end up.
            if lost { character.lostCards.append(cardId) } else { character.discardedCards.append(cardId) }
            if lost { coordinator?.boardScene?.play(.lose) }
        } else if markers.contains("persistent") || markers.contains("round") {
            character.activeCards.append(cardId)
            if markers.contains("round") && !markers.contains("persistent") {
                character.roundBonusCards.append(cardId)
            }
            if !top { character.bottomHalvesInPlay.append(cardId) }
            if lost { character.lostWhenRemoved.append(cardId) }
        } else if lost {
            character.lostCards.append(cardId)
            coordinator?.boardScene?.play(.lose)
        } else {
            character.discardedCards.append(cardId)
        }
    }
}
