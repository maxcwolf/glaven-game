import Foundation

/// A boss that sits on all the hexes of an obstacle and flies from one to the next
/// (`ScenarioPlacements.Perch`): the Elder Drake of the Scorched Summit and its Zephyrs.
extension BoardCoordinator {

    var scenarioPerch: ScenarioPlacements.Perch? { scenarioData?.placements?.perch }

    /// The boss, while it is on the board.
    func perchedBoss() -> PieceID? {
        guard let perch = scenarioPerch else { return nil }
        return boardState.piecePositions.keys.sorted().first { if case .monster(perch.monster, _) = $0 { return true }; return false }
    }

    private func settle(_ piece: PieceID, on letter: String) -> Bool {
        let hexes = (boardState.markerHexes[letter] ?? []).sorted()
        guard let first = hexes.first else { return false }
        boardState.movePiece(piece, to: first)
        boardState.bodies[piece] = hexes
        return true
    }

    /// A monster has been put on the board: the boss takes the perch it starts on.
    func takeItsPerch(_ piece: PieceID) {
        guard let perch = scenarioPerch, case .monster(perch.monster, _) = piece, boardState.bodies[piece] == nil else { return }
        if settle(piece, on: perch.start) { syncPieceVisuals() }
    }

    /// The letter of the perch the boss is on.
    func perchLetter(of piece: PieceID) -> String? {
        guard let perch = scenarioPerch, let here = boardState.piecePositions[piece] else { return nil }
        return perch.cycle.first { (boardState.markerHexes[$0] ?? []).contains(here) }
    }

    /// "The Elder Drake can use any of its hexes to determine what it can target": as its turn
    /// starts it is taken to stand on the hex of its perch nearest an enemy it can see.
    func faceItsEnemies(_ piece: PieceID) {
        guard let body = boardState.bodies[piece], body.count > 1 else { return }
        let enemies = boardState.piecePositions.filter { areEnemies(piece, $0.key) && !isConditionActive(.invisible, on: $0.key) }.map(\.value)
        func nearest(_ hex: HexCoord) -> (Int, Int) {
            let seen = enemies.filter { LineOfSight.hasLOS(from: hex, to: $0, board: boardState) }
            return (seen.isEmpty ? 1 : 0, (seen.isEmpty ? enemies : seen).compactMap { boardState.range(from: hex, to: $0) }.min() ?? 99)
        }
        guard let best = body.sorted().min(by: { nearest($0) < nearest($1) }), best != boardState.piecePositions[piece] else { return }
        boardState.movePiece(piece, to: best)
        syncPieceVisuals()
    }

    /// The boss's special: it summons its Zephyrs, "then flies to the next perch".
    @MainActor func flyToNextPerch(_ piece: PieceID) async {
        guard let perch = scenarioPerch, let from = boardState.piecePositions[piece] else { return }
        let generation = boardGeneration
        if let summoned = perch.summons, let body = boardState.bodies[piece] {
            for _ in 0..<max(1, perch.count ?? 1) {
                // Beside it: the nearest empty hex to its perch.
                guard let beside = body.sorted().compactMap({ nearestEmptyHex(to: $0) })
                    .min(by: { (boardState.range(from: from, to: $0) ?? 99, $0) < (boardState.range(from: from, to: $1) ?? 99, $1) }),
                      let zephyr = spawnMonster(name: summoned, type: .normal, at: beside, origin: .summoned) else {
                    log("\(name(piece)) has no \(GameText.monsterName(summoned)) left to summon", category: .info)
                    break
                }
                log("\(name(piece)) summons \(name(zephyr))", category: .info)
            }
        }
        let here = perch.cycle.firstIndex { (boardState.markerHexes[$0] ?? []).contains(from) }
        let next = perch.cycle[((here ?? -1) + 1) % perch.cycle.count]
        guard let landing = (boardState.markerHexes[next] ?? []).sorted().first else { return }
        log("\(name(piece)) flies to the next perch (\(next))", category: .move, trace: "to \(landing)")
        await animateMove(piece, along: [from, landing], as: .teleport)
        guard isCurrentBoard(generation), isOnBoard(piece) else { return }
        _ = settle(piece, on: next)
        syncPieceVisuals()
    }

    // MARK: - Zephyrs

    /// Monsters nothing affects at all — no attack, no damage, no condition, no push — and that
    /// no one focuses on: a perched boss's summons.
    func isIntangible(_ piece: PieceID) -> Bool {
        guard let summoned = scenarioPerch?.summons, case .monster(summoned, _) = piece else { return false }
        return true
    }
}
