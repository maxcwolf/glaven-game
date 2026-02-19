import Foundation

/// Controls the automated execution of all monster turns.
@Observable
final class MonsterTurnController {

    private weak var coordinator: BoardCoordinator?
    private weak var gameManager: GameManager?
    var isExecuting: Bool = false

    init(coordinator: BoardCoordinator, gameManager: GameManager) {
        self.coordinator = coordinator
        self.gameManager = gameManager
    }

    // MARK: - Execute All Monster Turns

    /// Execute all monster turns for the current round.
    /// Each monster group acts in initiative order, entities within a group act
    /// in order: elites first (ascending standee), then normals (ascending standee).
    func executeAllMonsterTurns() async {
        guard let coordinator = coordinator,
              let gameManager = gameManager else { return }

        isExecuting = true
        coordinator.interactionMode = .watchingMonsterTurn

        // Get all monster groups sorted by initiative
        let monsters = gameManager.game.monsters.sorted { a, b in
            a.effectiveInitiative < b.effectiveInitiative
        }

        for monster in monsters {
            await executeMonsterGroup(monster)
        }

        isExecuting = false
        coordinator.interactionMode = .idle
        coordinator.log("All monster turns complete", category: .round)
    }

    /// Execute a single monster group's turn.
    func executeMonsterGroup(_ monster: GameMonster) async {
        guard let coordinator = coordinator,
              let gameManager = gameManager else { return }

        guard !monster.off else { return }
        guard !monster.aliveEntities.isEmpty else { return }

        isExecuting = true

        // Get the drawn ability card
        let abilityIndex = monster.ability
        guard let deckData = gameManager.editionStore.deckData(name: monster.monsterData?.deck ?? monster.name, edition: monster.edition),
              abilityIndex >= 0 && abilityIndex < deckData.abilities.count else {
            coordinator.log("\(monster.name): No ability card drawn", category: .info)
            isExecuting = false
            return
        }
        let ability = deckData.abilities[abilityIndex]
        coordinator.log("\(monster.name) — Initiative \(ability.initiative)", category: .round)

        // Sort entities: elites first (ascending standee), then normals (ascending standee)
        let sortedEntities = monster.aliveEntities.sorted { a, b in
            if a.type != b.type {
                return a.type == .elite // elites first
            }
            return a.number < b.number
        }

        for entity in sortedEntities {
            let pieceID = PieceID.monster(name: monster.name, standee: entity.number)
            guard coordinator.boardState.piecePositions[pieceID] != nil else { continue }

            let result = MonsterAI.computeTurn(
                pieceID: pieceID,
                monster: monster,
                entity: entity,
                ability: ability,
                board: coordinator.boardState,
                gameState: gameManager.game
            )

            await executeMonsterTurn(result: result, entity: entity, monster: monster)

            // Pause between entities
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
        }

        isExecuting = false
    }

    // MARK: - Single Monster Turn

