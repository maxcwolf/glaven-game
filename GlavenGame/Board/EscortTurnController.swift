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
    @MainActor func executeEscortTurns(for container: GameObjectiveContainer) async {
        guard let coordinator, let gameManager else { return }
        isExecuting = true
        defer { isExecuting = false }

        for entity in container.entities where !entity.dead && entity.health > 0 && !entity.off {
            let pieceID = PieceID.objective(id: entity.number)
            guard coordinator.isOnBoard(pieceID) else { continue }

            // Start of turn: conditions become active and tick (wound, regenerate).
            gameManager.entityManager.restoreConditions(entity)
            gameManager.entityManager.applyConditionsTurn(entity)
            coordinator.sweepDeadFigures()
            guard !entity.dead, coordinator.isOnBoard(pieceID) else { continue }

            let result = EscortAI.computeTurn(escort: container, entity: entity,
                                              board: coordinator.boardState, gameState: gameManager.game)
            await executeEscortTurn(result: result, container: container, entity: entity, pieceID: pieceID)

            if !entity.dead {
                gameManager.entityManager.expireConditions(entity)
            }
            coordinator.sweepDeadFigures()
            if coordinator.scenarioResult != nil { return }
            if coordinator.turnDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: coordinator.turnDelayNanoseconds) }
        }
    }

    @MainActor private func executeEscortTurn(result: EscortTurnResult, container: GameObjectiveContainer,
                                   entity: GameObjectiveEntity, pieceID: PieceID) async {
        guard let coordinator, let gameManager else { return }
        let name = "\(container.name)#\(entity.number)"

        if result.stunned {
            coordinator.log("  \(name): Stunned — skipped", category: .condition)
            return
        }

        if result.movementPath.count > 1 {
            coordinator.log("  \(name): Move \(result.movementPath.count - 1)", category: .move)
            guard await coordinator.moveAlong(pieceID, path: result.movementPath, style: .normal) else { return }
        }

        guard let attack = result.attack, let target = result.attackTarget else { return }
        let am = gameManager.attackModifierManager
        // Escorts draw from the ally deck or the monster deck as the scenario specifies.
        let draw: () -> AttackModifier? = container.useAllyDeck ? { am.drawAllyCard() } : { am.drawMonsterCard() }
        await coordinator.performAttack(
            attacker: pieceID, target: target,
            attack: AttackParameters(value: attack.value, isRanged: attack.isRanged, pierce: attack.pierce,
                                     conditions: attack.conditions, push: attack.push, pull: attack.pull),
            drawCard: draw)
    }
}
