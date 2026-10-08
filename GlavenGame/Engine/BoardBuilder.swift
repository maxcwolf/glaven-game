import Foundation

/// A monster position from the map data. Which monsters appear — and whether they are normal,
/// elite or boss — comes from the scenario data; the map supplies where they stand.
struct MonsterSlot: Equatable {
    let name: String
    let coord: HexCoord
    /// Map-data type per character count (2/3/4): "normal", "elite" or "none".
    let typeByPlayerCount: [Int: String]

    func type(forPlayerCount count: Int) -> String {
        typeByPlayerCount[min(4, max(2, count))] ?? "none"
    }
}

/// Builds a BoardState from VGB scenario map data.
/// Reuses ScenarioMapBuilder's coordinate transform logic.
enum BoardBuilder {

    /// Result of revealing part of the map.
    struct Reveal {
        /// Monster positions in the revealed tiles.
        var slots: [MonsterSlot] = []
        /// Tile refs revealed (a room can span several tiles joined by corridors).
        var tileRefs: [String] = []
        /// Cells that existed before this reveal — their overlays are never re-applied (a sprung
        /// trap or looted treasure stays gone when a room is entered from another door).
        var preexisting: Set<HexCoord> = []
        /// Tree paths already added during this reveal.
        var visited: Set<[Int]> = []
    }

    /// Placement of a tile: its path in the map tree and the transform that puts it on the board.
    typealias TurnAxis = (refPoint: (Int, Int), origin: (Int, Int))

    /// Build the initial board for a scenario, revealing only the starting room.
    /// `playerCount` determines which monsters spawn (2, 3, or 4).
    static func build(from scenario: VGBScenario, playerCount: Int) -> BoardState {
        let (board, reveal) = buildStartingRoom(from: scenario)
        place(reveal.slots, on: board, playerCount: playerCount)
        return board
    }

    /// Build the board with the starting room revealed but no monsters placed; returns the
    /// starting room's monster slots for the caller to fill. The starting room is the tile named by
    /// the scenario's initial room (falling back to the tile holding the starting locations, then
    /// the map's root tile).
    static func buildStartingRoom(from scenario: VGBScenario, initialRoomRefs: [String] = []) -> (BoardState, Reveal) {
        let board = BoardState()
        var reveal = Reveal()
        let start = startingPlacement(in: scenario.mapTileData, initialRoomRefs: initialRoomRefs)
        addRoom(start.tile, path: start.path, root: scenario.mapTileData, to: board,
                turnAxis: start.axis, reveal: &reveal)
        // Some scenarios split the party between separate starting tiles (e.g. GH 50, 58, 85: the
        // scenario's first room covers both). Every tile with starting hexes is revealed at setup.
        for placement in findPlacements(in: scenario.mapTileData)
        where hasStartingLocations(placement.tile) && !reveal.visited.contains(placement.path) {
            addRoom(placement.tile, path: placement.path, root: scenario.mapTileData, to: board,
                    turnAxis: placement.axis, reveal: &reveal)
        }
        recomputeBounds(board)
        return (board, reveal)
    }

    private static func hasStartingLocations(_ tile: VGBMapTileData) -> Bool {
        tile.overlays.contains { $0.ref.type == "starting-location" }
    }

    /// Reveal a room behind a door. Returns the newly spawned monster positions.
    static func revealRoom(
        door: DoorInfo,
        scenario: VGBScenario,
        board: BoardState,
        playerCount: Int
    ) -> [(PieceID, HexCoord)] {
        let before = Set(board.piecePositions.keys)
        guard let reveal = revealRoomSlots(door: door, scenario: scenario, board: board) else { return [] }
        place(reveal.slots, on: board, playerCount: playerCount)
        return board.piecePositions.filter { !before.contains($0.key) }.map { ($0.key, $0.value) }
    }

    /// Reveal the room behind a door (cells, overlays, onward doors) without placing monsters;
    /// returns the room's monster slots. Nil if the door's room can't be found.
    static func revealRoomSlots(door: DoorInfo, scenario: VGBScenario, board: BoardState) -> Reveal? {
        let root = scenario.mapTileData
        let path: [Int]
        let tile: VGBMapTileData
        if let childPath = door.childPath, let located = self.tile(at: childPath, in: root) {
            path = childPath
            tile = located
        } else if let found = findPlacements(in: root).first(where: { $0.tile.ref == door.childTileRef }) {
            path = found.path
            tile = found.tile
        } else {
            return nil
        }

        let isRoot = path.isEmpty
        let turnAxis: TurnAxis? = isRoot && door.refPoint == HexCoord(0, 0) && door.origin == HexCoord(0, 0)
            ? nil
            : (refPoint: (door.refPoint.col, door.refPoint.row), origin: (door.origin.col, door.origin.row))
        var reveal = Reveal(preexisting: Set(board.cells.keys))
        addRoom(tile, path: path, root: root, to: board, turnAxis: turnAxis, reveal: &reveal)

        if let idx = board.doors.firstIndex(where: { $0.coord == door.coord }) {
            board.doors[idx].isOpen = true
        }
        recomputeBounds(board)
        return reveal
    }

