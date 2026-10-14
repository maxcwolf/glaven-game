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

/// What a trap does to the figure that springs it. A scenario's map legend names each of its
/// traps ("Damage Trap", "Stun Trap", "Poison and Damage Trap"): some deal no damage at all, and
/// the art a trap is drawn with says nothing about which it is.
struct TrapEffect: Codable, Sendable, Equatable {
    /// Whether it deals trap damage: 2 + L, or the amount printed on the card that made it.
    var damage: Bool
    /// The conditions it gives, in the order the legend names them.
    var conditions: [ConditionName] = []
    /// What it does besides to the enemies beside it as it is sprung (Detonation: "all enemies
    /// adjacent to this trap suffer 2 damage"; Flight of Flame: "Wound all enemies adjacent to
    /// this trap").
    var adjacentDamage: Int? = nil
    var adjacentConditions: [ConditionName]? = nil

    /// Those lines of a card, from its words ("… when the trap is sprung").
    static func around(from lines: [String]) -> (damage: Int?, conditions: [ConditionName]) {
        var damage: Int?
        var conditions: [ConditionName] = []
        for line in lines.map({ $0.lowercased() }) where line.contains("adjacent to this trap") {
            if let match = line.firstMatch(of: #/suffer (\d+) damage/#) { damage = Int(match.1) }
            for condition in ConditionName.allCases where line.contains("\(condition.rawValue) all enemies adjacent") {
                conditions.append(condition)
            }
        }
        return (damage, conditions)
    }

    /// A plain damage trap.
    static let damageOnly = TrapEffect(damage: true)

    /// What a trap is guessed to do from its art alone (the map data's sub-type), for traps no
    /// legend or card describes.
    static func guess(fromArt subType: String?) -> TrapEffect {
        switch subType {
        case "poison": return TrapEffect(damage: true, conditions: [.poison])
        case "bear": return TrapEffect(damage: true, conditions: [.immobilize])
        case "thorns": return TrapEffect(damage: true, conditions: [.wound])
        default: return .damageOnly
        }
    }

    /// The trap as a legend names it: "Damage", "Stun", "Poison and Damage", "Immobilize and Poison".
    var legendName: String {
        var parts = conditions.map { $0.rawValue.prefix(1).uppercased() + $0.rawValue.dropFirst() }
        if damage { parts.append("Damage") }
        return parts.joined(separator: " and ")
    }
}

/// A single hex cell on the game board.
struct HexCell: Codable, Sendable, Equatable {
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
    /// Explicit damage override for a trap placed mid-scenario; nil means the standard
    /// damage-trap value (2 + scenario level).
    var trapDamage: Int?
    /// What a trap does when sprung, where something says so: the scenario book's legend for a
    /// trap of the map, the card or monster ability for one placed in play. Nil only for a trap
    /// nothing describes (a map without a written legend, an old save), which is guessed from
    /// the art it is drawn with.
    var trapEffect: TrapEffect?
    /// An obstacle nothing gets past or sees past: jumping and flying figures are stopped by it
    /// as walkers are, and it blocks line of sight as a wall does (Noxious Cellar's centre room).
    /// Range is still counted across it.
    var solid: Bool? = nil
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
    /// What the trap on this cell does when sprung: what is written for it, else the guess
    /// from its art.
    var resolvedTrapEffect: TrapEffect { trapEffect ?? .guess(fromArt: overlaySubType) }
}
