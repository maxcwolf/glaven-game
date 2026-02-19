import Foundation

/// Controls the automated execution of summon turns before their owning character acts.
@Observable
final class SummonTurnController {

    private weak var coordinator: BoardCoordinator?
    private weak var gameManager: GameManager?
    var isExecuting: Bool = false

    init(coordinator: BoardCoordinator, gameManager: GameManager) {
        self.coordinator = coordinator
        self.gameManager = gameManager
    }

    /// Execute all summon turns for a character.
    /// New summons (state == .new) skip their first turn and transition to .active.
    func executeSummonTurns(for character: GameCharacter) async {
        guard let coordinator = coordinator,
              let gameManager = gameManager else { return }

        isExecuting = true

        let livingSummons = character.summons.filter { !$0.dead && $0.health > 0 }

        for summon in livingSummons {
            // New summons skip their first turn
            if summon.state == .new {
                summon.state = .active
                coordinator.log("  summon(\(summon.id.prefix(8))): New — skips first turn", category: .info)
                continue
            }

            // Apply start-of-turn conditions
            gameManager.entityManager.applyConditionsTurn(summon)

            // Check if summon died from wound damage
            if summon.dead || summon.health <= 0 {
                coordinator.log("  summon(\(summon.id.prefix(8))): Died from conditions", category: .death)
                let pieceID = PieceID.summon(id: summon.id)
                coordinator.boardState.removePiece(pieceID)
                coordinator.boardScene?.removePieceSprite(id: pieceID)
                summon.dead = true
                continue
            }

            // Compute AI turn
            let result = SummonAI.computeTurn(
                summon: summon,
                ownerCharacterID: character.id,
                board: coordinator.boardState,
                gameState: gameManager.game
            )

            // Execute the turn
            await executeSummonTurn(result: result, summon: summon, character: character)

            // Expire end-of-turn conditions
            gameManager.entityManager.expireConditions(summon)

            // Pause between summons
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        isExecuting = false
    }

    // MARK: - Single Summon Turn

    private func executeSummonTurn(result: SummonTurnResult, summon: GameSummon, character: GameCharacter) async {
        guard let coordinator = coordinator,
              let gameManager = gameManager else { return }

        if result.stunned {
            coordinator.log("  \(result.summonPieceID): Stunned — skipped", category: .condition)
            return
        }

        // Movement
        if result.movementPath.count > 1 {
            let path = result.movementPath
            coordinator.log("  \(result.summonPieceID): Move \(path.count - 1) hexes", category: .move)

            await withCheckedContinuation { continuation in
                coordinator.boardScene?.movePiece(
                    id: result.summonPieceID, along: path,
                    offsetCol: coordinator.offsetCol, offsetRow: coordinator.offsetRow
                ) {
                    coordinator.boardState.movePiece(result.summonPieceID, to: path.last!)
                    continuation.resume()
                }
            }

            // Check if summon stepped on a trap
            coordinator.checkForTrap(
                pieceID: result.summonPieceID,
                at: path.last!,
                flying: summon.flying
            )

            // If summon died from trap, skip the rest of this turn
            if summon.dead || summon.health <= 0 { return }
        }

        // Attack
        if let target = result.attackTarget {
            guard !summon.dead else { return }
            guard let targetPos = coordinator.boardState.piecePositions[target],
                  let attackerPos = coordinator.boardState.piecePositions[result.summonPieceID] else { return }

            let (defenderHealth, defenderShield, retInfo) = getDefenderInfo(target: target, gameManager: gameManager)
            let isPoisoned = isConditionActive(.poison, on: target, gameManager: gameManager)
            let hasAdvantage = CombatResolver.hasAdvantage(attacker: summon)
            let isRangedAdjacent = result.attackRange > 1 && attackerPos.isAdjacent(to: targetPos)
            let hasDisadvantage = CombatResolver.hasDisadvantage(attacker: summon, isRangedAdjacent: isRangedAdjacent)

            // Draw from owner's attack modifier deck
            let attackResult = CombatResolver.resolveAttack(
                attacker: result.summonPieceID,
                defender: target,
                baseAttack: result.attackValue,
                advantage: hasAdvantage,
                disadvantage: hasDisadvantage,
                isPoisoned: isPoisoned,
                shield: defenderShield,
                retaliateValue: retInfo.value,
                retaliateRange: retInfo.range,
                attackerDefenderDistance: attackerPos.distance(to: targetPos),
                drawModifier: { gameManager.attackModifierManager.drawCharacterCard(for: character) },
                defenderHealth: defenderHealth
            )

            coordinator.log("  \(result.summonPieceID): Attack \(target) for \(attackResult.damage) damage", category: .attack)

            // Show modifier card popup
            if let mod = attackResult.modifierCard {
                coordinator.lastDrawnModifier = mod
                coordinator.showModifierCard = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak coordinator] in
                    coordinator?.showModifierCard = false
                }
            }

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

            // Retaliate
            if attackResult.retaliateDamage > 0 {
                coordinator.log("  \(result.summonPieceID): Takes \(attackResult.retaliateDamage) retaliate damage", category: .damage)
                gameManager.entityManager.changeHealth(summon, amount: -attackResult.retaliateDamage)
                if summon.health <= 0 {
                    summon.dead = true
                    coordinator.boardState.removePiece(result.summonPieceID)
                    coordinator.boardScene?.removePieceSprite(id: result.summonPieceID)
                    coordinator.log("  \(result.summonPieceID): Killed by retaliate!", category: .death)
                }
            }
        } else if result.focusTarget != nil {
            coordinator.log("  \(result.summonPieceID): Can't reach focus — moved closer", category: .move)
        } else {
            coordinator.log("  \(result.summonPieceID): No focus found", category: .info)
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
