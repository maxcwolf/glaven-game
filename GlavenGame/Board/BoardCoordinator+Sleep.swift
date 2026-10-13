import Foundation

/// Monsters set up asleep (`ScenarioPlacements.asleep`): the Spitting Drakes of the Windswept
/// Highlands. Unlike an inactive monster a sleeper is there to be attacked — which wakes it.
extension BoardCoordinator {

    /// A monster has been put on the board: one of the map, of a type the scenario sets up asleep,
    /// sleeps; one that arrives later (and whoever takes a dead sleeper's standee) is awake.
    func setUpAsleep(_ piece: PieceID, ofTheMap: Bool) {
        if ofTheMap, case .monster(let type, _) = piece, scenarioData?.placements?.asleep?.contains(type) == true {
            boardState.asleep.insert(piece)
        } else {
            boardState.asleep.remove(piece)
        }
    }

    func isAsleep(_ piece: PieceID) -> Bool {
        boardState.asleep.contains(piece) && boardState.piecePositions[piece] != nil
    }

    /// The sleeper wakes: "follow the rules as if it has just been spawned" — it acts this round,
    /// with its type or, that turn gone by, after the turn it woke in.
    func wake(_ piece: PieceID) {
        guard boardState.asleep.contains(piece), case .monster(let type, let standee) = piece else { return }
        boardState.asleep.remove(piece)
        guard isOnBoard(piece), let gameManager, let monster = gameManager.game.monsters.first(where: { $0.name == type }) else { return }
        log("\(name(piece)) wakes up", category: .info)
        if isMidRound {
            if !monster.abilityDrawn { gameManager.monsterManager.drawAbility(for: monster) }
            pendingRevealedStandees[type, default: []].insert(standee)
        }
        syncPieceVisuals()
    }

    /// A character or a character's summon has ended a movement: the sleepers beside it wake.
    func wakeSleepers(beside mover: PieceID) {
        guard !boardState.asleep.isEmpty, let here = boardState.piecePositions[mover] else { return }
        switch mover {
        case .character, .summon: break
        default: return
        }
        for sleeper in boardState.asleep.sorted() {
            guard let hex = boardState.piecePositions[sleeper], boardState.areAdjacent(here, hex) else { continue }
            wake(sleeper)
        }
    }
}
