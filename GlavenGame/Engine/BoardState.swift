import Foundation

/// Information about a door connecting two map tile rooms.
struct DoorInfo: Codable, Sendable, Equatable {
    /// The hex coordinate where the door sits.
    let coord: HexCoord
    /// The tile ref of the child room behind this door (e.g. "g1b").
    let childTileRef: String
    /// Door sub-type (e.g. "stone", "wooden").
    let subType: String
    /// The reference point for coordinate transform when revealing the child room.
    let refPoint: HexCoord
    /// The origin point in the child tile's local space.
    let origin: HexCoord
    var isOpen: Bool = false
    /// The tile ref on this side of the door, the one revealed first. Optional: older saves
    /// have none.
    var fromTileRef: String? = nil
    /// Path of door indices from the map's root tile to the tile behind this door. The same tile
    /// name can appear several times in the map tree (once per connector), and only one copy
    /// carries its monsters, overlays and onward doors, so rooms are located by path.
    var childPath: [Int]? = nil
}

/// Spatial game state tracking what's on each hex.
/// Kept separate from GameState — this is a parallel spatial layer.
@Observable
final class BoardState {
    /// All hex cells on the board, keyed by coordinate.
    var cells: [HexCoord: HexCell] = [:]

    /// Where each piece is on the board.
    var piecePositions: [PieceID: HexCoord] = [:]

    /// Which rooms have been revealed (by tile ref).
    var visibleRooms: Set<String> = []

    /// Starting locations for character placement.
    var startingLocations: [HexCoord] = []

    /// Door info for room reveal.
    var doors: [DoorInfo] = []

    /// Bounding box of all placed tiles.
    var bounds: MapBounds = .zero

    /// Monster standees that are elite (for visual distinction).
    var eliteStandees: Set<PieceID> = []

    /// Loot tokens on the board (dropped when monsters die). Value = token count at that hex.
    var lootTokens: [HexCoord: Int] = [:]

    /// The lettered spawn hexes of the revealed tiles, by marker ("a").
    var markerHexes: [String: [HexCoord]] = [:]

    /// Places for objectives in the revealed tiles that no objective stands on yet.
    var openObjectiveSlots: [ObjectiveSlot] = []

    /// Where each objective on the board stands, by its number: the hexes it covers and whether
    /// it bars a door.
    var objectiveSites: [Int: ObjectiveSlot] = [:]

    /// Doors a scenario rule keeps locked: walking into one doesn't open it.
    var lockedDoors: Set<HexCoord> = []

    /// Doors of revealed rooms that have shut again (held open only while a pressure plate is
    /// stood on). The room behind stays revealed.
    var shutDoors: Set<HexCoord> = []

    /// The scenario's locks (by their place in its list) whose key has been turned.
    var releasedLocks: Set<Int> = []

    /// Goal treasure tiles looted so far, and elite monsters killed (both open doors somewhere).
    var goalTreasuresLooted = 0
    var eliteKills = 0

    /// Characters (by id) who have looted a goal treasure tile, once each.
    var goalLooters: [String] = []

    /// Characters (by id) who left the scenario through an exit.
    var escapedCharacters: [String] = []

    // MARK: - Derived

    /// Reverse lookup: which piece is at a given coordinate.
    func piece(at coord: HexCoord) -> PieceID? {
        piecePositions.first(where: { $0.value == coord })?.key
    }

    /// All pieces at a given coordinate (normally 0 or 1, but summons can stack).
    func pieces(at coord: HexCoord) -> [PieceID] {
        piecePositions.filter { $0.value == coord }.map(\.key)
    }

    /// Whether a coordinate is occupied by any piece.
    func isOccupied(_ coord: HexCoord) -> Bool {
        piecePositions.values.contains(coord)
    }

    /// Whether a hex is passable and exists on the board.
    func isPassable(_ coord: HexCoord) -> Bool {
        cells[coord]?.passable ?? false
    }

    /// Whether a closed door sits on this hex: one never opened, or one that has shut again.
    /// Characters may enter it (which opens the door) unless it is locked; monsters and summons
    /// treat it as a wall.
    func isClosedDoor(_ coord: HexCoord) -> Bool {
        shutDoors.contains(coord) || doors.contains { $0.coord == coord && !$0.isOpen }
    }

