import Foundation

/// A codable snapshot of the board state for undo/redo.
struct BoardSnapshot: Codable {
    let cells: [HexCoord: HexCell]
    let piecePositions: [PieceIDCodable: HexCoord]
    let visibleRooms: Set<String>
    let startingLocations: [HexCoord]
    let doors: [DoorInfo]
    let bounds: MapBounds
    let eliteStandees: Set<PieceIDCodable>
    let lootTokens: [HexCoord: Int]
    /// Traps a character placed (Proximity Mine), who placed them and the XP an enemy springing
    /// one gives them. Optional: older saves have none.
    var characterTraps: [CharacterTrap]? = nil
    /// Spawn marker hexes and objective places. Optional: older saves have none.
    var markerHexes: [String: [HexCoord]]? = nil
    var openObjectiveSlots: [ObjectiveSlot]? = nil
    var objectiveSites: [Int: ObjectiveSlot]? = nil
    var goalLooters: [String]? = nil
    var escapedCharacters: [String]? = nil
    var lockedDoors: Set<HexCoord>? = nil
    var shutDoors: Set<HexCoord>? = nil
    var releasedLocks: Set<Int>? = nil
    var goalTreasuresLooted: Int? = nil
    var eliteKills: Int? = nil

    struct CharacterTrap: Codable, Equatable {
        let hex: HexCoord
        let characterID: String
        let experience: Int
    }

    /// Create a snapshot from the current board state.
    static func from(_ board: BoardState) -> BoardSnapshot {
        let codablePieces = Dictionary(
            uniqueKeysWithValues: board.piecePositions.map { (PieceIDCodable($0.key), $0.value) }
        )
        return BoardSnapshot(
            cells: board.cells,
            piecePositions: codablePieces,
            visibleRooms: board.visibleRooms,
            startingLocations: board.startingLocations,
            doors: board.doors,
            bounds: board.bounds,
            eliteStandees: Set(board.eliteStandees.map { PieceIDCodable($0) }),
            lootTokens: board.lootTokens,
            markerHexes: board.markerHexes,
            openObjectiveSlots: board.openObjectiveSlots,
            objectiveSites: board.objectiveSites,
            goalLooters: board.goalLooters,
            escapedCharacters: board.escapedCharacters,
            lockedDoors: board.lockedDoors, shutDoors: board.shutDoors, releasedLocks: board.releasedLocks,
            goalTreasuresLooted: board.goalTreasuresLooted, eliteKills: board.eliteKills
        )
    }

    /// Restore the board state from this snapshot.
    func restore(to board: BoardState) {
        board.cells = cells
        board.piecePositions = Dictionary(
            uniqueKeysWithValues: piecePositions.map { ($0.key.pieceID, $0.value) }
        )
        board.visibleRooms = visibleRooms
        board.startingLocations = startingLocations
        board.doors = doors
        board.bounds = bounds
        board.eliteStandees = Set(eliteStandees.map { $0.pieceID })
        board.lootTokens = lootTokens
        board.markerHexes = markerHexes ?? [:]
        board.openObjectiveSlots = openObjectiveSlots ?? []
        board.objectiveSites = objectiveSites ?? [:]
        board.goalLooters = goalLooters ?? []
        board.escapedCharacters = escapedCharacters ?? []
        board.lockedDoors = lockedDoors ?? []
        board.shutDoors = shutDoors ?? []
        board.releasedLocks = releasedLocks ?? []
        board.goalTreasuresLooted = goalTreasuresLooted ?? 0
        board.eliteKills = eliteKills ?? 0
    }
}

// MARK: - PieceID Codable Wrapper

/// PieceID needs a custom Codable wrapper because enum associated values
/// with mixed types can't be Dictionary keys directly.
struct PieceIDCodable: Codable, Hashable {
    let pieceID: PieceID

    init(_ pieceID: PieceID) {
        self.pieceID = pieceID
    }

    private enum CodingKeys: String, CodingKey {
        case type, characterID, monsterName, standee, summonID, objectiveID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch pieceID {
        case .character(let id):
            try container.encode("character", forKey: .type)
            try container.encode(id, forKey: .characterID)
        case .monster(let name, let standee):
            try container.encode("monster", forKey: .type)
            try container.encode(name, forKey: .monsterName)
            try container.encode(standee, forKey: .standee)
        case .summon(let id):
            try container.encode("summon", forKey: .type)
            try container.encode(id, forKey: .summonID)
        case .objective(let id):
            try container.encode("objective", forKey: .type)
            try container.encode(id, forKey: .objectiveID)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "character":
            let id = try container.decode(String.self, forKey: .characterID)
            pieceID = .character(id)
        case "monster":
            let name = try container.decode(String.self, forKey: .monsterName)
            let standee = try container.decode(Int.self, forKey: .standee)
            pieceID = .monster(name: name, standee: standee)
        case "summon":
            let id = try container.decode(String.self, forKey: .summonID)
            pieceID = .summon(id: id)
        case "objective":
            let id = try container.decode(Int.self, forKey: .objectiveID)
            pieceID = .objective(id: id)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.type], debugDescription: "Unknown piece type: \(type)"))
        }
    }
}
