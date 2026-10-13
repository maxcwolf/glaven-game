import Foundation

/// A monster position from the map data. Which monsters appear — and whether they are normal,
/// elite or boss — comes from the scenario data; the map supplies where they stand.
struct MonsterSlot: Codable, Equatable, Sendable {
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

    /// The connector that is no door but a crossing between two tiles lying apart.
    static let crossingSubType = "altar"

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
                turnAxis: start.axis, placements: scenario.placements, traps: scenario.traps, reveal: &reveal)
        // Some scenarios split the party between separate starting tiles (e.g. GH 50, 58, 85: the
        // scenario's first room covers both). Every tile with starting hexes is revealed at setup.
        for placement in findPlacements(in: scenario.mapTileData)
        where hasStartingLocations(placement.tile) && !reveal.visited.contains(placement.path) {
            addRoom(placement.tile, path: placement.path, root: scenario.mapTileData, to: board,
                    turnAxis: placement.axis, placements: scenario.placements, traps: scenario.traps, reveal: &reveal)
        }
        recomputeBounds(board)
        board.wallEdges = wallEdges(in: scenario, among: Set(board.cells.keys))
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
    /// With `opening` false the door stays shut: the tiles are laid out behind it (a room the
    /// scenario shows from the start, or one entered some other way than by its door).
    static func revealRoomSlots(door: DoorInfo, scenario: VGBScenario, board: BoardState, opening: Bool = true) -> Reveal? {
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
        addRoom(tile, path: path, root: root, to: board, turnAxis: turnAxis,
                placements: scenario.placements, traps: scenario.traps, reveal: &reveal)

        if opening {
            // A door two or three hexes wide is one door: all of it opens.
            for coord in doorHexes(ofTheDoorAt: door.coord, on: board) {
                if let idx = board.doors.firstIndex(where: { $0.coord == coord }) { board.doors[idx].isOpen = true }
            }
        }
        recomputeBounds(board)
        board.wallEdges = wallEdges(in: scenario, among: Set(board.cells.keys))
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

    /// Where a lettered hex is on the whole map, revealed or not, with the path of its tile.
    static func markerSites(_ marker: String, in scenario: VGBScenario) -> [(path: [Int], coord: HexCoord)] {
        guard let placements = scenario.placements else { return [] }
        var sites: [(path: [Int], coord: HexCoord)] = []
        for placement in findPlacements(in: scenario.mapTileData) {
            for cell in placements.tiles[placement.tile.ref.lowercased()]?.markers?[marker] ?? [] where cell.count >= 2 {
                let global = HexMath.normaliseAndRotatePoint(
                    turns: placement.tile.turns, refPoint: placement.axis?.refPoint ?? (0, 0),
                    origin: placement.axis?.origin ?? (0, 0), tileCoord: (cell[0], cell[1])
                )
                let coord = HexCoord(global.0, global.1)
                if !sites.contains(where: { $0.coord == coord }) { sites.append((placement.path, coord)) }
            }
        }
        return sites
    }

    /// Every tile of the room behind a door: its own, and those joined to it by corridors.
    static func roomRefs(behind door: DoorInfo, in scenario: VGBScenario) -> Set<String> {
        var refs: Set<String> = [door.childTileRef.lowercased()]
        guard let path = door.childPath, let start = tile(at: path, in: scenario.mapTileData) else { return refs }
        func walk(_ tile: VGBMapTileData) {
            refs.insert(tile.ref.lowercased())
            for connector in tile.doors where connector.subType == "corridor" { walk(connector.mapTileData) }
        }
        walk(start)
        return refs
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
        placements: ScenarioPlacements?,
        traps: ScenarioTraps?,
        reveal: inout Reveal
    ) {
        guard !reveal.visited.contains(path) else { return }
        reveal.visited.insert(path)

        // A tile reached by two connectors is in the map data twice, and only one copy carries
        // its overlays, monsters and onward connectors. Entered by the other one, it is that
        // copy which is laid out (the room was revealed empty: #7's F1b from D2b, #53's J2a).
        if let full = fullCopy(of: tileData, path: path, axis: turnAxis, in: root) {
            addRoom(full.tile, path: full.path, root: root, to: board, turnAxis: full.axis,
                    placements: placements, traps: traps, reveal: &reveal)
            return
        }

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
                    // What it does is what the scenario book's legend says of it, not what its
                    // art suggests (a "Stun Trap" drawn as a bear trap deals no damage). Damage
                    // (2 + L) is computed from the scenario level when the trap springs.
                    board.cells[coord]?.trapEffect = traps?.kind(tile: tileData.ref, cell: cell, art: overlay.ref.subType)?.effect

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
                addRoom(door.mapTileData, path: path + [index], root: root, to: board, turnAxis: axis,
                        placements: placements, traps: traps, reveal: &reveal)
                continue
            }
            if door.subType == Self.crossingSubType {
                // Not a door but one end of a crossing (the altars of Demonic Rift): the tile
                // beyond lies apart and is on the map from the start; its own altar is the
                // other end.
                board.cells[doorCoord]?.overlay = .obstacle
                board.cells[doorCoord]?.overlaySubType = door.subType
                board.cells[doorCoord]?.passable = false
                addRoom(door.mapTileData, path: path + [index], root: root, to: board, turnAxis: axis,
                        placements: placements, traps: traps, reveal: &reveal)
                let far = board.cells.values.filter {
                    $0.coord != doorCoord && $0.overlay == .obstacle && $0.overlaySubType == door.subType
                        && $0.tileRef == door.mapTileData.ref
                }.map(\.coord).min()
                if let far, board.crossings.isEmpty { board.crossings = [doorCoord, far] }
                continue
            }
            recordDoor(at: doorCoord, subType: door.subType, leadingTo: door.mapTileData.ref, from: tileData.ref,
                       path: path + [index], axis: axis, on: board)
        }

        // 5. Objective places and spawn markers written for this tile (once per hex: a tile
        //    joined by several corridors appears once per connector in the map data).
        if let written = placements?.tiles[tileData.ref.lowercased()] {
            let place: ([Int]) -> HexCoord? = { cell in
                guard cell.count >= 2 else { return nil }
                let global = HexMath.normaliseAndRotatePoint(
                    turns: tileData.turns, refPoint: refPoint, origin: origin, tileCoord: (cell[0], cell[1])
                )
                return HexCoord(global.0, global.1)
            }
            for objective in written.objectives ?? [] {
                let cells = objective.cells.compactMap(place)
                guard let coord = cells.first, board.cells[coord] != nil, !reveal.preexisting.contains(coord),
                      !board.openObjectiveSlots.contains(where: { $0.coord == coord }),
                      !board.objectiveSites.values.contains(where: { $0.coord == coord }) else { continue }
                board.openObjectiveSlots.append(ObjectiveSlot(objective: objective.objective, coord: coord, cells: cells,
                                                              barsDoor: objective.door ?? false))
            }
            for (marker, hexes) in (written.markers ?? [:]).sorted(by: { $0.key < $1.key }) {
                for coord in hexes.compactMap(place) where board.cells[coord] != nil
                    && !(board.markerHexes[marker] ?? []).contains(coord) {
                    board.markerHexes[marker, default: []].append(coord)
                }
            }
        }

        // 6. Connectors from tiles that hold only an empty copy of this one.
        addConnectorsFromEmptyCopies(of: tileData, path: path, axis: turnAxis, root: root, to: board,
                                     placements: placements, traps: traps, reveal: &reveal)

        // 7. Connector back to the parent tile, when this tile was revealed before its parent.
        if let last = path.last, let parent = tile(at: Array(path.dropLast()), in: root),
           last < parent.doors.count {
            let parentPath = Array(path.dropLast())
            guard let parentPlacement = findPlacements(in: root).first(where: { $0.path == parentPath }) else { return }
            let door = parent.doors[last]
            let doorCoord = doorCoordinate(door, in: parent, axis: parentPlacement.axis)
            if door.subType == "corridor" {
                addRoom(parent, path: parentPath, root: root, to: board, turnAxis: parentPlacement.axis,
                        placements: placements, traps: traps, reveal: &reveal)
            } else if !board.visibleRooms.contains(parent.ref) || !reveal.visited.contains(parentPath) {
                let parentAxis = parentPlacement.axis ?? (refPoint: (0, 0), origin: (0, 0))
                // (The connector's own hex is on the map from this side too.)
                if board.cells[doorCoord] == nil {
                    board.cells[doorCoord] = HexCell(coord: doorCoord, tileRef: tileData.ref, passable: true)
                }
                recordDoor(at: doorCoord, subType: door.subType, leadingTo: parent.ref, from: tileData.ref,
                           path: parentPath, axis: parentAxis, on: board)
            }
        }
    }

    /// The wall lines among `cells` (the hexes on the board): every side shared by full hexes of
    /// two different tiles. The edge of a map tile is a wall unless a door or corridor covers it
    /// (FAQ), and those cover the hexes the two tiles' half-hexes make together — so two full
    /// hexes that meet across the border, beside a door or anywhere else, have a wall line
    /// between them. Hexes outside every tile's own grid (doors, corridors) join what they touch.
    static func wallEdges(in scenario: VGBScenario, among cells: Set<HexCoord>) -> Set<HexEdge> {
        var tileOf: [HexCoord: Int] = [:]
        var connectors = Set<HexCoord>()
        var tiles: [Set<HexCoord>] = []
        for placement in findPlacements(in: scenario.mapTileData) {
            let grid = cellSet(of: placement.tile, axis: placement.axis)
            // A tile reached by two connectors is in the data twice: one tile.
            let id = tiles.firstIndex(of: grid) ?? {
                tiles.append(grid)
                return tiles.count - 1
            }()
            for cell in grid where tileOf[cell] == nil { tileOf[cell] = id }
            for door in placement.tile.doors {
                connectors.insert(doorCoordinate(door, in: placement.tile, axis: placement.axis))
            }
            for overlay in placement.tile.overlays {
                for cell in overlay.cells where cell.count >= 2 {
                    let global = HexMath.normaliseAndRotatePoint(
                        turns: placement.tile.turns, refPoint: placement.axis?.refPoint ?? (0, 0),
                        origin: placement.axis?.origin ?? (0, 0), tileCoord: (cell[0], cell[1])
                    )
                    let coord = HexCoord(global.0, global.1)
                    if !grid.contains(coord) { connectors.insert(coord) }
                }
            }
        }
        var edges = Set<HexEdge>()
        for cell in cells where !connectors.contains(cell) {
            guard let mine = tileOf[cell] else { continue }
            for neighbor in cell.neighbors where cells.contains(neighbor) && !connectors.contains(neighbor) {
                if let theirs = tileOf[neighbor], theirs != mine { edges.insert(HexEdge(cell, neighbor)) }
            }
        }
        return edges
    }

    /// The hexes a tile covers on the board, placed by `axis`.
    private static func cellSet(of tile: VGBMapTileData, axis: TurnAxis?) -> Set<HexCoord> {
        var cells = Set<HexCoord>()
        for (y, row) in TileGrids.grid(for: tile.ref).enumerated() {
            for (x, exists) in row.enumerated() where exists {
                let global = HexMath.normaliseAndRotatePoint(
                    turns: tile.turns, refPoint: axis?.refPoint ?? (0, 0), origin: axis?.origin ?? (0, 0), tileCoord: (x, y)
                )
                cells.insert(HexCoord(global.0, global.1))
            }
        }
        return cells
    }

    /// For an empty copy of a tile (one reached through an extra connector), the copy of the
    /// same tile, on the same hexes, that carries its content.
    private static func fullCopy(of tile: VGBMapTileData, path: [Int], axis: TurnAxis?, in root: VGBMapTileData)
        -> (path: [Int], tile: VGBMapTileData, axis: TurnAxis?)? {
        guard !hasContent(tile) else { return nil }
        let cells = cellSet(of: tile, axis: axis)
        return findPlacements(in: root).first {
            $0.path != path && $0.tile.ref == tile.ref && hasContent($0.tile) && cellSet(of: $0.tile, axis: $0.axis) == cells
        }
    }

    /// Connectors that reach this tile from tiles holding only an empty copy of it: from this
    /// side they exist too — a door to open, or a corridor that makes the other tile part of
    /// this room.
    private static func addConnectorsFromEmptyCopies(of tileData: VGBMapTileData, path: [Int], axis: TurnAxis?,
                                                     root: VGBMapTileData, to board: BoardState,
                                                     placements: ScenarioPlacements?, traps: ScenarioTraps?,
                                                     reveal: inout Reveal) {
        let cells = cellSet(of: tileData, axis: axis)
        for placement in findPlacements(in: root) where placement.path != path {
            for (index, door) in placement.tile.doors.enumerated()
            where door.mapTileData.ref == tileData.ref && !hasContent(door.mapTileData) && placement.path + [index] != path {
                let copyAxis = childAxis(of: door, in: placement.tile, parentAxis: placement.axis)
                guard cellSet(of: door.mapTileData, axis: copyAxis) == cells else { continue }
                let doorCoord = doorCoordinate(door, in: placement.tile, axis: placement.axis)
                if door.subType == "corridor" {
                    if board.cells[doorCoord] == nil {
                        board.cells[doorCoord] = HexCell(coord: doorCoord, tileRef: tileData.ref, passable: true)
                    }
                    addRoom(placement.tile, path: placement.path, root: root, to: board, turnAxis: placement.axis,
                            placements: placements, traps: traps, reveal: &reveal)
                } else if !reveal.visited.contains(placement.path),
                          !cellSet(of: placement.tile, axis: placement.axis).isSubset(of: Set(board.cells.keys)) {
                    if board.cells[doorCoord] == nil {
                        board.cells[doorCoord] = HexCell(coord: doorCoord, tileRef: tileData.ref, passable: true)
                    }
                    recordDoor(at: doorCoord, subType: door.subType, leadingTo: placement.tile.ref, from: tileData.ref,
                               path: placement.path, axis: placement.axis ?? (refPoint: (0, 0), origin: (0, 0)), on: board)
                }
            }
        }
    }

    /// The hexes of the door a hex belongs to: a wide door (Shrine of Strength's are two hexes,
    /// Sacrifice Pit's three) is drawn as door hexes side by side between the same two tiles, and
    /// is one door. A wall to break down (Harrower Hive) is its own hex, whatever stands beside it.
    static func doorHexes(ofTheDoorAt coord: HexCoord, on board: BoardState) -> [HexCoord] {
        guard let door = board.doors.first(where: { $0.coord == coord }) else { return [] }
        guard door.subType != breakableWallSubType else { return [coord] }
        var found: [HexCoord] = [coord]
        var frontier = [coord]
        while let hex = frontier.popLast() {
            for other in board.doors where !found.contains(other.coord) && hex.neighbors.contains(other.coord)
                && other.subType == door.subType && other.childTileRef == door.childTileRef && other.fromTileRef == door.fromTileRef {
                found.append(other.coord)
                frontier.append(other.coord)
            }
        }
        return found.sorted()
    }

    /// The connector that is a wall with hit points, not a door.
    static let breakableWallSubType = "breakable-wall"

    /// The map tiles with a hex beside `hex`, revealed or not (a wall at the corner of three
    /// tiles has two rooms on its other side).
    static func tiles(touching hex: HexCoord, in scenario: VGBScenario) -> Set<String> {
        let beside = Set(hex.neighbors)
        return Set(findPlacements(in: scenario.mapTileData)
            .filter { !cellSet(of: $0.tile, axis: $0.axis).isDisjoint(with: beside) }
            .map { $0.tile.ref.lowercased() })
    }

    /// Record a closed door (once per hex).
    private static func recordDoor(at coord: HexCoord, subType: String, leadingTo ref: String, from: String,
                                   path: [Int], axis: TurnAxis, on board: BoardState) {
        guard !board.doors.contains(where: { $0.coord == coord }) else { return }
        board.doors.append(DoorInfo(
            coord: coord,
            childTileRef: ref,
            subType: subType,
            refPoint: HexCoord(axis.refPoint.0, axis.refPoint.1),
            origin: HexCoord(axis.origin.0, axis.origin.1),
            fromTileRef: from,
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
