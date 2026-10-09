import Foundation

/// State machine for a player's turn.
enum PlayerTurnPhase {
    case selectTopCard
    case executeTopAction
    case executeBottomAction
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

    /// Perform the bottom half before the top half.
    private(set) var bottomFirst: Bool = false
    /// Whether any action has been performed yet (cards can only be rearranged before that).
    private(set) var hasActed: Bool = false
    /// Halves played as the default Attack 2 / Move 2 — such cards always go to the discard pile.
    private(set) var topUsedAsDefault = false
    private(set) var bottomUsedAsDefault = false
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
    /// Damage the character chose to suffer this turn (Flurry of Axes' X).
    var damageSuffered = 0
    /// Hexes moved by the latest move action (Hook and Chain).
    var lastMoveLength = 0
    /// Hexes passed over (not ended on) during the latest move action, for "enemies moved through".
    var hexesPassed: [HexCoord] = []
    /// Cards whose persistent half was performed this turn: their charged bonus is in effect
    /// before they reach the active area. A bonus used up this turn never gets there.
    var persistentCardsThisTurn: [Int] = []
    /// Conditions the current move gives every enemy it passes over (Feedback Loop).
    var movedThroughConditions: [ConditionName] = []
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
        // Enhancements bought in town are part of the card (GH p.42).
        let enhancements = character?.enhancements ?? []
        let labels = gameManager?.editionStore, edition = character?.edition ?? "gh"
        self.topActions = Self.steps(Self.attachingTargets(
            CardEnhancing.apply(enhancements, to: top.actions ?? [], cardId: top.cardId, half: "top")), labels: labels, edition: edition)
        self.bottomActions = Self.steps(Self.attachingTargets(
            CardEnhancing.apply(enhancements, to: bottom.bottomActions ?? [], cardId: bottom.cardId, half: "bottom")), labels: labels, edition: edition)
        self.phase = bottomFirst ? .executeBottomAction : .executeTopAction
        self.currentActionIndex = 0
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

        let actions: [ActionModel]
        switch phase {
        case .executeTopAction: actions = topActions
        case .executeBottomAction: actions = bottomActions
        default: return
        }

        guard currentActionIndex < actions.count else {
            advancePhase()
            return
        }

