import Foundation

/// Controls the automated execution of summon turns. A summon's turn comes directly before its
/// summoner's, summons act in the order they were summoned, and a summon never acts in the
/// round it was summoned (GH p.26).
@Observable
final class SummonTurnController {

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

    /// Execute all summon turns for a character.
    @MainActor func executeSummonTurns(for character: GameCharacter) async {
        guard let coordinator, let gameManager else { return }
        isExecuting = true
        defer { isExecuting = false }

        for summon in character.summons where !summon.dead {
            guard !isStale else { return }
            let pieceID = PieceID.summon(id: summon.id)
            coordinator.setActing(pieceID)
            guard coordinator.isOnBoard(pieceID) else { continue }

            if summon.state == .new {
                coordinator.log("\(coordinator.name(pieceID)) was summoned this round and waits", category: .info)
                continue
            }

            // Start of the summon's own turn: its conditions tick (wound, regenerate).
            gameManager.entityManager.restoreConditions(summon)
            gameManager.entityManager.applyConditionsTurn(summon)
            coordinator.sweepDeadFigures()
            guard !summon.dead, coordinator.isOnBoard(pieceID) else { continue }

            let result = SummonAI.computeTurn(summon: summon, ownerCharacterID: character.id,
                                              board: coordinator.boardState, gameState: gameManager.game)
            await executeSummonTurn(result: result, summon: summon, pieceID: pieceID)

            guard !isStale else { return }
            if !summon.dead {
                gameManager.entityManager.expireConditions(summon)
            }
            coordinator.sweepDeadFigures()
            if coordinator.scenarioResult != nil { return }
            await coordinator.beat()
        }
    }

    @MainActor private func executeSummonTurn(result: SummonTurnResult, summon: GameSummon, pieceID: PieceID) async {
        guard let coordinator else { return }

        if result.stunned {
            coordinator.log("\(coordinator.name(pieceID)) is stunned and loses the turn", category: .condition)
            return
        }
        guard result.focusTarget != nil else {
            coordinator.log("\(coordinator.name(pieceID)) finds no enemy to focus on", category: .info)
            return
        }

        if result.movementPath.count > 1 {
            let steps = result.movementPath.count - 1
            coordinator.log("\(coordinator.name(pieceID)) moves \(steps) hex\(steps == 1 ? "" : "es")", category: .move, trace: "to \(result.movementPath.last!)")
            guard await coordinator.moveAlong(pieceID, path: result.movementPath,
                                              style: summon.flying ? .fly : .normal), !isStale else { return }
        }

        guard let attack = result.attack, !result.attackTargets.isEmpty else { return }
        var targets = result.attackTargets
        if let planned = result.movementPath.last, coordinator.boardState.piecePositions[pieceID] != planned {
            // Stopped short of its hex (a bear trap): only what it can reach from where it stands.
            let reachable = coordinator.targetableEnemies(of: pieceID, range: attack.range)
            targets = targets.filter(reachable.contains)
        }
        for target in targets {
            guard !isStale, !summon.dead, coordinator.isOnBoard(pieceID), coordinator.scenarioResult == nil else { return }
            await coordinator.performAttack(
                attacker: pieceID, target: target,
                attack: AttackParameters(value: attack.value, isRanged: attack.isRanged, pierce: attack.pierce,
                                         conditions: attack.conditions, push: attack.push, pull: attack.pull))
        }
    }
}
