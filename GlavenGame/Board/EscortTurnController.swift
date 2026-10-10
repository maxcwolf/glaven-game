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
                                              board: coordinator.boardState, gameState: gameManager.game,
                                              destination: destination(of: container))
            await executeEscortTurn(result: result, container: container, entity: entity, pieceID: pieceID)

            guard !isStale else { return }
            if !entity.dead {
                gameManager.entityManager.expireConditions(entity)
                coordinator.noteEscortArrival(pieceID)
            }
            coordinator.sweepDeadFigures()
            if coordinator.scenarioResult != nil { return }
            await coordinator.beat()
        }
    }

    /// Where the escort's move heads when its text names a lettered hex — "Move 2 towards the
    /// altar (b)" — and the letter is on the revealed map.
    func destination(of container: GameObjectiveContainer) -> Set<HexCoord> {
        guard let coordinator, let store = gameManager?.editionStore else { return [] }
        let notes = container.escortActions.filter { $0.type == .move }
            .flatMap { $0.subActions ?? [] }.filter { $0.type == .custom }.compactMap { $0.value?.stringValue }
        var hexes: Set<HexCoord> = []
        for note in notes {
            let key = note.trimmingCharacters(in: CharacterSet(charactersIn: "%")).replacingOccurrences(of: "data.", with: "")
            let text = store.resolveLabel(key: key, edition: container.edition) ?? note
            for match in text.matches(of: #/%game\.mapMarker\.([a-z0-9]+)%/#) {
                let marker = String(match.1)
                let revealed = coordinator.boardState.markerHexes[marker] ?? []
                hexes.formUnion(revealed.isEmpty ? doorsToward(marker) : revealed)
            }
        }
        return hexes
    }

    /// The letter is in a room not yet revealed: the closed doors on the way there (walking
    /// into one opens it), or failing that the closed door nearest to it.
    private func doorsToward(_ marker: String) -> [HexCoord] {
        guard let coordinator, let scenario = coordinator.scenarioData else { return [] }
        let closed = coordinator.boardState.doors.filter {
            !$0.isOpen && !coordinator.isDoorBarred(at: $0.coord) && !coordinator.boardState.isLockedDoor($0.coord)
        }
        let sites = BoardBuilder.markerSites(marker, in: scenario)
        let onTheWay = closed.filter { door in
            guard let path = door.childPath else { return false }
            return sites.contains { $0.path.starts(with: path) }
        }
        if !onTheWay.isEmpty { return onTheWay.map(\.coord) }
        guard let site = sites.first else { return [] }
        return closed.min { $0.coord.distance(to: site.coord) < $1.coord.distance(to: site.coord) }.map { [$0.coord] } ?? []
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
