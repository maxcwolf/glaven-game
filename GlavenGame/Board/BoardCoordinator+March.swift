import Foundation

/// Monsters that march instead of moving as their card says (`ScenarioPlacements.March`): the
/// City Guards of Vault of Secrets go "Move 2" for the nearest alarm plate every turn, opening
/// the door in their way, then do whatever else their card has.
extension BoardCoordinator {

    func march(of monsterName: String) -> ScenarioPlacements.March? {
        scenarioData?.placements?.march?[monsterName]
    }

    /// One turn's march for a monster: up to its `move` toward the nearest of its lettered
    /// hexes on the revealed map — or, with none revealed yet, toward the nearest closed door,
    /// which it opens by walking in.
    @MainActor func marchStep(_ pieceID: PieceID) async {
        guard case .monster(let name, _) = pieceID, let march = march(of: name) else { return }
        await walk(pieceID, move: march.move, opensDoors: march.opensDoors == true) {
            march.toward.flatMap { self.boardState.markerHexes[$0] ?? [] }
        }
    }

    /// Walk a monster up to `move` toward the nearest of `goals` (looked up afresh after a door
    /// opens), as near as it can get when they are taken, opening doors in its way if it may.
    /// Returns how many hexes it went.
    @discardableResult
    @MainActor func walk(_ pieceID: PieceID, move: Int, opensDoors: Bool, toward goals: () -> [HexCoord]) async -> Int {
        if isConditionActive(.immobilize, on: pieceID) {
            log("\(self.name(pieceID)) is immobilized and can\u{2019}t move", category: .condition)
            return 0
        }
        let generation = boardGeneration
        var budget = move
        var walked = 0
        // A door opened on the way reveals where it is really going: look again from there.
        for _ in 0..<3 where budget > 0 {
            guard isCurrentBoard(generation), let start = boardState.piecePositions[pieceID] else { return walked }
            let goals = goals()
            if goals.contains(start) { return walked }
            let doors = opensDoors
                ? boardState.doors.filter { !$0.isOpen && !boardState.isLockedDoor($0.coord) && !isDoorBarred(at: $0.coord) }.map(\.coord) : []
            let (enemies, allies) = movementSets(for: pieceID)
            func way(to hex: HexCoord) -> [HexCoord]? {
                Pathfinder.findPath(board: boardState, from: start, to: hex, avoidTraps: true, canOpenDoors: opensDoors,
                                    occupiedByEnemy: enemies, occupiedByAlly: allies)
            }
            func nearest(_ hexes: [HexCoord]) -> [HexCoord]? {
                hexes.sorted().compactMap(way).min { Pathfinder.movementCost(of: $0, board: boardState) < Pathfinder.movementCost(of: $1, board: boardState) }
            }
            // The plates themselves; with a figure on each, as near to one as it can get.
            guard let path = nearest(goals) ?? nearest(goals.flatMap(boardState.neighbors(of:)).filter(isEmptyHex)) ?? nearest(doors), path.count > 1 else {
                log("\(self.name(pieceID)) finds no way forward", category: .move)
                return walked
            }
            let doorIndex = path.firstIndex { hex in boardState.doors.contains { $0.coord == hex && !$0.isOpen } }
            let end = (doorIndex ?? path.count) - 1   // the last hex before a closed door, or the goal
            // How far along its Move takes it, stopping on a free hex.
            var reach = (0...max(0, end)).last { Pathfinder.movementCost(of: Array(path.prefix($0 + 1)), board: boardState) <= budget } ?? 0
            while reach > 0 && boardState.isOccupied(path[reach]) { reach -= 1 }
            if reach > 0 {
                log("\(self.name(pieceID)) marches \(reach) hex\(reach == 1 ? "" : "es")", category: .move, trace: "to \(path[reach])")
                guard await moveAlong(pieceID, path: Array(path.prefix(reach + 1)), style: .normal), isCurrentBoard(generation) else { return walked }
                walked += reach
                budget -= Pathfinder.movementCost(of: Array(path.prefix(reach + 1)), board: boardState)
            }
            // Beside the door with movement to spare: it opens, and the march goes on through it.
            guard let doorIndex, reach == doorIndex - 1, budget >= 1, boardState.piecePositions[pieceID] == path[reach] else { break }
            log("\(self.name(pieceID)) opens the door", category: .door)
            openDoor(at: path[doorIndex])
            guard isCurrentBoard(generation), isOnBoard(pieceID) else { return walked }
            if !boardState.isOccupied(path[doorIndex]) {
                guard await moveAlong(pieceID, path: [path[reach], path[doorIndex]], style: .normal), isCurrentBoard(generation) else { return walked }
                walked += 1
            }
            budget -= 1
        }
        checkVictoryDefeat()
        return walked
    }
}