    /// Whether a closed door on this hex can't be opened by walking into it.
    func isLockedDoor(_ coord: HexCoord) -> Bool {
        lockedDoors.contains(coord) && isClosedDoor(coord)
    }

    /// Whether this hex is a "negative hex" for movement: an active trap or hazardous
    /// terrain (monster AI treats these as obstacles unless no other route exists).
    func isNegativeHex(_ coord: HexCoord) -> Bool {
        guard let cell = cells[coord] else { return false }
        return cell.isTrap || cell.isHazard
    }

    /// Whether a figure can move into this hex (passable + not occupied by enemy).
    /// `allies` determines which pieces are friendly (can pass through but not stop on).
    func canEnter(_ coord: HexCoord, flying: Bool = false) -> Bool {
        guard let cell = cells[coord] else { return false }
        if flying { return true }
        return cell.passable
    }

    // MARK: - Mutations

    /// Place a piece at a coordinate. Only one figure per hex (Gloomhaven rule).
    /// Returns false if the hex is already occupied.
    @discardableResult
    func placePiece(_ id: PieceID, at coord: HexCoord) -> Bool {
        // Allow re-placing the same piece (no-op move)
        if piecePositions[id] == coord { return true }
        // Enforce one figure per hex
        if isOccupied(coord) { return false }
        piecePositions[id] = coord
        return true
    }

    /// Remove a piece from the board.
    func removePiece(_ id: PieceID) {
        piecePositions.removeValue(forKey: id)
    }

    /// Move a piece to a new coordinate. Enforces one figure per hex.
    /// Returns false if the destination is already occupied by another figure.
    @discardableResult
    func movePiece(_ id: PieceID, to coord: HexCoord) -> Bool {
        // Allow "moving" to the same spot
        if piecePositions[id] == coord { return true }
        // Enforce one figure per hex
        if isOccupied(coord) { return false }
        piecePositions[id] = coord
        return true
    }

    /// Remove a trap overlay from a cell (after it triggers).
    func removeTrap(at coord: HexCoord) {
        cells[coord]?.overlay = nil
        cells[coord]?.overlayImageName = nil
        cells[coord]?.overlaySubType = nil
        cells[coord]?.trapDamage = nil
    }

    /// Place loot tokens at a hex (monsters drop these when killed).
    func placeLoot(at coord: HexCoord, count: Int = 1) {
        lootTokens[coord, default: 0] += count
    }

    /// Remove and return the number of loot tokens at a hex (characters pick these up).
    @discardableResult
    func takeLoot(at coord: HexCoord) -> Int {
        guard let count = lootTokens[coord], count > 0 else { return 0 }
        lootTokens.removeValue(forKey: coord)
        return count
    }

    /// Place an obstacle at a hex (makes it impassable).
    func placeObstacle(at coord: HexCoord, subType: String? = nil) {
        guard cells[coord] != nil else { return }
        cells[coord]?.overlay = .obstacle
        cells[coord]?.overlaySubType = subType
        cells[coord]?.passable = false
    }

    /// Remove an obstacle from a hex (makes it passable again).
    func removeObstacle(at coord: HexCoord) {
        guard cells[coord] != nil else { return }
        cells[coord]?.overlay = nil
        cells[coord]?.overlaySubType = nil
        cells[coord]?.passable = true
    }

    /// Place a trap at a hex.
    func placeTrap(at coord: HexCoord, damage: Int, subType: String? = nil) {
        guard cells[coord] != nil else { return }
        cells[coord]?.overlay = .trap
        cells[coord]?.overlaySubType = subType
        cells[coord]?.trapDamage = damage
    }

    /// Place hazardous terrain at a hex.
    func placeHazard(at coord: HexCoord, subType: String? = nil) {
        guard cells[coord] != nil else { return }
        cells[coord]?.overlay = .hazard
        cells[coord]?.overlaySubType = subType
    }

    /// Remove a treasure overlay from a cell (after it's looted).
    func removeTreasure(at coord: HexCoord) {
        cells[coord]?.overlay = nil
        cells[coord]?.overlayImageName = nil
        cells[coord]?.treasureID = nil
        cells[coord]?.treasureAmount = nil
    }
}