    private func executeMonsterTurn(result: MonsterTurnResult, entity: GameMonsterEntity, monster: GameMonster) async {
        guard let coordinator = coordinator,
              let gameManager = gameManager else { return }

        if result.stunned {
            coordinator.log("  \(result.entityID): Stunned — skipped", category: .condition)
            return
        }

        // Movement
        if result.movementPath.count > 1 {
            let path = result.movementPath
            coordinator.log("  \(result.entityID): Move \(path.count - 1) hexes", category: .move)

            await withCheckedContinuation { continuation in
                coordinator.boardScene?.movePiece(
                    id: result.entityID, along: path,
                    offsetCol: coordinator.offsetCol, offsetRow: coordinator.offsetRow
                ) {
                    coordinator.boardState.movePiece(result.entityID, to: path.last!)
                    continuation.resume()
                }
            }

            // Check if monster stepped on a trap
            coordinator.checkForTrap(
                pieceID: result.entityID,
                at: path.last!,
                flying: monster.monsterData?.flying ?? false
            )

            // If monster died from trap, skip the rest of this turn
            if entity.dead || entity.health <= 0 { return }
        }

        // Attacks (may have multiple targets)
        if !result.attackTargets.isEmpty {
            let stat = monster.stat(for: entity.type)
            let baseAttack = (stat?.attack?.intValue ?? 0)
            let (_, attackMod, _, abilityConditions) = parseAbilityModifiers(result.abilityActions)
            let totalAttack = baseAttack + attackMod

            for target in result.attackTargets {
                // Skip if attacker already died (e.g. from retaliate on a prior target)
                guard !entity.dead else { break }
                guard let targetPos = coordinator.boardState.piecePositions[target],
                      let attackerPos = coordinator.boardState.piecePositions[result.entityID] else { continue }

                let (defenderHealth, defenderShield, retInfo) = getDefenderInfo(target: target, gameManager: gameManager)

                let isPoisoned = isConditionActive(.poison, on: target, gameManager: gameManager)
                let hasAdvantage = CombatResolver.hasAdvantage(attacker: entity)
                let isRangedAdjacent = (stat?.range?.intValue ?? 0) > 0 && attackerPos.isAdjacent(to: targetPos)
                let hasDisadvantage = CombatResolver.hasDisadvantage(attacker: entity, isRangedAdjacent: isRangedAdjacent)

                // Each target gets its own modifier card draw
                let attackResult = CombatResolver.resolveAttack(
                    attacker: result.entityID,
                    defender: target,
                    baseAttack: totalAttack,
                    advantage: hasAdvantage,
                    disadvantage: hasDisadvantage,
                    isPoisoned: isPoisoned,
                    shield: defenderShield,
                    conditions: abilityConditions,
                    retaliateValue: retInfo.value,
                    retaliateRange: retInfo.range,
                    attackerDefenderDistance: attackerPos.distance(to: targetPos),
                    drawModifier: { gameManager.attackModifierManager.drawMonsterCard() },
                    defenderHealth: defenderHealth
                )

                coordinator.log("  \(result.entityID): Attack \(target) for \(attackResult.damage) damage", category: .attack)

                if attackResult.damage > 0 {
                    coordinator.boardScene?.pieceDamage(id: target, amount: attackResult.damage)

                    if case .character(let charID) = target {
                        let mitigated = await promptDamageMitigation(
                            characterID: charID,
                            damage: attackResult.damage,
                            source: "\(result.entityID)",
                            coordinator: coordinator,
                            gameManager: gameManager
                        )
                        if !mitigated {
                            applyDamage(attackResult.damage, to: target, gameManager: gameManager)
                        }
                    } else {
                        applyDamage(attackResult.damage, to: target, gameManager: gameManager)
                    }
                }

                // Check if target was killed
                let killed: Bool
                if case .character(let charID) = target,
                   let char = gameManager.game.characters.first(where: { $0.id == charID }) {
                    killed = char.health <= 0
                } else if case .summon(let summonID) = target {
                    var summonDead = attackResult.killed
                    for char in gameManager.game.characters {
                        if let summon = char.summons.first(where: { $0.id == summonID }) {
                            summonDead = summon.health <= 0
                            break
                        }
                    }
                    killed = summonDead
                } else {
                    killed = attackResult.killed
                }

                if killed {
                    coordinator.log("  \(target): Killed!", category: .death)
                    coordinator.boardState.removePiece(target)
                    coordinator.boardScene?.removePieceSprite(id: target)
                    markDead(target: target, gameManager: gameManager)
                }

                // Apply conditions to target
                for condition in attackResult.appliedConditions {
                    switch target {
                    case .character(let charID):
                        if let char = gameManager.game.characters.first(where: { $0.id == charID }) {
                            gameManager.entityManager.addCondition(condition, to: char)
                        }
                    case .summon(let summonID):
                        for char in gameManager.game.characters {
                            if let summon = char.summons.first(where: { $0.id == summonID }) {
                                gameManager.entityManager.addCondition(condition, to: summon)
                                break
                            }
                        }
                    default:
                        break
                    }
                    coordinator.log("  \(target): \(condition.rawValue) applied", category: .condition)
                }

                // Show modifier card popup
                if let mod = attackResult.modifierCard {
                    coordinator.lastDrawnModifier = mod
                    coordinator.showModifierCard = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak coordinator] in
                        coordinator?.showModifierCard = false
                    }
                }

                // Retaliate
                if attackResult.retaliateDamage > 0 {
                    coordinator.log("  \(result.entityID): Takes \(attackResult.retaliateDamage) retaliate damage", category: .damage)
                    gameManager.entityManager.changeHealth(entity, amount: -attackResult.retaliateDamage)
                    if entity.health <= 0 {
                        entity.dead = true
                        coordinator.boardState.removePiece(result.entityID)
                        coordinator.boardScene?.removePieceSprite(id: result.entityID)
                        coordinator.log("  \(result.entityID): Killed by retaliate!", category: .death)
                    }
                }
            }
        } else if result.disarmed {
            coordinator.log("  \(result.entityID): Disarmed — moved but can't attack", category: .condition)
        } else if result.focusTarget != nil {
            coordinator.log("  \(result.entityID): Can't reach focus — moved closer", category: .move)
        } else {
            coordinator.log("  \(result.entityID): No focus found", category: .info)
        }

        // Apply element infusions from ability card actions
        applyElementActions(result.abilityActions, coordinator: coordinator, game: gameManager.game)
    }

    /// Infuse elements from monster ability card actions.
    private func applyElementActions(_ actions: [ActionModel], coordinator: BoardCoordinator, game: GameState) {
        for action in actions {
            if action.type == .element, let val = action.value?.stringValue {
                for elemName in val.split(separator: ":") {
                    guard let elemType = ElementType(rawValue: String(elemName)) else { continue }
                    guard let idx = game.elementBoard.firstIndex(where: { $0.type == elemType }) else { continue }

                    let isConsume = action.valueType == .minus || action.valueType == .subtract
                    if isConsume {
                        if game.elementBoard[idx].state == .strong || game.elementBoard[idx].state == .waning {
                            game.elementBoard[idx].state = .consumed
                            coordinator.log("  Consumed \(elemName)", category: .element)
                        }
                    } else {
                        if game.elementBoard[idx].state == .inert || game.elementBoard[idx].state == .consumed {
                            game.elementBoard[idx].state = .new
                            coordinator.log("  Infused \(elemName)", category: .element)
                        }
                    }
                }
            }
            // Check sub-actions too
            for sub in action.subActions ?? [] {
                if sub.type == .element {
                    applyElementActions([sub], coordinator: coordinator, game: game)
                }
            }
        }
    }

    // MARK: - Helpers

    private func parseAbilityModifiers(_ actions: [ActionModel]) -> (move: Int, attack: Int, range: Int, conditions: [ConditionName]) {
        var m = 0, a = 0, r = 0
        var conditions: [ConditionName] = []
        for action in actions {
            switch action.type {
            case .move: m += action.value?.intValue ?? 0
            case .attack: a += action.value?.intValue ?? 0
            case .range: r += action.value?.intValue ?? 0
            case .condition:
                if let name = action.value?.stringValue, let cond = ConditionName(rawValue: name) {
                    conditions.append(cond)
                }
            default: break
            }
        }
        return (m, a, r, conditions)
    }

    private func getDefenderInfo(target: PieceID, gameManager: GameManager) -> (health: Int, shield: Int, retaliate: (value: Int, range: Int)) {
        switch target {
        case .character(let charID):
            if let char = gameManager.game.characters.first(where: { $0.id == charID }) {
                let shield = CombatResolver.totalShield(shield: char.shield, shieldPersistent: char.shieldPersistent)
                let ret = CombatResolver.retaliateInfo(retaliate: char.retaliate, retaliatePersistent: char.retaliatePersistent)
                return (char.health, shield, ret)
            }
        case .summon(let summonID):
            for char in gameManager.game.characters {
                if let summon = char.summons.first(where: { $0.id == summonID }) {
                    let shield = CombatResolver.totalShield(shield: summon.shield, shieldPersistent: summon.shieldPersistent)
                    let ret = CombatResolver.retaliateInfo(retaliate: summon.retaliate, retaliatePersistent: summon.retaliatePersistent)
                    return (summon.health, shield, ret)
                }
            }
        default:
            break
        }
        return (0, 0, (0, 1))
    }

    private func isConditionActive(_ condition: ConditionName, on target: PieceID, gameManager: GameManager) -> Bool {
        switch target {
        case .character(let charID):
            if let char = gameManager.game.characters.first(where: { $0.id == charID }) {
                return char.entityConditions.contains(where: { $0.name == condition && !$0.expired })
            }
        case .summon(let summonID):
            for char in gameManager.game.characters {
                if let summon = char.summons.first(where: { $0.id == summonID }) {
                    return summon.entityConditions.contains(where: { $0.name == condition && !$0.expired })
                }
            }
        default:
            break
        }
        return false
    }

    private func applyDamage(_ damage: Int, to target: PieceID, gameManager: GameManager) {
        switch target {
        case .character(let charID):
            if let char = gameManager.game.characters.first(where: { $0.id == charID }) {
                gameManager.entityManager.changeHealth(char, amount: -damage)
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

    /// Prompt the player for damage mitigation. Returns true if damage was fully negated.
    private func promptDamageMitigation(
        characterID: String,
        damage: Int,
        source: String,
        coordinator: BoardCoordinator,
        gameManager: GameManager
    ) async -> Bool {
        guard let character = gameManager.game.characters.first(where: { $0.id == characterID }) else {
            return false
        }

        // Check if mitigation is even possible
        let canLoseHand = !character.handCards.isEmpty
        let canLoseDiscard = character.discardedCards.count >= 2

        // If no mitigation options, just take the damage
        guard canLoseHand || canLoseDiscard else { return false }

        // Show the prompt and wait for player choice
        let choice = await withCheckedContinuation { (continuation: CheckedContinuation<BoardCoordinator.DamageMitigationChoice, Never>) in
            coordinator.pendingDamage = BoardCoordinator.PendingDamage(
                characterID: characterID,
                damage: damage,
                sourceDescription: source,
                continuation: continuation
            )
        }

        switch choice {
        case .takeDamage:
            return false

        case .loseHandCard(let cardIndex):
            guard cardIndex < character.handCards.count else { return false }
            let cardId = character.handCards.remove(at: cardIndex)
            character.lostCards.append(cardId)
            coordinator.log("  \(characterID): Lost hand card to negate \(damage) damage", category: .damage)
            return true

        case .loseDiscardCards(let indices):
            // Remove in reverse order so indices stay valid
            let sorted = indices.sorted(by: >)
            for idx in sorted {
                guard idx < character.discardedCards.count else { continue }
                let cardId = character.discardedCards.remove(at: idx)
                character.lostCards.append(cardId)
            }
            coordinator.log("  \(characterID): Lost 2 discard cards to negate \(damage) damage", category: .damage)
            return true
        }
    }

    private func markDead(target: PieceID, gameManager: GameManager) {
        switch target {
        case .character(let charID):
            if let char = gameManager.game.characters.first(where: { $0.id == charID }) {
                char.exhausted = true
            }
        case .monster(let name, let standee):
            if let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                entity.dead = true
            }
        case .summon(let summonID):
            for char in gameManager.game.characters {
                if let summon = char.summons.first(where: { $0.id == summonID }) {
                    summon.dead = true
                    break
                }
            }
        default:
            break
        }
    }
}
