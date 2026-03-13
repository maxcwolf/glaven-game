import Foundation

/// Controls the automated execution of escort objective turns.
@Observable
final class EscortTurnController {

    private weak var coordinator: BoardCoordinator?
    private weak var gameManager: GameManager?
    var isExecuting: Bool = false

    init(coordinator: BoardCoordinator, gameManager: GameManager) {
        self.coordinator = coordinator
        self.gameManager = gameManager
    }

    /// Execute all living escort entity turns for an objective container.
    func executeEscortTurns(for container: GameObjectiveContainer) async {
        guard let coordinator = coordinator,
              let gameManager = gameManager else { return }

        isExecuting = true

        let livingEntities = container.entities.filter { !$0.dead && $0.health > 0 && !$0.off }

        for entity in livingEntities {
            // Apply start-of-turn conditions (wound, regenerate)
            gameManager.entityManager.applyConditionsTurn(entity)

            // Check if escort died from wound damage
            if entity.dead || entity.health <= 0 {
                coordinator.log("  \(container.name)#\(entity.number): Died from conditions", category: .death)
                let pieceID = PieceID.objective(id: entity.number)
                coordinator.boardState.removePiece(pieceID)
                coordinator.boardScene?.removePieceSprite(id: pieceID)
                entity.dead = true
                continue
            }

            // Only compute AI turn if the escort has actions
            if container.hasEscortActions {
                let result = EscortAI.computeTurn(
                    escort: container,
                    entity: entity,
                    board: coordinator.boardState,
                    gameState: gameManager.game
                )

                await executeEscortTurn(result: result, container: container, entity: entity)
            }

            // Expire end-of-turn conditions
            gameManager.entityManager.expireConditions(entity)

            // Pause between entities
            if livingEntities.count > 1 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }

        isExecuting = false
    }

    // MARK: - Single Escort Turn

    private func executeEscortTurn(
        result: EscortTurnResult,
        container: GameObjectiveContainer,
        entity: GameObjectiveEntity
    ) async {
        guard let coordinator = coordinator,
              let gameManager = gameManager else { return }

        if result.stunned {
            coordinator.log("  \(container.name)#\(entity.number): Stunned — skipped", category: .condition)
            return
        }

        // Movement
        if result.movementPath.count > 1 {
            let path = result.movementPath
            coordinator.log("  \(container.name)#\(entity.number): Move \(path.count - 1) hexes", category: .move)

            await withCheckedContinuation { continuation in
                coordinator.boardScene?.movePiece(
                    id: result.escortPieceID, along: path,
                    offsetCol: coordinator.offsetCol, offsetRow: coordinator.offsetRow
                ) {
                    coordinator.boardState.movePiece(result.escortPieceID, to: path.last!)
                    continuation.resume()
                }
            }

            // Check for traps (escorts are not flying)
            coordinator.checkForTrap(
                pieceID: result.escortPieceID,
                at: path.last!,
                flying: false
            )

            // Check for hazardous terrain
            coordinator.checkForHazard(
                pieceID: result.escortPieceID,
                at: path.last!,
                flying: false
            )

            // If escort died from trap/hazard, stop
            if entity.dead || entity.health <= 0 { return }
        }

        // Attack
        if let target = result.attackTarget {
            guard !entity.dead else { return }
            guard let targetPos = coordinator.boardState.piecePositions[target],
                  let attackerPos = coordinator.boardState.piecePositions[result.escortPieceID] else { return }

            let (defenderHealth, defenderShield, retInfo) = getDefenderInfo(target: target, gameManager: gameManager)
            let isPoisoned = isConditionActive(.poison, on: target, gameManager: gameManager)
            let isRangedAdjacent = result.attackRange > 1 && attackerPos.isAdjacent(to: targetPos)
            // Escorts don't have conditions that give advantage/disadvantage typically,
            // but check entity conditions for correctness
            let hasAdvantage = entity.entityConditions.contains(where: { $0.name == .strengthen && !$0.expired })
            let hasDisadvantage = entity.entityConditions.contains(where: { $0.name == .muddle && !$0.expired }) || isRangedAdjacent

            // Draw from ally deck or monster deck
            let drawCard: () -> AttackModifier? = {
                if container.useAllyDeck {
                    return gameManager.attackModifierManager.drawAllyCard()
                } else {
                    return gameManager.attackModifierManager.drawMonsterCard()
                }
            }

            let preDrawnCards = await coordinator.performModifierDraw(
                attacker: result.escortPieceID,
                defender: target,
                baseAttack: result.attackValue,
                advantage: hasAdvantage,
                disadvantage: hasDisadvantage,
                drawCard: drawCard
            )

            let attackResult = CombatResolver.resolveAttack(
                attacker: result.escortPieceID,
                defender: target,
                baseAttack: result.attackValue,
                advantage: hasAdvantage,
                disadvantage: hasDisadvantage,
                isPoisoned: isPoisoned,
                shield: defenderShield,
                retaliateValue: retInfo.value,
                retaliateRange: retInfo.range,
                attackerDefenderDistance: attackerPos.distance(to: targetPos),
                preDrawnCards: preDrawnCards,
                drawModifier: { nil },
                defenderHealth: defenderHealth
            )

            let breakdown = CombatResolver.damageBreakdown(
                base: result.attackValue, isPoisoned: isPoisoned,
                preDrawnCards: preDrawnCards, shield: defenderShield,
                isMiss: attackResult.isMiss, finalDamage: attackResult.damage)
            coordinator.log("  \(container.name)#\(entity.number) → \(target): \(breakdown)", category: .attack)

            // Apply damage
            if attackResult.damage > 0 {
                coordinator.boardScene?.pieceDamage(id: target, amount: attackResult.damage)
                applyDamage(attackResult.damage, to: target, gameManager: gameManager)
            }

            // Apply conditions to target
            for condition in attackResult.appliedConditions {
                applyConditionToTarget(condition, target: target, gameManager: gameManager)
                coordinator.log("  \(target): \(condition.rawValue) applied", category: .condition)
            }

            // Check if target was killed
            if attackResult.killed || isTargetDead(target, gameManager: gameManager) {
                coordinator.log("  \(target): Killed!", category: .death)
                coordinator.boardState.removePiece(target)
                coordinator.boardScene?.removePieceSprite(id: target)
                markDead(target: target, gameManager: gameManager)
            }

            // Retaliate damage back to escort
            if attackResult.retaliateDamage > 0 {
                coordinator.log("  \(container.name)#\(entity.number): Takes \(attackResult.retaliateDamage) retaliate damage", category: .damage)
                gameManager.entityManager.changeHealth(entity, amount: -attackResult.retaliateDamage)
                if entity.health <= 0 {
                    entity.dead = true
                    coordinator.boardState.removePiece(result.escortPieceID)
                    coordinator.boardScene?.removePieceSprite(id: result.escortPieceID)
                    coordinator.log("  \(container.name)#\(entity.number): Killed by retaliate!", category: .death)
                }
            }
        } else if result.focusTarget != nil {
            coordinator.log("  \(container.name)#\(entity.number): Can't reach focus — moved closer", category: .move)
        } else {
            coordinator.log("  \(container.name)#\(entity.number): No focus found", category: .info)
        }
    }

