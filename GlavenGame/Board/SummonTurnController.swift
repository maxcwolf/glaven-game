import Foundation

/// Controls the automated execution of summon turns. A summon's turn comes directly before its
/// summoner's, summons act in the order they were summoned, and a summon never acts in the
/// round it was summoned (GH p.26).
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
    @MainActor func executeSummonTurns(for character: GameCharacter) async {
        guard let coordinator, let gameManager else { return }
        isExecuting = true
        defer { isExecuting = false }

        for summon in character.summons where !summon.dead {
            let pieceID = PieceID.summon(id: summon.id)
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

            if !summon.dead {
                gameManager.entityManager.expireConditions(summon)
            }
            coordinator.sweepDeadFigures()
            if coordinator.scenarioResult != nil { return }
            if coordinator.turnDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: coordinator.turnDelayNanoseconds) }
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
                                              style: summon.flying ? .fly : .normal) else { return }
        }

        guard let attack = result.attack, !result.attackTargets.isEmpty else { return }
        for target in result.attackTargets {
            guard !summon.dead, coordinator.isOnBoard(pieceID), coordinator.scenarioResult == nil else { return }
            await coordinator.performAttack(
                attacker: pieceID, target: target,
                attack: AttackParameters(value: attack.value, isRanged: attack.isRanged, pierce: attack.pierce,
                                         conditions: attack.conditions, push: attack.push, pull: attack.pull))
        }
    }
}
