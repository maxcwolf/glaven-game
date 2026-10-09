import Foundation

/// Controls the automated execution of escort objective turns.
@Observable
final class EscortTurnController {

    private weak var coordinator: BoardCoordinator?
    private weak var gameManager: GameManager?
    var isExecuting: Bool = false

    /// The board this turn belongs to; a turn that outlives it (the board left or restarted
    /// while it waited) stops without touching the game.
    private let generation: Int
    private var isStale: Bool { coordinator?.isCurrentBoard(generation) != true }

    init(coordinator: BoardCoordinator, gameManager: GameManager) {
        self.coordinator = coordinator
        self.gameManager = gameManager
        self.generation = coordinator.boardGeneration
    }

    /// Execute all living escort entity turns for an objective container.
    @MainActor func executeEscortTurns(for container: GameObjectiveContainer) async {
        guard let coordinator, let gameManager else { return }
        isExecuting = true
        defer { isExecuting = false }

        for entity in container.entities where !entity.dead && entity.health > 0 && !entity.off {
            guard !isStale else { return }
            let pieceID = PieceID.objective(id: entity.number)
            coordinator.setActing(pieceID)
            guard coordinator.isOnBoard(pieceID) else { continue }

            // Start of turn: conditions become active and tick (wound, regenerate).
            gameManager.entityManager.restoreConditions(entity)
            gameManager.entityManager.applyConditionsTurn(entity)
            coordinator.sweepDeadFigures()
            guard !entity.dead, coordinator.isOnBoard(pieceID) else { continue }

            let result = EscortAI.computeTurn(escort: container, entity: entity,
                                              board: coordinator.boardState, gameState: gameManager.game)
            await executeEscortTurn(result: result, container: container, entity: entity, pieceID: pieceID)

            guard !isStale else { return }
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
        let name = coordinator.name(pieceID)

        if result.stunned {
            coordinator.log("\(name) is stunned and loses the turn", category: .condition)
            return
        }

        if result.movementPath.count > 1 {
            let steps = result.movementPath.count - 1
            coordinator.log("\(name) moves \(steps) hex\(steps == 1 ? "" : "es")", category: .move, trace: "to \(result.movementPath.last!)")
            guard await coordinator.moveAlong(pieceID, path: result.movementPath, style: .normal), !isStale else { return }
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