    // MARK: - Helpers

    private func getDefenderInfo(target: PieceID, gameManager: GameManager) -> (health: Int, shield: Int, retaliate: (value: Int, range: Int)) {
        switch target {
        case .monster(let name, let standee):
            if let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                let shield = CombatResolver.totalShield(shield: entity.shield, shieldPersistent: entity.shieldPersistent)
                let ret = CombatResolver.retaliateInfo(retaliate: entity.retaliate, retaliatePersistent: entity.retaliatePersistent)
                return (entity.health, shield, ret)
            }
        default:
            break
        }
        return (0, 0, (0, 1))
    }

    private func isConditionActive(_ condition: ConditionName, on target: PieceID, gameManager: GameManager) -> Bool {
        switch target {
        case .monster(let name, let standee):
            if let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                return entity.entityConditions.contains(where: { $0.name == condition && !$0.expired })
            }
        default:
            break
        }
        return false
    }

    private func applyDamage(_ damage: Int, to target: PieceID, gameManager: GameManager) {
        switch target {
        case .monster(let name, let standee):
            if let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                gameManager.entityManager.changeHealth(entity, amount: -damage)
            }
        default:
            break
        }
    }

    private func applyConditionToTarget(_ condition: ConditionName, target: PieceID, gameManager: GameManager) {
        switch target {
        case .monster(let name, let standee):
            if let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                gameManager.entityManager.addCondition(condition, to: entity)
            }
        default:
            break
        }
    }

    private func isTargetDead(_ target: PieceID, gameManager: GameManager) -> Bool {
        switch target {
        case .monster(let name, let standee):
            if let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                return entity.health <= 0
            }
        default:
            break
        }
        return false
    }

    private func markDead(target: PieceID, gameManager: GameManager) {
        switch target {
        case .monster(let name, let standee):
            if let monster = gameManager.game.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }) {
                entity.dead = true
            }
        default:
            break
        }
    }
}
