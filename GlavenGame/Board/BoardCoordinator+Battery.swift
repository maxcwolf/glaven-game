import Foundation

/// A gun that never acts and is fired by its crew (`ScenarioPlacements.Battery`): the Siege
/// Cannon of Rebel's Stand and the City Archers.
extension BoardCoordinator {

    var scenarioBattery: ScenarioPlacements.Battery? { scenarioData?.placements?.battery }

    /// The gun, while it stands on the board.
    func batteryGun() -> (piece: PieceID, hex: HexCoord)? {
        guard let battery = scenarioBattery else { return nil }
        return boardState.piecePositions.sorted { $0.key < $1.key }.first { piece, _ in
            if case .monster(battery.gun, _) = piece { return true }
            return false
        }.map { ($0.key, $0.value) }
    }

    /// Of the crew's type, the one who serves the gun this round: the nearest to it — of several
    /// as near, the one that acts first (an elite, then the lowest number). Nil for another
    /// monster type, or with no gun on the board.
    func gunner(ofType type: String) -> PieceID? {
        guard let battery = scenarioBattery, battery.crew == type, let gun = batteryGun(),
              let monster = gameManager?.game.monsters.first(where: { $0.name == type }) else { return nil }
        let crew = monster.aliveEntities.compactMap { entity -> (piece: PieceID, far: Int, late: Int)? in
            let piece = PieceID.monster(name: type, standee: entity.number)
            guard let hex = boardState.piecePositions[piece] else { return nil }
            return (piece, boardState.range(from: hex, to: gun.hex) ?? 999, (entity.type == .elite ? 0 : 100) + entity.number)
        }
        return crew.min { ($0.far, $0.late) < ($1.far, $1.late) }?.piece
    }

    /// The hexes beside the gun its crew makes for: any but those before its muzzle.
    func gunnerPosts() -> [HexCoord] {
        guard let battery = scenarioBattery, let gun = batteryGun() else { return [] }
        let line = Set(boardState.markerHexes[battery.line] ?? [])
        return boardState.neighbors(of: gun.hex).filter { boardState.isPassable($0) && !line.contains($0) }.sorted()
    }

    /// Every hex the gun's shot covers: the lettered hexes before it, the row of each on the
    /// side it fires toward, and the tiles written.
    func batteryLine() -> Set<HexCoord> {
        guard let battery = scenarioBattery else { return [] }
        let lettered = boardState.markerHexes[battery.line] ?? []
        let tiles = Set(battery.tiles ?? [])
        return Set(boardState.cells.values.filter { cell in
            tiles.contains(cell.tileRef.lowercased()) || lettered.contains { start in
                cell.coord.row == start.row && (battery.side == "W" ? cell.coord.col <= start.col : cell.coord.col >= start.col)
            }
        }.map(\.coord))
    }

    /// The gunner's turn: up to its Move toward a post beside the gun; beside it, the gun fires.
    @MainActor func serveTheGun(_ pieceID: PieceID) async {
        guard let battery = scenarioBattery, let gun = batteryGun(), let start = boardState.piecePositions[pieceID] else { return }
        let generation = boardGeneration
        let posts = gunnerPosts()
        if !posts.contains(start) {
            if isConditionActive(.immobilize, on: pieceID) {
                log("\(name(pieceID)) is immobilized and can\u{2019}t move", category: .condition)
            } else {
                let (enemies, allies) = movementSets(for: pieceID)
                let ways = posts.filter { boardState.piece(at: $0) == nil }.compactMap {
                    Pathfinder.findPath(board: boardState, from: start, to: $0, avoidTraps: true, canOpenDoors: false,
                                        occupiedByEnemy: enemies, occupiedByAlly: allies)
                }
                if let path = ways.min(by: { Pathfinder.movementCost(of: $0, board: boardState) < Pathfinder.movementCost(of: $1, board: boardState) }),
                   path.count > 1 {
                    var reach = (0..<path.count).last { Pathfinder.movementCost(of: Array(path.prefix($0 + 1)), board: boardState) <= battery.move } ?? 0
                    while reach > 0 && boardState.isOccupied(path[reach]) { reach -= 1 }
                    if reach > 0 {
                        log("\(name(pieceID)) makes for the \(name(gun.piece)): \(reach) hex\(reach == 1 ? "" : "es")",
                            category: .move, trace: "to \(path[reach])")
                        guard await moveAlong(pieceID, path: Array(path.prefix(reach + 1)), style: .normal), isCurrentBoard(generation) else { return }
                    }
                } else {
                    log("\(name(pieceID)) finds no way to the \(name(gun.piece))", category: .move)
                }
            }
        }
        guard isCurrentBoard(generation), isOnBoard(pieceID), isOnBoard(gun.piece), let here = boardState.piecePositions[pieceID],
              boardState.areAdjacent(here, gun.hex), let gameManager,
              let cannon = gameManager.game.monsters.first(where: { $0.name == battery.gun }),
              let entity = entity(for: gun.piece) as? GameMonsterEntity,
              let damage = cannon.stat(for: entity.type)?.attack?.intValue ?? cannon.stat(for: .boss)?.attack?.intValue, damage > 0 else { return }
        // "It fires, causing damage … on all characters and character summons" in its line.
        let line = batteryLine()
        let struck = boardState.piecePositions.keys.sorted().filter { piece in
            switch piece {
            case .character, .summon: return boardState.piecePositions[piece].map(line.contains) ?? false
            default: return false
            }
        }
        log("\(name(pieceID)) fires the \(name(gun.piece)): \(damage) damage along its line", category: .attack)
        boardScene?.play(.trap)
        for piece in struck {
            await sufferDamageWithMitigation(damage, to: piece, source: "The \(name(gun.piece))")
            guard isCurrentBoard(generation), scenarioResult == nil else { return }
        }
    }
}