    /// Place map-data monsters for the given player count (used when the scenario data has no
    /// room list to take monsters from).
    static func place(_ slots: [MonsterSlot], on board: BoardState, playerCount: Int) {
        let active = slots.compactMap { slot -> (MonsterSlot, String)? in
            let type = slot.type(forPlayerCount: playerCount)
            return type == "none" ? nil : (slot, type)
        }
        // Elites first so they get the lowest standee numbers.
        let sorted = active.sorted { a, b in a.1 == b.1 ? false : a.1 == "elite" }
        for (slot, type) in sorted {
            let standee = nextStandeeNumber(for: slot.name, board: board)
            let pieceID = PieceID.monster(name: slot.name, standee: standee)
            if type == "elite" { board.eliteStandees.insert(pieceID) }
            if !board.placePiece(pieceID, at: slot.coord), let fallback = findNearestEmpty(near: slot.coord, board: board) {
                board.placePiece(pieceID, at: fallback)
            }
        }
    }

    // MARK: - Map tree

    /// Every tile placement in the map tree (depth first), with its path and transform.
    static func findPlacements(in root: VGBMapTileData) -> [(path: [Int], tile: VGBMapTileData, axis: TurnAxis?)] {
        var result: [(path: [Int], tile: VGBMapTileData, axis: TurnAxis?)] = []
        func walk(_ tile: VGBMapTileData, path: [Int], axis: TurnAxis?) {
            result.append((path, tile, axis))
            for (index, door) in tile.doors.enumerated() {
                walk(door.mapTileData, path: path + [index], axis: childAxis(of: door, in: tile, parentAxis: axis))
            }
        }
        walk(root, path: [], axis: nil)
        return result
    }

    /// The tile at a door-index path from the root.
    static func tile(at path: [Int], in root: VGBMapTileData) -> VGBMapTileData? {
        var tile = root
        for index in path {
            guard index < tile.doors.count else { return nil }
            tile = tile.doors[index].mapTileData
        }
        return tile
    }

    /// Transform of the tile behind `door`, given its parent's transform.
    private static func childAxis(of door: VGBDoor, in parent: VGBMapTileData, parentAxis: TurnAxis?) -> TurnAxis {
        let doorCoord = doorCoordinate(door, in: parent, axis: parentAxis)
        return (refPoint: (doorCoord.col, doorCoord.row), origin: (door.room2X, door.room2Y))
    }

    /// Board coordinate of a connector hex.
    private static func doorCoordinate(_ door: VGBDoor, in tile: VGBMapTileData, axis: TurnAxis?) -> HexCoord {
        let global = HexMath.normaliseAndRotatePoint(
            turns: tile.turns, refPoint: axis?.refPoint ?? (0, 0), origin: axis?.origin ?? (0, 0),
            tileCoord: (door.room1X, door.room1Y)
        )
        return HexCoord(global.0, global.1)
    }

    /// Whether a tile copy carries anything (copies reached through extra connectors are empty).
    private static func hasContent(_ tile: VGBMapTileData) -> Bool {
        !tile.monsters.isEmpty || !tile.overlays.isEmpty || !tile.doors.isEmpty
    }

    /// Where the party starts: the map's root tile when it has starting locations; otherwise the
    /// scenario's initial room (e.g. GH 12, whose map is rooted at the last room), else any tile
    /// with starting locations.
    private static func startingPlacement(in root: VGBMapTileData, initialRoomRefs: [String])
        -> (path: [Int], tile: VGBMapTileData, axis: TurnAxis?) {
        let placements = findPlacements(in: root)
        let refs = Set(initialRoomRefs.map { $0.lowercased() })
        let hasStart: (VGBMapTileData) -> Bool = { tile in
            tile.overlays.contains { $0.ref.type == "starting-location" }
        }
        if hasStart(root) || refs.isEmpty || refs.contains(root.ref.lowercased()) {
            return placements[0]
        }
        return placements.first { refs.contains($0.tile.ref.lowercased()) && hasStart($0.tile) }
            ?? placements.first { refs.contains($0.tile.ref.lowercased()) && hasContent($0.tile) }
            ?? placements.first { hasStart($0.tile) }
            ?? placements[0]
    }

    // MARK: - Private

