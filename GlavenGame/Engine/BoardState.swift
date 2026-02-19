import Foundation

/// Information about a door connecting two map tile rooms.
struct DoorInfo: Codable, Sendable {
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
    /// The VGBMapTileData for the child room (stored for room reveal).
    /// Not codable — rebuilt from scenario data on restore.
    var isOpen: Bool = false
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

    /// Remove a treasure overlay from a cell (after it's looted).
    func removeTreasure(at coord: HexCoord) {
        cells[coord]?.overlay = nil
        cells[coord]?.overlayImageName = nil
        cells[coord]?.treasureID = nil
        cells[coord]?.treasureAmount = nil
    }
}
