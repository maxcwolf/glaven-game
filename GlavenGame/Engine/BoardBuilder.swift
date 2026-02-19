import Foundation

/// Builds a BoardState from VGB scenario map data.
/// Reuses ScenarioMapBuilder's coordinate transform logic.
enum BoardBuilder {

    /// Build the initial board for a scenario, revealing only the starting room.
    /// `playerCount` determines which monsters spawn (2, 3, or 4).
    static func build(from scenario: VGBScenario, playerCount: Int) -> BoardState {
        let board = BoardState()
        let rootTile = scenario.mapTileData

        // Build the starting room
        addRoom(rootTile, to: board, turnAxis: nil, playerCount: playerCount)
        board.visibleRooms.insert(rootTile.ref)

        // Process doors from the starting room (store info but don't reveal child rooms)
        buildDoors(from: rootTile, board: board, turnAxis: nil)

        // Compute bounds
        recomputeBounds(board)

        return board
    }

    /// Reveal a room behind a door. Returns the newly spawned monster positions.
    static func revealRoom(
        door: DoorInfo,
        scenario: VGBScenario,
        board: BoardState,
        playerCount: Int
    ) -> [(PieceID, HexCoord)] {
        // Find the VGBMapTileData for this door's child room
        guard let childTile = findTileData(ref: door.childTileRef, in: scenario.mapTileData) else {
            return []
        }

        let turnAxis = (
            refPoint: (door.refPoint.col, door.refPoint.row),
            origin: (door.origin.col, door.origin.row)
        )

        // Add the child room's cells, overlays, and monsters
        addRoom(childTile, to: board, turnAxis: turnAxis, playerCount: playerCount)
        board.visibleRooms.insert(childTile.ref)

        // Mark the door as open
        if let idx = board.doors.firstIndex(where: { $0.coord == door.coord }) {
            board.doors[idx].isOpen = true
        }

        // Build doors from the child room
        buildDoors(from: childTile, board: board, turnAxis: turnAxis)

        // Recompute bounds
        recomputeBounds(board)

        // Return monster positions that were just placed
        let newMonsters = board.piecePositions.filter { id, _ in
            if case .monster = id { return true }
            return false
        }
        // Filter to only the ones in the newly revealed room's cells
        let roomCells = Set(board.cells.filter { $0.value.tileRef == childTile.ref }.map(\.key))
        return newMonsters.filter { roomCells.contains($0.value) }.map { ($0.key, $0.value) }
    }

    // MARK: - Private

    /// Add a room's cells, overlays, and monsters to the board.
    private static func addRoom(
        _ tileData: VGBMapTileData,
        to board: BoardState,
        turnAxis: (refPoint: (Int, Int), origin: (Int, Int))?,
        playerCount: Int
    ) {
        let refPoint = turnAxis?.refPoint ?? (0, 0)
        let origin = turnAxis?.origin ?? (0, 0)

        // 1. Add hex cells from tile grid
        let grid = TileGrids.grid(for: tileData.ref)
        for (y, row) in grid.enumerated() {
            for (x, exists) in row.enumerated() {
                guard exists else { continue }
                let global = HexMath.normaliseAndRotatePoint(
                    turns: tileData.turns, refPoint: refPoint, origin: origin, tileCoord: (x, y)
                )
                let coord = HexCoord(global.0, global.1)
                if board.cells[coord] == nil {
                    board.cells[coord] = HexCell(
                        coord: coord,
                        tileRef: tileData.ref,
                        passable: true
                    )
                }
            }
        }

        // 2. Process overlays
        for overlay in tileData.overlays {
            let overlayType = parseOverlayType(overlay.ref.type)

            for cell in overlay.cells {
                guard cell.count >= 2 else { continue }
                let global = HexMath.normaliseAndRotatePoint(
                    turns: tileData.turns, refPoint: refPoint, origin: origin, tileCoord: (cell[0], cell[1])
                )
                let coord = HexCoord(global.0, global.1)

                // Ensure cell exists
                if board.cells[coord] == nil {
                    board.cells[coord] = HexCell(
                        coord: coord,
                        tileRef: tileData.ref,
                        passable: true
                    )
                }

                switch overlayType {
                case .obstacle, .wall:
                    board.cells[coord]?.passable = false
                    board.cells[coord]?.overlay = overlayType
                    board.cells[coord]?.overlaySubType = overlay.ref.subType

                case .trap:
                    board.cells[coord]?.overlay = .trap
                    board.cells[coord]?.overlaySubType = overlay.ref.subType
                    board.cells[coord]?.trapDamage = trapDamage(for: overlay.ref.subType)

                case .hazard:
                    board.cells[coord]?.overlay = .hazard
                    board.cells[coord]?.overlaySubType = overlay.ref.subType

                case .difficultTerrain:
                    board.cells[coord]?.overlay = .difficultTerrain
                    board.cells[coord]?.overlaySubType = overlay.ref.subType

                case .treasure:
                    board.cells[coord]?.overlay = .treasure
                    board.cells[coord]?.treasureID = overlay.ref.id
                    board.cells[coord]?.treasureAmount = overlay.ref.amount
                    board.cells[coord]?.overlaySubType = overlay.ref.subType

                case .door:
                    // Doors handled separately
                    break

                case .rift:
                    board.cells[coord]?.overlay = .rift

                case nil:
                    if overlay.ref.type == "starting-location" {
                        board.startingLocations.append(coord)
                    }
                }
            }
        }

        // 3. Place monsters based on player count
        // Sort elites first so they get the lowest standee numbers (Gloomhaven rules)
        let activeMonsters = tileData.monsters.compactMap { monster -> (VGBMonster, String)? in
            let type = monsterTypeForPlayerCount(monster, playerCount: playerCount)
            guard type != "none" else { return nil }
            return (monster, type)
        }
        let sortedMonsters = activeMonsters.sorted { a, b in
            if a.1 == b.1 { return false } // stable sort for same type
            return a.1 == "elite" // elites first
        }

        for (monster, monsterType) in sortedMonsters {
            let global = HexMath.normaliseAndRotatePoint(
                turns: tileData.turns, refPoint: refPoint, origin: origin,
                tileCoord: (monster.initialX, monster.initialY)
            )
            let coord = HexCoord(global.0, global.1)

            // Assign next available standee number (elites get lowest numbers first)
            let standee = nextStandeeNumber(for: monster.monster, board: board)
            let pieceID = PieceID.monster(name: monster.monster, standee: standee)

            // Track elite status for visual distinction
            if monsterType == "elite" {
                board.eliteStandees.insert(pieceID)
            }

            // Try the intended hex, fall back to nearest empty neighbor
            if !board.placePiece(pieceID, at: coord) {
                // Hex is occupied — find nearest passable empty hex
                if let fallback = findNearestEmpty(near: coord, board: board) {
                    board.placePiece(pieceID, at: fallback)
                }
            }
        }
    }