    /// Add a tile's cells, overlays and monster slots to the board, then follow its connectors:
    /// tiles joined by a corridor (no door) belong to the same room and are revealed with it;
    /// real doors are recorded closed. A door back toward the root is recorded too when the room
    /// was entered from below (e.g. the party starts in a non-root tile).
    private static func addRoom(
        _ tileData: VGBMapTileData,
        path: [Int],
        root: VGBMapTileData,
        to board: BoardState,
        turnAxis: TurnAxis?,
        reveal: inout Reveal
    ) {
        guard !reveal.visited.contains(path) else { return }
        reveal.visited.insert(path)

        let refPoint = turnAxis?.refPoint ?? (0, 0)
        let origin = turnAxis?.origin ?? (0, 0)
        board.visibleRooms.insert(tileData.ref)
        if !reveal.tileRefs.contains(tileData.ref) { reveal.tileRefs.append(tileData.ref) }

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

        // 2. Process overlays (only on cells new to the board)
        for overlay in tileData.overlays {
            let overlayType = parseOverlayType(overlay.ref.type)

            for cell in overlay.cells {
                guard cell.count >= 2 else { continue }
                let global = HexMath.normaliseAndRotatePoint(
                    turns: tileData.turns, refPoint: refPoint, origin: origin, tileCoord: (cell[0], cell[1])
                )
                let coord = HexCoord(global.0, global.1)
                guard !reveal.preexisting.contains(coord) else { continue }

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
                    // Damage (2 + L) is computed from the scenario level when the trap springs.

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
                    if overlay.ref.type == "starting-location", !board.startingLocations.contains(coord) {
                        board.startingLocations.append(coord)
                    }
                }
            }
        }

        // 3. Monster positions (deduplicated: a tile joined by several corridors appears once
        //    per connector in the map data).
        for monster in tileData.monsters {
            let global = HexMath.normaliseAndRotatePoint(
                turns: tileData.turns, refPoint: refPoint, origin: origin,
                tileCoord: (monster.initialX, monster.initialY)
            )
            let coord = HexCoord(global.0, global.1)
            guard !reveal.preexisting.contains(coord) else { continue }
            let slot = MonsterSlot(
                name: monster.monster,
                coord: coord,
                typeByPlayerCount: [2: monster.twoPlayer, 3: monster.threePlayer, 4: monster.fourPlayer]
            )
            if !reveal.slots.contains(where: { $0.coord == slot.coord }) {
                reveal.slots.append(slot)
            }
        }

        // 4. Connectors to child tiles
        for (index, door) in tileData.doors.enumerated() {
            let doorCoord = doorCoordinate(door, in: tileData, axis: turnAxis)
            if board.cells[doorCoord] == nil {
                board.cells[doorCoord] = HexCell(coord: doorCoord, tileRef: tileData.ref, passable: true)
            }
            let axis = childAxis(of: door, in: tileData, parentAxis: turnAxis)

            if door.subType == "corridor" {
                // No door: the connected tile is part of this room.
                addRoom(door.mapTileData, path: path + [index], root: root, to: board, turnAxis: axis, reveal: &reveal)
                continue
            }
            recordDoor(at: doorCoord, subType: door.subType, leadingTo: door.mapTileData.ref,
                       path: path + [index], axis: axis, on: board)
        }

        // 5. Connector back to the parent tile, when this tile was revealed before its parent.
        if let last = path.last, let parent = tile(at: Array(path.dropLast()), in: root),
           last < parent.doors.count {
            let parentPath = Array(path.dropLast())
            guard let parentPlacement = findPlacements(in: root).first(where: { $0.path == parentPath }) else { return }
            let door = parent.doors[last]
            let doorCoord = doorCoordinate(door, in: parent, axis: parentPlacement.axis)
            if door.subType == "corridor" {
                addRoom(parent, path: parentPath, root: root, to: board, turnAxis: parentPlacement.axis, reveal: &reveal)
            } else if !board.visibleRooms.contains(parent.ref) || !reveal.visited.contains(parentPath) {
                let parentAxis = parentPlacement.axis ?? (refPoint: (0, 0), origin: (0, 0))
                recordDoor(at: doorCoord, subType: door.subType, leadingTo: parent.ref,
                           path: parentPath, axis: parentAxis, on: board)
            }
        }
    }

    /// Record a closed door (once per hex).
    private static func recordDoor(at coord: HexCoord, subType: String, leadingTo ref: String,
                                   path: [Int], axis: TurnAxis, on board: BoardState) {
        guard !board.doors.contains(where: { $0.coord == coord }) else { return }
        board.doors.append(DoorInfo(
            coord: coord,
            childTileRef: ref,
            subType: subType,
            refPoint: HexCoord(axis.refPoint.0, axis.refPoint.1),
            origin: HexCoord(axis.origin.0, axis.origin.1),
            childPath: path
        ))
        board.cells[coord]?.overlay = .door
        board.cells[coord]?.overlaySubType = subType
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
