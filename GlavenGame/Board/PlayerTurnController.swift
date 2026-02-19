import Foundation

/// State machine for a player's turn.
enum PlayerTurnPhase {
    case selectTopCard
    case executeTopAction
    case executeBottomAction
    case turnComplete
}

/// Controls a single player character's turn on the board.
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

    /// Pierce, push, pull, and conditions extracted from the current attack's sub-actions.
    var pendingPierce: Int = 0
    var pendingPush: Int = 0
    var pendingPull: Int = 0
    var pendingConditions: [ConditionName] = []

    private weak var coordinator: BoardCoordinator?
    private weak var gameManager: GameManager?

    init(characterID: String, coordinator: BoardCoordinator, gameManager: GameManager) {
        self.characterID = characterID
        self.coordinator = coordinator
        self.gameManager = gameManager
    }

    // MARK: - Card Selection

    /// Set the two selected cards and which is used for top/bottom.
    func selectCards(top: AbilityModel, bottom: AbilityModel) {
        self.topCard = top
        self.bottomCard = bottom
        self.topActions = top.actions ?? []
        self.bottomActions = bottom.bottomActions ?? bottom.actions ?? []
        self.phase = .executeTopAction
        self.currentActionIndex = 0
    }

    /// Select long rest instead of cards.
    func selectLongRest() {
        isLongRest = true
        phase = .turnComplete
        executeLongRest()
    }

    // MARK: - Action Execution

    /// Execute the current action in the current phase.
    func executeCurrentAction() {
        guard let coordinator = coordinator else { return }

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

        let action = actions[currentActionIndex]
        let isAsync = action.type == .attack || action.type == .summon || action.type == .push || action.type == .pull
        executeAction(action, coordinator: coordinator)
        // Attack and summon actions are async (player must select a target/hex),
        // so don't advance the index yet — it's advanced in advanceAfterAsyncAction().
        if !isAsync {
            currentActionIndex += 1
        }
    }

    /// Advance the action index after an async action (attack/summon) resolves.
    func advanceAfterAsyncAction() {
        currentActionIndex += 1
    }

    /// Skip remaining actions in the current phase.
    func skipRemainingActions() {
        advancePhase()
    }

    /// Use default action for the current phase (Attack 2 for top, Move 2 for bottom).
    func useDefaultAction() {
        guard let coordinator = coordinator else { return }

        let pieceID = PieceID.character(characterID)
        switch phase {
        case .executeTopAction:
            // Default top: Attack 2
            coordinator.beginAttackAction(pieceID: pieceID, range: 1)
            coordinator.log("\(characterID): Default Attack 2", category: .attack)
        case .executeBottomAction:
            // Default bottom: Move 2
            coordinator.beginMoveAction(pieceID: pieceID, moveRange: 2)
            coordinator.log("\(characterID): Default Move 2", category: .move)
        default:
            break
        }
        advancePhase()
    }

    // MARK: - Queries

    /// The current attack value based on the active action.
    func currentAttackValue() -> Int {
        let actions: [ActionModel]
        switch phase {
        case .executeTopAction: actions = topActions
        case .executeBottomAction: actions = bottomActions
        default: return 2
        }
        guard currentActionIndex < actions.count else { return 2 }
        let action = actions[currentActionIndex]
        return action.type == .attack ? (action.value?.intValue ?? 2) : 2
    }

    /// The current attack range based on the active action.
    func currentAttackRange() -> Int {
        let actions: [ActionModel]
        switch phase {
        case .executeTopAction: actions = topActions
        case .executeBottomAction: actions = bottomActions
        default: return 1
        }
        guard currentActionIndex < actions.count else { return 1 }
        let action = actions[currentActionIndex]
        if action.type == .attack {
            for sub in action.subActions ?? [] {
                if sub.type == .range, let r = sub.value?.intValue { return r }
            }
        }
        return 1
    }

    // MARK: - Private

    private func advancePhase() {
        switch phase {
        case .executeTopAction:
            phase = .executeBottomAction
            currentActionIndex = 0
        case .executeBottomAction:
            phase = .turnComplete
            finishTurn()
        default:
            break
        }
    }

    private func executeAction(_ action: ActionModel, coordinator: BoardCoordinator) {
        let pieceID = PieceID.character(characterID)

        switch action.type {
        case .move:
            let moveValue = action.value?.intValue ?? 2
            coordinator.beginMoveAction(pieceID: pieceID, moveRange: moveValue)
            coordinator.log("\(characterID): Move \(moveValue)", category: .move)

        case .jump:
            let jumpValue = action.value?.intValue ?? 2
            coordinator.beginMoveAction(pieceID: pieceID, moveRange: jumpValue)
            coordinator.log("\(characterID): Jump \(jumpValue)", category: .move)

        case .fly:
            let flyValue = action.value?.intValue ?? 2
            coordinator.beginMoveAction(pieceID: pieceID, moveRange: flyValue)
            coordinator.log("\(characterID): Fly \(flyValue)", category: .move)

        case .teleport:
            let teleportValue = action.value?.intValue ?? 2
            coordinator.beginMoveAction(pieceID: pieceID, moveRange: teleportValue)
            coordinator.log("\(characterID): Teleport \(teleportValue)", category: .move)

        case .attack:
            var range = 1 // Default melee
            var targetCount = 1
            pendingPierce = 0
            pendingPush = 0
            pendingPull = 0
            pendingConditions = []
            for sub in action.subActions ?? [] {
                if sub.type == .range, let r = sub.value?.intValue {
                    range = r
                }
                if sub.type == .target, let t = sub.value?.intValue, t > 1 {
                    targetCount = t
                }
                if sub.type == .pierce, let p = sub.value?.intValue {
                    pendingPierce = p
                }
                if sub.type == .push, let p = sub.value?.intValue {
                    pendingPush = p
                }
                if sub.type == .pull, let p = sub.value?.intValue {
                    pendingPull = p
                }
                if sub.type == .condition,
                   let condName = sub.value?.stringValue,
                   let cond = ConditionName(rawValue: condName) {
                    pendingConditions.append(cond)
                }
            }
            let attackValue = action.value?.intValue ?? 2
            coordinator.beginAttackAction(pieceID: pieceID, range: range, targetCount: targetCount)
            var extras: [String] = []
            if targetCount > 1 { extras.append("Target \(targetCount)") }
            if pendingPierce > 0 { extras.append("Pierce \(pendingPierce)") }
            if pendingPush > 0 { extras.append("Push \(pendingPush)") }
            if pendingPull > 0 { extras.append("Pull \(pendingPull)") }
            for cond in pendingConditions { extras.append(cond.rawValue.capitalized) }
            let extrasStr = extras.isEmpty ? "" : ", " + extras.joined(separator: ", ")
            coordinator.log("\(characterID): Attack \(attackValue), Range \(range)\(extrasStr)", category: .attack)

        case .heal:
            let healValue = action.value?.intValue ?? 0
            coordinator.log("\(characterID): Heal \(healValue)", category: .heal)
            if let character = gameManager?.game.characters.first(where: { $0.id == characterID }) {
                gameManager?.entityManager.changeHealth(character, amount: healValue)
            }

        case .condition:
            if let condName = action.value?.stringValue, let cond = ConditionName(rawValue: condName) {
                applyConditionToSelf(cond, coordinator: coordinator)
            }

        case .shield:
            let shieldValue = action.value?.intValue ?? 0
            if let character = gameManager?.game.characters.first(where: { $0.id == characterID }) {
                character.shield = ActionModel(type: .shield, value: .int(shieldValue))
                coordinator.log("\(characterID): Shield \(shieldValue)", category: .condition)
            }

        case .retaliate:
            let retValue = action.value?.intValue ?? 0
            var retRange = 1
            for sub in action.subActions ?? [] {
                if sub.type == .range, let r = sub.value?.intValue { retRange = r }
            }
            if let character = gameManager?.game.characters.first(where: { $0.id == characterID }) {
                let retAction = ActionModel(type: .retaliate, value: .int(retValue),
                                            subActions: retRange > 1 ? [ActionModel(type: .range, value: .int(retRange))] : nil)
                character.retaliate = [retAction]
                coordinator.log("\(characterID): Retaliate \(retValue)\(retRange > 1 ? ", Range \(retRange)" : "")", category: .condition)
            }

        case .experience:
            let xpValue = action.value?.intValue ?? 1
            if let character = gameManager?.game.characters.first(where: { $0.id == characterID }) {
                character.experience += xpValue
                coordinator.log("\(characterID): +\(xpValue) XP (total: \(character.experience))", category: .info)
            }

        case .loot:
            let lootRange = action.value?.intValue ?? 1
            coordinator.log("\(characterID): Loot \(lootRange)", category: .loot)

        case .summon:
            executeSummon(action, coordinator: coordinator)

        case .push:
            let pushValue = action.value?.intValue ?? 1
            coordinator.log("\(characterID): Push \(pushValue)", category: .move)
            coordinator.beginStandalonePushPull(steps: pushValue, isPush: true)

        case .pull:
            let pullValue = action.value?.intValue ?? 1
            coordinator.log("\(characterID): Pull \(pullValue)", category: .move)
            coordinator.beginStandalonePushPull(steps: pullValue, isPush: false)

        case .pierce:
            let pierceValue = action.value?.intValue ?? 0
            coordinator.log("\(characterID): Pierce \(pierceValue)", category: .attack)

        case .suffer, .sufferDamage:
            let sufferValue = action.value?.intValue ?? 1
            if let character = gameManager?.game.characters.first(where: { $0.id == characterID }) {
                gameManager?.entityManager.changeHealth(character, amount: -sufferValue)
                coordinator.log("\(characterID): Suffer \(sufferValue) damage", category: .damage)
            }

        case .damage:
            let damageValue = action.value?.intValue ?? 1
            coordinator.log("\(characterID): Damage \(damageValue)", category: .damage)

        case .element:
            applyElementAction(action, coordinator: coordinator)

        case .refreshItem, .refreshSpent, .forceRefresh:
            coordinator.log("\(characterID): Refresh items", category: .info)

        case .removeNegativeConditions:
            if let character = gameManager?.game.characters.first(where: { $0.id == characterID }) {
                character.entityConditions.removeAll { !$0.name.isPositive && !$0.expired }
                coordinator.log("\(characterID): Remove negative conditions", category: .condition)
            }

        case .immune:
            if let condName = action.value?.stringValue, let cond = ConditionName(rawValue: condName) {
                if let character = gameManager?.game.characters.first(where: { $0.id == characterID }) {
                    if !character.immunities.contains(cond) {
                        character.immunities.append(cond)
                    }
                    coordinator.log("\(characterID): Immune to \(condName)", category: .condition)
                }
            }

        case .box, .concatenation, .grid:
            // Container actions: recursively execute their children
            for sub in action.subActions ?? [] {
                executeAction(sub, coordinator: coordinator)
            }

        case .card:
            // Card sub-actions: extract experience (format "experience:N")
            if let val = action.value?.stringValue, val.hasPrefix("experience:"),
               let xp = Int(val.dropFirst("experience:".count)) {
                if let character = gameManager?.game.characters.first(where: { $0.id == characterID }) {
                    character.experience += xp
                    coordinator.log("\(characterID): +\(xp) XP", category: .info)
                }
            }

        case .target, .range, .area, .specialTarget:
            // These are sub-action modifiers, not standalone — handled when parent action runs
            break

        case .custom, .hint, .text, .nonCalc:
            // Display-only types — no game effect
            break

        default:
            coordinator.log("\(characterID): \(action.type.rawValue)", category: .info)
        }

        // Check sub-actions for element infusions/consumptions and experience
        for sub in action.subActions ?? [] {
            if sub.type == .element {
                applyElementAction(sub, coordinator: coordinator)
            } else if sub.type == .experience {
                let xpValue = sub.value?.intValue ?? 1
                if let character = gameManager?.game.characters.first(where: { $0.id == characterID }) {
                    character.experience += xpValue
                    coordinator.log("\(characterID): +\(xpValue) XP", category: .info)
                }
            } else if sub.type == .condition {
                if let condName = sub.value?.stringValue, let cond = ConditionName(rawValue: condName) {
                    applyConditionToSelf(cond, coordinator: coordinator)
                }
            }
        }
    }

    /// Apply a condition to the acting character.
    private func applyConditionToSelf(_ condition: ConditionName, coordinator: BoardCoordinator) {
        guard let character = gameManager?.game.characters.first(where: { $0.id == characterID }) else { return }

        // Don't duplicate existing non-expired conditions
        if !character.entityConditions.contains(where: { $0.name == condition && !$0.expired }) {
            character.entityConditions.append(EntityCondition(name: condition))
        }
        coordinator.log("\(characterID): \(condition.rawValue)", category: .condition)
    }

    /// Execute a summon action: create the summon entity and enter interactive placement mode.
    private func executeSummon(_ action: ActionModel, coordinator: BoardCoordinator) {
        guard let gameManager = gameManager,
              let character = gameManager.game.characters.first(where: { $0.id == characterID }) else { return }

        // Resolve summon name: prefer valueObject.name, fall back to action.value
        let summonName = action.summonValueObject?.name ?? action.value?.stringValue
        guard let summonName else {
            coordinator.log("\(characterID): Summon (unknown)", category: .info)
            return
        }

        // Look up summon data from character's available summons, or use embedded valueObject stats
        let summonData: SummonDataModel
        if let found = character.characterData?.availableSummons?.first(where: { $0.name == summonName }) {
            summonData = found
        } else if let embedded = action.summonValueObject {
            summonData = embedded.toSummonData()
        } else {
            coordinator.log("\(characterID): Summon \(summonName) — not found in character data", category: .info)
            return
        }

        // Find empty adjacent hexes for placement
        let pieceID = PieceID.character(characterID)
        guard let charPos = coordinator.boardState.piecePositions[pieceID] else {
            coordinator.log("\(characterID): Summon \(summonName) — no position found", category: .info)
            return
        }

        let emptyNeighbors = charPos.neighbors.filter { coord in
            coordinator.boardState.isPassable(coord) && !coordinator.boardState.isOccupied(coord)
        }

        guard !emptyNeighbors.isEmpty else {
            coordinator.log("\(characterID): Summon \(summonName) failed — no empty adjacent hex", category: .info)
            return
        }

        // Create the summon via CharacterManager
        gameManager.characterManager.addSummon(from: summonData, for: character)
        guard let summon = character.summons.last else { return }

        // Enter interactive placement mode
        let validHexes = Set(emptyNeighbors)
        coordinator.pendingSummonPlacement = BoardCoordinator.PendingSummonPlacement(
            summonID: summon.id,
            characterID: characterID,
            summonName: summonName,
            validHexes: validHexes
        )
        coordinator.interactionMode = .placingSummon(
            summonID: summon.id,
            characterID: characterID,
            validHexes: validHexes
        )
        coordinator.boardScene?.highlightHexes(validHexes, color: .green, offsetCol: coordinator.offsetCol, offsetRow: coordinator.offsetRow)
        coordinator.log("\(characterID): Summoned \(summonName) — choose placement hex", category: .info)
    }

    /// Infuse or consume an element based on the action's valueType.
    private func applyElementAction(_ action: ActionModel, coordinator: BoardCoordinator) {
        guard let game = gameManager?.game else { return }
        guard let rawValue = action.value?.stringValue else { return }
        let values = rawValue.split(separator: ":").map(String.init)
        let isConsume = action.valueType == .minus || action.valueType == .subtract

        for val in values {
            guard let elemType = ElementType(rawValue: val) else { continue }
            guard let idx = game.elementBoard.firstIndex(where: { $0.type == elemType }) else { continue }

            if isConsume {
                let current = game.elementBoard[idx].state
                if current == .strong || current == .waning {
                    game.elementBoard[idx].state = .consumed
                    coordinator.log("\(characterID): Consumed \(val)", category: .element)
                }
            } else {
                let current = game.elementBoard[idx].state
                if current == .inert || current == .consumed {
                    game.elementBoard[idx].state = .new
                    coordinator.log("\(characterID): Infused \(val)", category: .element)
                }
            }
        }
    }

    private func executeLongRest() {
        guard let coordinator = coordinator,
              let character = gameManager?.game.characters.first(where: { $0.id == characterID }) else { return }

        // Heal 2
        gameManager?.entityManager.changeHealth(character, amount: 2)

        // Lose a random card from discard
        if !character.discardedCards.isEmpty {
            let randomIndex = Int.random(in: 0..<character.discardedCards.count)
            let lostCard = character.discardedCards.remove(at: randomIndex)
            character.lostCards.append(lostCard)
        }

        // Refresh spent items
        character.longRest = true

        coordinator.log("\(characterID): Long Rest — Heal 2, lose card, refresh items", category: .rest)
    }

    private func finishTurn() {
        // Move cards to appropriate piles
        guard let character = gameManager?.game.characters.first(where: { $0.id == characterID }) else { return }

        if let top = topCard?.cardId {
            if topCard?.lost == true {
                character.lostCards.append(top)
            } else {
                character.discardedCards.append(top)
            }
            character.handCards.removeAll { $0 == top }
        }

        if let bottom = bottomCard?.cardId {
            if bottomCard?.bottomLost == true {
                character.lostCards.append(bottom)
            } else {
                character.discardedCards.append(bottom)
            }
            character.handCards.removeAll { $0 == bottom }
        }

        coordinator?.log("\(characterID): Turn complete", category: .round)
    }
}