        hasActed = true
        let action = actions[currentActionIndex]
        // Async actions (target/hex selection) advance in advanceAfterAsyncAction() — which may
        // already have happened synchronously (e.g. an attack with no valid target).
        awaitingAsync = true
        let isAsync = executeAction(action, coordinator: coordinator)
        if !isAsync {
            awaitingAsync = false
            currentActionIndex += 1
        }
    }

    /// Advance the action index after an async action (attack/summon/condition/heal) resolves.
    func advanceAfterAsyncAction() {
        if defaultAttackPending {
            defaultAttackPending = false
            awaitingAsync = false
            advancePhase()
            return
        }
        guard awaitingAsync else { return }
        awaitingAsync = false
        currentActionIndex += 1
    }

    /// Skip remaining actions in the current phase. A pending target/hex selection is
    /// cancelled; an attack that is already resolving must finish first.
    func skipRemainingActions() {
        guard let coordinator else { return }
        if defaultAttackPending || awaitingAsync {
            switch coordinator.interactionMode {
            case .idle, .watchingMonsterTurn, .selectingPushPullHex:
                return
            default:
                coordinator.interactionMode = .idle
                coordinator.boardScene?.clearHighlights()
                defaultAttackPending = false
                awaitingAsync = false
            }
        }
        advancePhase()
    }

    /// Skip just the current ability of this half (any ability may be skipped, GH p.16) and go
    /// on to the next one. A pending target or hex selection for it is cancelled; an attack that
    /// is already resolving must finish first.
    func skipCurrentAction() {
        guard let coordinator else { return }
        if defaultAttackPending {
            skipRemainingActions()
            return
        }
        if awaitingAsync {
            switch coordinator.interactionMode {
            case .idle, .watchingMonsterTurn, .selectingPushPullHex:
                return
            default:
                coordinator.interactionMode = .idle
                coordinator.boardScene?.clearHighlights()
                awaitingAsync = false
            }
        }
        let count = phase == .executeTopAction ? topActions.count : bottomActions.count
        guard phase == .executeTopAction || phase == .executeBottomAction else { return }
        hasActed = true
        if currentActionIndex + 1 < count {
            currentActionIndex += 1
        } else {
            advancePhase()
        }
    }

    /// Use the default action for the current half instead of the printed one:
    /// Attack 2 on the top half, Move 2 on the bottom half.
    func useDefaultAction() {
        guard let coordinator = coordinator, !hasActed || currentActionIndex == 0, !defaultAttackPending else { return }
        if character?.exhausted ?? true {
            endForExhaustion()
            return
        }
        hasActed = true

        let pieceID = PieceID.character(characterID)
        guard !awaitingAsync else { return }
        switch phase {
        case .executeTopAction:
            // Versatile Dagger, Balanced Blade: a stronger basic attack.
            let value = PassiveItems.defaultAttack(for: character?.items ?? [])
            topUsedAsDefault = true
            resetPendingAttack(value: value, range: 1)
            pendingPierce += PassiveItems.meleePierce(for: character?.items ?? [])
            pendingPush += PassiveItems.meleePush(for: character?.items ?? [])
            pendingAttackValue += coordinator.roundAttackBonus(for: pieceID, ranged: false)
            defaultAttackPending = true
            coordinator.log("\(who) uses the basic Attack \(value)", category: .attack)
            coordinator.beginAttackAction(pieceID: pieceID, range: 1)
        case .executeBottomAction:
            // Comfortable Shoes, Serene Sandals: a longer basic move.
            let value = PassiveItems.defaultMove(for: character?.items ?? [])
            bottomUsedAsDefault = true
            defaultAttackPending = true // ends the half once the move resolves
            coordinator.log("\(who) uses the basic Move \(value)", category: .move)
            coordinator.beginMoveAction(pieceID: pieceID, moveRange: value,
                                        mode: PassiveItems.flies(character?.items ?? []) ? .fly : .normal)
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

    // MARK: - Queries

    /// The attack value of the attack currently being resolved.
    func currentAttackValue() -> Int { pendingAttackValue }

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
        default:
            break
        }
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
    }

    /// Pay for every element-consume augment on the action that can be paid for and return
    /// their bonus effects (GH p.24: all listed elements are needed for one augment).
    private func consumeAugments(of action: ActionModel) -> [ActionModel] {
        guard let game = gameManager?.game else { return [] }
        var bonus: [ActionModel] = []
        for sub in action.subActions ?? [] where MonsterAbility.isConsume(sub) {
            let elements = MonsterAbility.elements(of: sub)
            guard let used = game.consumeElements(elements) else { continue }
            coordinator?.log("\(who) consumes \(GameText.list(used.map(GameText.elementName)))", category: .element)
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

    private func grantExperience(_ xp: Int) {
        guard let character, xp > 0 else { return }
        character.experience += xp
        coordinator?.log("\(who) gains \(xp) XP", category: .info)
    }

    /// Execute one action. Returns true if it waits for player input (and advances later).
    @discardableResult
    private func executeAction(_ action: ActionModel, coordinator: BoardCoordinator) -> Bool {
        let pieceID = PieceID.character(characterID)
        // A persistent or round half's bonus applies once the half is being performed.
        let markers = halfMarkers(for: phase)
        if markers.contains("persistent") || markers.contains("round"),
           let cardId = (phase == .executeBottomAction ? bottomCard : topCard)?.cardId,
           !persistentCardsThisTurn.contains(cardId) {
            persistentCardsThisTurn.append(cardId)
        }

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
            if PassiveItems.flies(character?.items ?? []) { mode = .fly }
            grantBonusExperience(bonus)
            hexesPassed = []
            // Rumbling Advance ("then all adjacent figures suffer 1 damage"), Swift Bow ("loot
            // every hex you enter"): text printed inside the move, done when it ends.
            afterMoveTexts = customTexts(of: action)
            // Feedback Loop: "Muddle, all enemies moved through" printed inside the move.
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
            // Element augments are paid only when the attack has a target.
            let hasTarget = !coordinator.targetableEnemies(of: pieceID, range: attackRange(of: action)).isEmpty
            let bonus = hasTarget ? consumeAugments(of: action) : []
            for sub in (action.subActions ?? []) + bonus {
                switch sub.type {
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
            pendingAttackRange = range
            attackTexts = customTexts(of: action)
            // This round's bonuses: Wall of Doom, Forceful Storm, an adjacent Enhancement Field.
            pendingAttackValue += coordinator.roundAttackBonus(for: pieceID, ranged: range > 1)
            // Mindthief augments shape every melee attack.
            if range <= 1 { applyAugments(coordinator: coordinator) }
            // Charged bonuses: Backup Ammunition (one more target on a ranged attack), Crackling Air.
            if range > 1, coordinator.useFirstCharge(of: pieceID, where: { $0 == .extraTargetOnRanged }) != nil {
                targetCount += 1
                coordinator.log("\(who): one more target", category: .attack)
            }
            if case .attackPackage(let bonus, let conditions, let advantage)? = coordinator.useFirstCharge(of: pieceID, where: {
                if case .attackPackage = $0 { return true }; return false }) {
                pendingAttackValue += bonus
                pendingConditions.append(contentsOf: conditions)
                pendingAdvantage = pendingAdvantage || advantage
            }
            if coordinator.isConditionActive(.invisible, on: pieceID),
               case .conditionWhileInvisible(let condition)? = coordinator.useFirstCharge(of: pieceID, where: {
                   if case .conditionWhileInvisible = $0 { return true }; return false }) {
                pendingConditions.append(condition)
            }
            // Silent Stiletto: Pierce 1 on every melee attack.
            if range <= 1 {
                pendingPierce += PassiveItems.meleePierce(for: character?.items ?? [])
                pendingPush += PassiveItems.meleePush(for: character?.items ?? [])   // Mask of Terror
                if character?.health == 1, character?.items.contains(PassiveItems.maskOfDeath) == true {
                    pendingAttackValue += 2
                    coordinator.log("\(who)\u{2019}s Mask of Death: +2 Attack", category: .attack)
                }
                if !hornedHelmUsed, hexesMoved >= 4, character?.items.contains(PassiveItems.hornedHelm) == true {
                    hornedHelmUsed = true
                    pendingAttackValue += 1
                    coordinator.log("\(who)\u{2019}s Horned Helm: +1 Attack", category: .attack)
                }
            }
            // XP and infusions printed on the attack itself (e.g. Crushing Grasp's earth, Thief's
            // Knack's XP) and on paid augments come with performing it, which needs a target.
            func applyPerformedEffects() {
                guard hasTarget else { return }
                grantBonusExperience(bonus)
                for sub in action.subActions ?? [] {
                    if sub.type == .element && !MonsterAbility.isConsume(sub) {
                        applyElementAction(sub, coordinator: coordinator)
                    } else if let xp = Self.experience(in: sub) {
                        grantExperience(xp)
                    }
                }
            }

            if allTargets?.lowercased() == "enemiesmovedthrough" {
                coordinator.log("\(who): Attack \(pendingAttackValue) on every enemy moved through", category: .attack)
                applyPerformedEffects()
                coordinator.attackEnemiesMovedThrough(from: pieceID, hexes: hexesPassed)
                return true
            }
            // "Attack all adjacent enemies" / "all enemies within range N": every such enemy is
            // a separate attack of the same action.
            if let spec = allTargets?.lowercased(), spec.hasPrefix("enemiesadjacent") || spec.hasPrefix("enemiesrange") {
                let reach: Int = spec.hasPrefix("enemiesadjacent")
                    ? 1 : Int(spec.split(separator: ":").last ?? "") ?? range
                let exact = spec.hasPrefix("enemiesrangeexact")
                coordinator.log("\(who): Attack \(pendingAttackValue) on every enemy within \(reach)", category: .attack)
                applyPerformedEffects()
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
            applyPerformedEffects()
            // Halberd: a single-target melee attack reaches enemies 2 hexes away (still melee).
            let halberd = range <= 1 && targetCount == 1 && pendingAreaPattern == nil
                && character?.items.contains(PassiveItems.halberd) == true
            coordinator.beginAttackAction(pieceID: pieceID, range: halberd ? 2 : range, targetCount: targetCount)
            return true

        case .heal:
            let bonus = consumeAugments(of: action)
            var healValue = action.value?.intValue ?? 0
            var range = 0
            var conditions: [ConditionName] = []
            for sub in (action.subActions ?? []) + bonus {
                if sub.type == .range, let r = sub.value?.intValue { range = r }
                if sub.type == .heal { healValue += MonsterAbility.signedValue(sub) }
                if sub.type == .condition, let name = sub.value?.stringValue, let cond = ConditionName(rawValue: name) {
                    conditions.append(cond)
                }
            }
            grantBonusExperience(bonus)
            // Potent Potables: +2 on the next heal actions.
            if case .healBonus(let extra)? = coordinator.useFirstCharge(of: pieceID, where: {
                if case .healBonus = $0 { return true }; return false }) {
                healValue += extra
            }
            if range > 0 {
                coordinator.log("\(who): Heal \(healValue), Range \(range). Choose who to heal", category: .heal)
                applyPrintedEffects(of: action, coordinator: coordinator)
                coordinator.beginHealAction(pieceID: pieceID, healValue: healValue, range: range, conditions: conditions)
                return true
            }
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
                coordinator.beginConditionAction(pieceID: pieceID, condition: cond, range: range)
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
                coordinator.applyCondition(cond, toEnemiesOn: summonHexes.flatMap(\.neighbors), from: pieceID)
            case .enemiesBesideEnemiesWith(let marker):
                let marked = coordinator.boardState.piecePositions
                    .filter { coordinator.areEnemies(pieceID, $0.key) && coordinator.isConditionActive(marker, on: $0.key) }
                coordinator.applyCondition(cond, toEnemiesOn: marked.values.flatMap(\.neighbors), from: pieceID)
            case .everyoneElse:
                coordinator.applyConditionToAllEnemies(from: pieceID, condition: cond, range: 99)
                coordinator.applyConditionToAllAllies(from: pieceID, condition: cond, range: 99)
            }

        case .shield, .retaliate:
            applyDefensiveBonus(action)
            // Unstable Upheaval: "Shield 2, affect all allies".
            if customText(of: action).contains("affect all allies"), let game = gameManager?.game {
                for ally in game.characters where ally.id != characterID && !ally.exhausted && !ally.absent {
                    let total = (ally.shield?.value?.intValue ?? 0) + (action.value?.intValue ?? 0)
                    ally.shield = ActionModel(type: .shield, value: .int(total))
                }
            }

        case .custom:
            return performPrintedText(action, coordinator: coordinator)

        case .experience:
            grantExperience(action.value?.intValue ?? 1)

        case .loot:
            let lootRange = action.value?.intValue ?? 1
            coordinator.log("\(who): Loot \(lootRange)", category: .loot)
            coordinator.collectLootInRange(pieceID: pieceID, range: lootRange)

        case .summon:
            return executeSummon(action, coordinator: coordinator)

        case .push, .pull:
            let steps = action.value?.intValue ?? 1
            let isPush = action.type == .push
            let spec = action.subActions?.first { $0.type == .specialTarget }?.value?.stringValue.lowercased()
            let range = action.subActions?.first { $0.type == .range }?.value?.intValue
            coordinator.log("\(who): \(isPush ? "Push" : "Pull") \(steps)", category: .move)
            if spec?.hasPrefix("enemiesadjacent") == true {
                coordinator.forceMoveAllEnemies(from: pieceID, within: 1, steps: steps, isPush: isPush)
            } else if spec?.hasPrefix("enemyadjacent") == true || range != nil {
                coordinator.beginForcedMoveTarget(pieceID: pieceID, range: range ?? 1, steps: steps, isPush: isPush)
            } else {
                coordinator.beginStandalonePushPull(steps: steps, isPush: isPush)
            }
            return true

        case .suffer, .sufferDamage:
            let sufferValue = action.value?.intValue ?? 1
            coordinator.log("\(who) suffers \(sufferValue) damage", category: .damage)
            coordinator.sufferDamage(sufferValue, to: pieceID)

        case .element:
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
        if ![.element, .attack, .box, .concatenation, .grid].contains(action.type) {
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
        for sub in action.subActions ?? [] {
            if sub.type == .element && !MonsterAbility.isConsume(sub) {
                applyElementAction(sub, coordinator: coordinator)
            } else if let xp = Self.experience(in: sub) {
                grantExperience(xp)
            }
        }
    }

    /// The player-facing text of an action's custom sub-actions, lowercased.
    private func customText(of action: ActionModel) -> String {
        customTexts(of: action).joined(separator: " ")
    }

    private func customTexts(of action: ActionModel) -> [String] {
        guard let store = gameManager?.editionStore, let edition = character?.edition else { return [] }
        return (action.subActions ?? []).filter { $0.type == .custom }
            .compactMap { $0.value?.stringValue }
            .compactMap { store.resolveCustomText($0, edition: edition) }
            .map { $0.lowercased() }
    }

    /// Range of an attack action before augments (melee = 1).
    private func attackRange(of action: ActionModel) -> Int {
        action.subActions?.first { $0.type == .range }?.value?.intValue ?? 1
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
        let own = action.value.flatMap { gameManager?.editionStore.resolveCustomText($0.stringValue, edition: character.edition) } ?? ""
        let text = (own + " " + customText(of: action)).lowercased()
        if text.contains("trap in an adjacent empty hex"), text.hasPrefix("create") || text.contains(" create") {
            // Proximity Mine: "Create one 6 damage trap…", "Gain XP +2 when the trap is sprung by
            // an enemy" (the next line of the half); Volatile Concoction: "2 damage Poison trap".
            let half = phase == .executeBottomAction ? bottomActions : topActions
            let following = half.dropFirst(currentActionIndex + 1).first.map(customText(of:)) ?? ""
            let nextLine = half.dropFirst(currentActionIndex + 1).first.flatMap { $0.value }
                .flatMap { gameManager?.editionStore.resolveCustomText($0.stringValue, edition: character.edition) }?.lowercased() ?? following
            let xp = nextLine.contains("trap is sprung") ? (nextLine.firstMatch(of: #/xp \+(\d+)/#).flatMap { Int($0.1) } ?? 0) : 0
            let trap = PlacedToken.trap(damage: Self.damageAmount(in: text), subType: text.contains("poison") ? "poison" : nil,
                                        experience: xp)
            return coordinator.beginPlacingTokens(trap, count: 1, by: me)
        } else if text.contains("obstacle") && text.contains("create") {
            // Avalanche: "Create two single-hex obstacles in empty hexes adjacent to you."
            let count = text.contains("two") ? 2 : 1
            return coordinator.beginPlacingTokens(.obstacle, count: count, by: me)
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
            let title = (phase == .executeBottomAction ? bottomCard : topCard)?.name ?? "Recover"
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
            coordinator.printedDamage(text, amount: amount, by: me, around: coordinator.boardState.piecePositions[me])
        }
        return false
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
        guard let character, let playing = (phase == .executeBottomAction ? bottomCard : topCard)?.cardId else { return }
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
    }

    /// A half as the steps the player performs one by one: groupings (concatenations, grids,
    /// boxes) and text that wraps printed actions (Crater's "suffer 1 damage" around its Move) are
    /// opened up, so a move or a target choice inside them is a step of its own and the turn
    /// waits for it. Augments stay whole: they aren't performed.
    static func steps(_ actions: [ActionModel], labels: EditionDataStore? = nil, edition: String = "gh") -> [ActionModel] {
        actions.flatMap { action -> [ActionModel] in
            switch action.type {
            case .concatenation, .grid:
                return steps(action.subActions ?? [])
            case .box where !isAugment(action):
                return steps(action.subActions ?? [])
            case .custom where (action.subActions ?? []).contains(where: { isWrapped($0) })
                && !performedBySomeoneElse(action, labels: labels, edition: edition):
                // The text stays a step (with the element it may consume, "2 damage instead");
                // the actions it wraps become steps of their own.
                var text = action
                text.subActions = (action.subActions ?? []).filter { !isWrapped($0) }
                return [text] + steps((action.subActions ?? []).filter(isWrapped))
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
        return text.contains("perform") || key.contains("perform")
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
        case "allyadjacent", "alliesadjacent", "alliesadjacentaffect":
            return .allAllies(range: 1)
        case "alliesaffect":
            return .allAllies(range: nil)
        case "selfalliesaffect", "selfalliesadjacentaffect":
            return .selfAndAllAllies(range: lower.contains("adjacent") ? 1 : nil)
        default:
            if let r = embeddedRange("enemiesrange:") { return .allEnemies(range: r) }
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

        let summonData: SummonDataModel
        if let found = character.characterData?.availableSummons?.first(where: { $0.name == summonName }) {
            summonData = found
        } else if let embedded = action.summonValueObject {
            summonData = embedded.toSummonData()
        } else {
            coordinator.log("\(who)\u{2019}s summon could not be found", category: .info, trace: summonName)
            return false
        }

        let pieceID = PieceID.character(characterID)
        guard let charPos = coordinator.boardState.piecePositions[pieceID] else { return false }

        // Summons are placed in an empty hex adjacent to the summoner (p.26).
        let emptyNeighbors = charPos.neighbors.filter { coordinator.isEmptyHex($0) }
        guard !emptyNeighbors.isEmpty else {
            coordinator.log("\(who) can\u{2019}t summon \(GameText.titleCased(summonName)): no empty hex next to them", category: .info)
            return false
        }

        gameManager.characterManager.addSummon(from: summonData, for: character)
        guard let summon = character.summons.last else { return false }

        let validHexes = Set(emptyNeighbors)
        coordinator.pendingSummonPlacement = BoardCoordinator.PendingSummonPlacement(
            summonID: summon.id,
            characterID: characterID,
            summonName: summonName,
            validHexes: validHexes,
            remaining: max(0, (summonData.count ?? 1) - 1),
            summonData: summonData
        )
        coordinator.interactionMode = .placingSummon(
            summonID: summon.id,
            characterID: characterID,
            validHexes: validHexes
        )
        coordinator.boardScene?.highlightHexes(validHexes, style: .summon, offsetCol: coordinator.offsetCol, offsetRow: coordinator.offsetRow)
        coordinator.log("\(who) summons \(GameText.titleCased(summonName)). Choose a hex next to them", category: .info)
        return true
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
        }
    }

    // MARK: - Putting cards away

    /// "card" markers (persistent / round / lost) printed on a half, at any nesting depth.
    private func halfMarkers(for phase: PlayerTurnPhase) -> Set<String> {
        let actions = phase == .executeBottomAction ? bottomActions : topActions
        return Self.markers(in: actions)
    }

    static func markers(in actions: [ActionModel]) -> Set<String> {
        var result = Set<String>()
        for action in actions {
            if action.type == .card, let value = action.value?.stringValue, !value.contains(":") {
                result.insert(value)
            }
            result.formUnion(markers(in: action.subActions ?? []))
        }
        return result
    }

    /// Put both played cards away (GH p.16): a card played for a default action is discarded;
    /// otherwise an active bonus (persistent or round) goes to the active area, a half with the
    /// lost icon goes to the lost pile, and the rest are discarded.
    private func finishTurn() {
        guard let character, !character.exhausted else { return }
        putAway(topCard, half: topActions, lostFlag: topCard?.lost == true, usedAsDefault: topUsedAsDefault,
                character: character)
        putAway(bottomCard, half: bottomActions, lostFlag: bottomCard?.bottomLost == true,
                usedAsDefault: bottomUsedAsDefault, character: character)
        coordinator?.log("\(who) ends the turn", category: .round)
    }

    private func putAway(_ card: AbilityModel?, half: [ActionModel], lostFlag: Bool, usedAsDefault: Bool,
                         character: GameCharacter) {
        guard let cardId = card?.cardId, let index = character.handCards.firstIndex(of: cardId) else { return }
        character.handCards.remove(at: index)

        if usedAsDefault {
            character.discardedCards.append(cardId)
            return
        }
        let markers = Self.markers(in: half)
        let lost = lostFlag || markers.contains("lost")
        if usedUpThisTurn.contains(cardId) {
            // Its charges ran out during this turn: it goes straight where it would end up.
            if lost { character.lostCards.append(cardId) } else { character.discardedCards.append(cardId) }
        } else if markers.contains("persistent") || markers.contains("round") {
            character.activeCards.append(cardId)
            if markers.contains("round") && !markers.contains("persistent") {
                character.roundBonusCards.append(cardId)
            }
            if lost { character.lostWhenRemoved.append(cardId) }
        } else if lost {
            character.lostCards.append(cardId)
        } else {
            character.discardedCards.append(cardId)
        }
    }
}
