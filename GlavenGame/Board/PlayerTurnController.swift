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
        self.topActions = top.actions ?? []
        self.bottomActions = bottom.bottomActions ?? []
        self.phase = bottomFirst ? .executeBottomAction : .executeTopAction
        self.currentActionIndex = 0
    }

    /// Use the other card for the top half (allowed until the first action is performed).
    func swapCards() {
        guard !hasActed, let top = topCard, let bottom = bottomCard else { return }
        selectCards(top: bottom, bottom: top)
        coordinator?.log("\(characterID): Top from \(bottom.name ?? "?"), bottom from \(top.name ?? "?")", category: .round)
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

    /// Use the default action for the current half instead of the printed one:
    /// Attack 2 on the top half, Move 2 on the bottom half.
    func useDefaultAction() {
        guard let coordinator = coordinator, !hasActed || currentActionIndex == 0, !defaultAttackPending else { return }
        hasActed = true

        let pieceID = PieceID.character(characterID)
        guard !awaitingAsync else { return }
        switch phase {
        case .executeTopAction:
            topUsedAsDefault = true
            resetPendingAttack(value: 2, range: 1)
            defaultAttackPending = true
            coordinator.log("\(characterID): Default Attack 2", category: .attack)
            coordinator.beginAttackAction(pieceID: pieceID, range: 1)
        case .executeBottomAction:
            bottomUsedAsDefault = true
            defaultAttackPending = true // ends the half once the move resolves
            coordinator.log("\(characterID): Default Move 2", category: .move)
            coordinator.beginMoveAction(pieceID: pieceID, moveRange: 2)
        default:
            break
        }
    }

    // MARK: - Queries

    /// The attack value of the attack currently being resolved.
    func currentAttackValue() -> Int { pendingAttackValue }

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
            coordinator?.log("\(characterID): Consumed \(used.map(\.rawValue).joined(separator: " + "))", category: .element)
            for effect in sub.subActions ?? [] {
                if effect.type == .concatenation {
                    bonus.append(contentsOf: effect.subActions ?? [])
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

    private func grantExperience(_ xp: Int) {
        guard let character, xp > 0 else { return }
        character.experience += xp
        coordinator?.log("\(characterID): +\(xp) XP", category: .info)
    }

    /// Execute one action. Returns true if it waits for player input (and advances later).
    @discardableResult
    private func executeAction(_ action: ActionModel, coordinator: BoardCoordinator) -> Bool {
        let pieceID = PieceID.character(characterID)

        switch action.type {
        case .move, .jump, .fly:
            let bonus = consumeAugments(of: action)
            var moveValue = action.value?.intValue ?? 2
            var mode: MoveMode = action.type == .jump ? .jump : (action.type == .fly ? .fly : .normal)
            for effect in (action.subActions ?? []) + bonus {
                if effect.type == .jump { mode = .jump }
                if effect.type == .fly { mode = .fly }
                if effect.type == .move { moveValue += MonsterAbility.signedValue(effect) }
            }
            grantBonusExperience(bonus)
            let label = mode == .jump ? "Jump" : (mode == .fly ? "Fly" : "Move")
            coordinator.log("\(characterID): \(label) \(moveValue)", category: .move)
            coordinator.beginMoveAction(pieceID: pieceID, moveRange: moveValue, mode: mode)
            return true

        case .teleport:
            let teleportValue = action.value?.intValue ?? 2
            coordinator.log("\(characterID): Teleport \(teleportValue)", category: .move)
            coordinator.beginTeleportAction(pieceID: pieceID, range: teleportValue)
            return true

        case .attack:
            var range = 1
            var targetCount = 1
            var allTargets: String?
            resetPendingAttack(value: action.value?.intValue ?? 2, range: 1)
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
            if hasTarget { grantBonusExperience(bonus) }
            pendingAttackRange = range

            // "Attack all adjacent enemies" / "all enemies within range N": every such enemy is
            // a separate attack of the same action.
            if let spec = allTargets?.lowercased(), spec.hasPrefix("enemiesadjacent") || spec.hasPrefix("enemiesrange") {
                let reach: Int = spec.hasPrefix("enemiesadjacent")
                    ? 1 : Int(spec.split(separator: ":").last ?? "") ?? range
                let exact = spec.hasPrefix("enemiesrangeexact")
                coordinator.log("\(characterID): Attack \(pendingAttackValue) — all enemies within \(reach)", category: .attack)
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
            coordinator.log("\(characterID): Attack \(pendingAttackValue), Range \(range)\(extrasStr)", category: .attack)
            coordinator.beginAttackAction(pieceID: pieceID, range: range, targetCount: targetCount)
            return true

        case .heal:
            let bonus = consumeAugments(of: action)
            var healValue = action.value?.intValue ?? 0
            var range = 0
            for sub in (action.subActions ?? []) + bonus {
                if sub.type == .range, let r = sub.value?.intValue { range = r }
                if sub.type == .heal { healValue += MonsterAbility.signedValue(sub) }
            }
            grantBonusExperience(bonus)
            if range > 0 {
                coordinator.log("\(characterID): Heal \(healValue), Range \(range) — select target", category: .heal)
                coordinator.beginHealAction(pieceID: pieceID, healValue: healValue, range: range)
                return true
            }
            let healed = coordinator.heal(pieceID, amount: healValue, source: pieceID)
            coordinator.log("\(characterID): Heal \(healValue), self (+\(healed))", category: .heal)

        case .condition:
            guard let condName = action.value?.stringValue,
                  let cond = ConditionName(rawValue: condName) else { break }
            switch conditionTargetSpec(action) {
            case .singleEnemy(let range):
                coordinator.beginConditionAction(pieceID: pieceID, condition: cond, range: range)
                coordinator.log("\(characterID): \(cond.rawValue) — select target", category: .condition)
                return true
            case .allEnemies(let range):
                coordinator.applyConditionToAllEnemies(from: pieceID, condition: cond, range: range ?? 1)
                coordinator.log("\(characterID): \(cond.rawValue) → all enemies (range \(range ?? 1))", category: .condition)
            case .allAllies(let range):
                coordinator.applyConditionToAllAllies(from: pieceID, condition: cond, range: range ?? 999)
                coordinator.log("\(characterID): \(cond.rawValue) → all allies", category: .condition)
            case .selfAndAllAllies(let range):
                coordinator.applyCondition(cond, to: pieceID)
                coordinator.applyConditionToAllAllies(from: pieceID, condition: cond, range: range ?? 999)
            case .`self`:
                coordinator.applyCondition(cond, to: pieceID)
            }

        case .shield, .retaliate:
            applyDefensiveBonus(action)

        case .experience:
            grantExperience(action.value?.intValue ?? 1)

        case .loot:
            let lootRange = action.value?.intValue ?? 1
            coordinator.log("\(characterID): Loot \(lootRange)", category: .loot)
            coordinator.collectLootInRange(pieceID: pieceID, range: lootRange)

        case .summon:
            return executeSummon(action, coordinator: coordinator)

        case .push, .pull:
            let steps = action.value?.intValue ?? 1
            let isPush = action.type == .push
            let spec = action.subActions?.first { $0.type == .specialTarget }?.value?.stringValue.lowercased()
            let range = action.subActions?.first { $0.type == .range }?.value?.intValue
            coordinator.log("\(characterID): \(isPush ? "Push" : "Pull") \(steps)", category: .move)
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
            coordinator.log("\(characterID): Suffer \(sufferValue) damage", category: .damage)
            coordinator.sufferDamage(sufferValue, to: pieceID)

        case .element:
            applyElementAction(action, coordinator: coordinator)

        case .refreshItem, .refreshSpent, .forceRefresh:
            coordinator.log("\(characterID): Refresh items", category: .info)

        case .removeNegativeConditions:
            character?.entityConditions.removeAll { $0.name.isNegative && !$0.permanent }
            coordinator.log("\(characterID): Remove negative conditions", category: .condition)

        case .immune:
            if let condName = action.value?.stringValue, let cond = ConditionName(rawValue: condName),
               let character, !character.immunities.contains(cond) {
                character.immunities.append(cond)
                coordinator.log("\(characterID): Immune to \(condName)", category: .condition)
            }

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

        // Infusions printed inside a non-element action happen when the action is performed;
        // conditions on self-targeted actions apply to the character.
        if action.type != .element && action.type != .attack {
            for sub in action.subActions ?? [] where sub.type == .element && !MonsterAbility.isConsume(sub) {
                applyElementAction(sub, coordinator: coordinator)
            }
        }
        if action.type == .attack {
            for sub in action.subActions ?? [] where sub.type == .element && !MonsterAbility.isConsume(sub) {
                applyElementAction(sub, coordinator: coordinator)
            }
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

    /// Range of an attack action before augments (melee = 1).
    private func attackRange(of action: ActionModel) -> Int {
        action.subActions?.first { $0.type == .range }?.value?.intValue ?? 1
    }

    private func hasSpecialTargetSelf(_ action: ActionModel) -> Bool {
        action.subActions?.contains { $0.type == .specialTarget && $0.value?.stringValue == "self" } ?? false
    }

    /// Shield/Retaliate bonuses stack (GH p.24). A persistent bonus lasts while the card is in
    /// the active area; a round bonus until the end of the round.
    private func applyDefensiveBonus(_ action: ActionModel) {
        guard let character, let coordinator else { return }
        let value = action.value?.intValue ?? 0
        let persistent = halfMarkers(for: phase).contains("persistent")
        if action.type == .shield {
            let existing = persistent ? character.shieldPersistent : character.shield
            let total = (existing?.value?.intValue ?? 0) + value
            let stacked = ActionModel(type: .shield, value: .int(total))
            if persistent { character.shieldPersistent = stacked } else { character.shield = stacked }
            coordinator.log("\(characterID): Shield \(value)", category: .condition)
        } else {
            var range = 1
            for sub in action.subActions ?? [] where sub.type == .range { range = sub.value?.intValue ?? 1 }
            let bonus = ActionModel(type: .retaliate, value: .int(value),
                                    subActions: range > 1 ? [ActionModel(type: .range, value: .int(range))] : nil)
            if persistent { character.retaliatePersistent.append(bonus) } else { character.retaliate.append(bonus) }
            coordinator.log("\(characterID): Retaliate \(value)\(range > 1 ? ", Range \(range)" : "")", category: .condition)
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
    }

    /// Parse the `specialTarget` subaction to determine how a condition should be targeted.
    private func conditionTargetSpec(_ action: ActionModel) -> ConditionTarget {
        guard let specValue = action.subActions?
            .first(where: { $0.type == .specialTarget })?.value?.stringValue else {
            // A condition with a range targets one enemy in range; otherwise it targets oneself.
            if let range = action.subActions?.first(where: { $0.type == .range })?.value?.intValue {
                return .singleEnemy(range: range)
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
        case "enemiesadjacent", "enemiesmoved through", "enemiesmoved":
            return .allEnemies(range: 1)
        case "enemies":
            return .allEnemies(range: nil)
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
            coordinator.log("\(characterID): Summon (unknown)", category: .info)
            return false
        }

        let summonData: SummonDataModel
        if let found = character.characterData?.availableSummons?.first(where: { $0.name == summonName }) {
            summonData = found
        } else if let embedded = action.summonValueObject {
            summonData = embedded.toSummonData()
        } else {
            coordinator.log("\(characterID): Summon \(summonName) — not found in character data", category: .info)
            return false
        }

        let pieceID = PieceID.character(characterID)
        guard let charPos = coordinator.boardState.piecePositions[pieceID] else { return false }

        // Summons are placed in an empty hex adjacent to the summoner (p.26).
        let emptyNeighbors = charPos.neighbors.filter { coordinator.isEmptyHex($0) }
        guard !emptyNeighbors.isEmpty else {
            coordinator.log("\(characterID): Summon \(summonName) failed — no empty adjacent hex", category: .info)
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
        coordinator.boardScene?.highlightHexes(validHexes, color: .green, offsetCol: coordinator.offsetCol, offsetRow: coordinator.offsetRow)
        coordinator.log("\(characterID): Summoned \(summonName) — choose placement hex", category: .info)
        return true
    }

    /// Infuse or consume an element based on the action's valueType.
    private func applyElementAction(_ action: ActionModel, coordinator: BoardCoordinator) {
        guard let game = gameManager?.game else { return }
        let elements = MonsterAbility.elements(of: action)
        guard !elements.isEmpty else { return }
        if MonsterAbility.isConsume(action) {
            if let used = game.consumeElements(elements) {
                coordinator.log("\(characterID): Consumed \(used.map(\.rawValue).joined(separator: " + "))", category: .element)
            }
        } else {
            // Becomes strong at the end of this turn (it can't be consumed by this turn's actions).
            for element in elements where element != .wild {
                game.infuseElement(element)
                coordinator.log("\(characterID): Infused \(element.rawValue)", category: .element)
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
        coordinator?.log("\(characterID): Turn complete", category: .round)
    }

    private func putAway(_ card: AbilityModel?, half: [ActionModel], lostFlag: Bool, usedAsDefault: Bool,
                         character: GameCharacter) {
        guard let cardId = card?.cardId else { return }
        character.handCards.removeAll { $0 == cardId }

        if usedAsDefault {
            character.discardedCards.append(cardId)
            return
        }
        let markers = Self.markers(in: half)
        let lost = lostFlag || markers.contains("lost")
        if markers.contains("persistent") || markers.contains("round") {
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
