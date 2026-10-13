import Foundation

/// Monsters that carry an objective somewhere instead of acting (`ScenarioPlacements.Carry`):
/// the two Cultists of the Sacrifice Pit and their victim.
extension BoardCoordinator {

    var scenarioCarry: ScenarioPlacements.Carry? { scenarioData?.placements?.carry }

    func isCarrier(type name: String) -> Bool { scenarioCarry?.carriers == name }

    /// The carriers on the board, in piece order.
    func carriers() -> [PieceID] {
        guard let carry = scenarioCarry else { return [] }
        return boardState.piecePositions.keys.filter { if case .monster(carry.carriers, _) = $0 { return true }; return false }.sorted()
    }

    /// What is carried, while it stands on the board.
    func carriedVictim() -> (piece: PieceID, hex: HexCoord)? {
        guard let carry = scenarioCarry,
              let number = boardState.objectiveSites.filter({ $0.value.objective == carry.objective }).keys.sorted().first,
              let hex = boardState.piecePositions[.objective(id: number)] else { return nil }
        return (.objective(id: number), hex)
    }

    private func isBesideTheAltar(_ hex: HexCoord) -> Bool {
        guard let carry = scenarioCarry else { return false }
        return (boardState.markerHexes[carry.altar] ?? []).contains { boardState.areAdjacent(hex, $0) }
    }

    /// "If a Cultist starts its turn adjacent to the altars, and the victim is also adjacent to
    /// the altars, the victim is sacrificed."
    func sacrificeIsMade(by carrier: PieceID) -> Bool {
        guard let here = boardState.piecePositions[carrier], let victim = carriedVictim() else { return false }
        return isBesideTheAltar(here) && isBesideTheAltar(victim.hex)
    }

    /// One carrier's turn: the sacrifice, if all is in place; else "Move+0" — to the victim's
    /// side first, then with it toward the lettered hexes before the altar (or, those taken,
    /// the nearest hex beside the altar), opening the doors in its way.
    @MainActor func carrierStep(_ pieceID: PieceID, entity: GameMonsterEntity, monster: GameMonster) async {
        guard let carry = scenarioCarry else { return }
        if sacrificeIsMade(by: pieceID) {
            guard pendingResult == nil else { return }
            pendingResult = .defeat
            endReason = .ruleLost(carry.lost)
            log("\(name(pieceID)) makes the sacrifice: the scenario is lost", category: .death)
            return
        }
        guard let victim = carriedVictim(), let here = boardState.piecePositions[pieceID] else { return }
        let move = max(0, (monster.stat(for: entity.type)?.movement?.intValue ?? 0) + scenarioMoveBonus(of: pieceID))
        let carrying = boardState.areAdjacent(here, victim.hex)
        let steps = await walk(pieceID, move: move, opensDoors: true) {
            if !carrying {
                return self.boardState.neighbors(of: victim.hex).filter { self.boardState.isPassable($0) }
            }
            let free = { (hex: HexCoord) in self.boardState.piece(at: hex) == nil || self.boardState.piece(at: hex) == pieceID }
            let lettered = (self.boardState.markerHexes[carry.toward] ?? []).filter(free)
            if !lettered.isEmpty { return lettered }
            return (self.boardState.markerHexes[carry.altar] ?? []).flatMap { self.boardState.neighbors(of: $0) }
                .filter { self.boardState.isPassable($0) && free($0) }
        }
        carrierSteps[pieceID] = (steps, carrying)
    }

    /// "After the cultists move, the victim … will then move the same number of hexes to be
    /// adjacent to them, preferably to the left of the right Cultist and to the right of the
    /// left Cultist": as far as the carrier that had hold of it went, to the hex beside the most
    /// of them it can reach.
    @MainActor func carriedFollows() async {
        let went = carrierSteps
        carrierSteps = [:]
        guard let victim = carriedVictim(), scenarioResult == nil else { return }
        let holding = went.filter { $0.value.carrying && boardState.piecePositions[$0.key] != nil }
        guard let reach = holding.values.map(\.steps).max(), reach > 0 else { return }
        let bearers = carriers().compactMap { boardState.piecePositions[$0] }
        func held(_ hex: HexCoord) -> Int { bearers.filter { boardState.areAdjacent(hex, $0) }.count }
        let others = Set(boardState.piecePositions.filter { $0.key != victim.piece }.values)
        let places = Set(bearers.flatMap { boardState.neighbors(of: $0) }).union([victim.hex])
            .filter { boardState.isPassable($0) && !others.contains($0) }
        var best: (path: [HexCoord], held: Int)?
        for place in places.sorted() {
            let path = place == victim.hex ? [place] : Pathfinder.findPath(board: boardState, from: victim.hex, to: place, avoidTraps: false,
                                                                           canOpenDoors: false, occupiedByEnemy: [], occupiedByAlly: others)
            guard var path else { continue }
            // No further than it was carried; short of the place, as far along the way as that.
            if path.count - 1 > reach {
                path = Array(path.prefix(reach + 1))
                while path.count > 1, others.contains(path[path.count - 1]) { path.removeLast() }
            }
            let grip = held(path[path.count - 1])
            if best == nil || (grip, -path.count) > (best!.held, -best!.path.count) { best = (path, grip) }
        }
        guard let path = best?.path, path.count > 1, let destination = path.last else { return }
        let generation = boardGeneration
        log("\(name(victim.piece)) is carried \(path.count - 1) hex\(path.count == 2 ? "" : "es")", category: .move, trace: "to \(destination)")
        await animateMove(victim.piece, along: path)
        guard isCurrentBoard(generation), boardState.piecePositions[victim.piece] != nil else { return }
        boardState.movePiece(victim.piece, to: destination)
        if case .objective(let number) = victim.piece, let site = boardState.objectiveSites[number] {
            boardState.objectiveSites[number] = ObjectiveSlot(objective: site.objective, coord: destination, cells: [destination])
        }
        syncPieceVisuals()
    }
}