    /// Build door info from a tile's doors (without revealing child rooms).
    private static func buildDoors(
        from tileData: VGBMapTileData,
        board: BoardState,
        turnAxis: (refPoint: (Int, Int), origin: (Int, Int))?
    ) {
        let refPoint = turnAxis?.refPoint ?? (0, 0)
        let origin = turnAxis?.origin ?? (0, 0)

        for door in tileData.doors {
            let r = (door.room1X, door.room1Y)
            let doorGlobal = HexMath.normaliseAndRotatePoint(
                turns: tileData.turns, refPoint: refPoint, origin: origin, tileCoord: r
            )
            let doorCoord = HexCoord(doorGlobal.0, doorGlobal.1)

            // The door hex is the doorRefPoint for the child room transform
            let doorOrigin = (door.room2X, door.room2Y)

            let info = DoorInfo(
                coord: doorCoord,
                childTileRef: door.mapTileData.ref,
                subType: door.subType,
                refPoint: doorCoord,
                origin: HexCoord(doorOrigin.0, doorOrigin.1)
            )
            board.doors.append(info)

            // Mark the door cell
            if board.cells[doorCoord] == nil {
                board.cells[doorCoord] = HexCell(
                    coord: doorCoord,
                    tileRef: tileData.ref,
                    passable: true
                )
            }
            board.cells[doorCoord]?.overlay = .door
            board.cells[doorCoord]?.overlaySubType = door.subType
        }
    }

    /// Recursively find a VGBMapTileData by ref in the scenario tree.
    private static func findTileData(ref: String, in tileData: VGBMapTileData) -> VGBMapTileData? {
        for door in tileData.doors {
            if door.mapTileData.ref == ref {
                return door.mapTileData
            }
            if let found = findTileData(ref: ref, in: door.mapTileData) {
                return found
            }
        }
        return nil
    }

    /// Parse overlay type string to enum.
    private static func parseOverlayType(_ type: String) -> OverlayType? {
        switch type {
        case "obstacle": return .obstacle
        case "trap": return .trap
        case "hazard": return .hazard
        case "difficult-terrain": return .difficultTerrain
        case "treasure": return .treasure
        case "door": return .door
        case "wall": return .wall
        case "rift": return .rift
        default: return nil
        }
    }

    /// Default trap damage by sub-type.
    private static func trapDamage(for subType: String?) -> Int {
        switch subType {
        case "spike": return 3
        case "poison": return 1
        case "damage": return 3
        default: return 2
        }
    }

    /// Determine monster type (normal/elite/none) for a given player count.
    private static func monsterTypeForPlayerCount(_ monster: VGBMonster, playerCount: Int) -> String {
        switch playerCount {
        case 2: return monster.twoPlayer
        case 3: return monster.threePlayer
        case 4: return monster.fourPlayer
        default: return monster.twoPlayer
        }
    }

    /// Find nearest empty, passable hex to a given coordinate (BFS outward).
    private static func findNearestEmpty(near coord: HexCoord, board: BoardState) -> HexCoord? {
        var visited = Set<HexCoord>([coord])
        var queue = coord.neighbors.filter { board.isPassable($0) }
        visited.formUnion(queue)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            if !board.isOccupied(current) && board.isPassable(current) {
                return current
            }
            for neighbor in current.neighbors {
                guard !visited.contains(neighbor), board.isPassable(neighbor) else { continue }
                visited.insert(neighbor)
                queue.append(neighbor)
            }
        }
        return nil
    }

    /// Find next available standee number for a monster type.
    private static func nextStandeeNumber(for monsterName: String, board: BoardState) -> Int {
        let existing = board.piecePositions.keys.compactMap { id -> Int? in
            if case .monster(let name, let standee) = id, name == monsterName {
                return standee
            }
            return nil
        }
        return (existing.max() ?? 0) + 1
    }

    /// Recompute board bounds from all cells.
    private static func recomputeBounds(_ board: BoardState) {
        guard let first = board.cells.keys.first else { return }
        var bounds = MapBounds(minCol: first.col, maxCol: first.col, minRow: first.row, maxRow: first.row)
        for coord in board.cells.keys {
            bounds.expand(col: coord.col, row: coord.row)
        }
        board.bounds = bounds
    }
}
