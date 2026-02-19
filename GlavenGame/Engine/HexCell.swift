import Foundation

/// The type of overlay occupying a hex cell.
enum OverlayType: String, Codable, Sendable {
    case obstacle
    case trap
    case hazard
    case difficultTerrain
    case treasure
    case door
    case wall
    case rift
}

/// A single hex cell on the game board.
struct HexCell: Codable, Sendable {
    let coord: HexCoord
    /// Which map tile ref this cell belongs to (e.g. "l1a", "g1b").
    let tileRef: String
    /// Whether figures can stand on / walk through this cell.
    var passable: Bool
    /// Overlay occupying this cell, if any.
    var overlay: OverlayType?
    /// Image name for the overlay (used for rendering).
    var overlayImageName: String?
    /// Overlay sub-type (e.g. "spike" for traps, "table" for obstacles).
    var overlaySubType: String?
    /// Damage dealt by traps on this cell.
    var trapDamage: Int?
    /// Treasure ID for treasure chests/coins.
    var treasureID: String?
    /// Treasure coin amount (for coin tokens).
    var treasureAmount: Int?
    /// Whether this is difficult terrain (costs 2 movement).
    var isDifficultTerrain: Bool { overlay == .difficultTerrain }
    /// Whether this cell is a hazard.
    var isHazard: Bool { overlay == .hazard }
    /// Whether this cell has an active trap.
    var isTrap: Bool { overlay == .trap }
}
