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

    /// Monsters still asleep (Windswept Highlands' Spitting Drakes).
    var asleep: Set<PieceID> = []

    /// Characters and their summons who fight for the other side this round (mind control).
    var turned: Set<PieceID> = []

    /// The hexes of a figure that stands on more than one (the Elder Drake on its perch); its
    /// position is one of them.
    var bodies: [PieceID: [HexCoord]] = [:]

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

    /// A doorway some monster types can't enter or pass through, open or not (those standing on
    /// the tile `from`, where one is named).
    struct BarredDoor: Hashable {
        var hex: HexCoord
        var monsters: Set<String>
        var from: String?
    }
    var barredDoors: [BarredDoor] = []

    /// The hexes `piece` can't enter or pass through, by its own movement or anyone's push.
    func barredHexes(for piece: PieceID) -> Set<HexCoord> {
        guard !barredDoors.isEmpty, case .monster(let name, _) = piece else { return [] }
        let tile = piecePositions[piece].flatMap { cells[$0]?.tileRef.lowercased() }
        return Set(barredDoors.filter { $0.monsters.contains(name) && ($0.from == nil || $0.from == tile) }.map(\.hex))
    }

    /// Doors of revealed rooms that have shut again (held open only while a pressure plate is
    /// stood on). The room behind stays revealed.
    var shutDoors: Set<HexCoord> = []

    /// The scenario's locks (by their place in its list) whose key has been turned.
    var releasedLocks: Set<Int> = []

    /// The map's places for monsters of revealed rooms that are set up later (`ScenarioPlacements.later`).
    var heldMonsterSlots: [MonsterSlot] = []

    /// Characters (by id) a scenario's water has cleansed (`ScenarioPlacements.Water.cleanses`).
    var cleansed: [String] = []
    /// How often a card has been lost to spare each objective (by its 1-based index) a source
    /// of damage (`ScenarioPlacements.saves`).
    var savesUsed: [Int: Int] = [:]

    /// How many places each cycling boss has been to (`ScenarioPlacements.Cycle`), by monster type.
    var cycleSteps: [String: Int] = [:]

    /// Goal treasure tiles looted so far, and elite monsters killed (both open doors somewhere).
    var goalTreasuresLooted = 0
    var eliteKills = 0

    /// Characters (by id) who have looted a goal treasure tile, once each.
    var goalLooters: [String] = []

    /// Characters (by id) who left the scenario through an exit.
    var escapedCharacters: [String] = []

    /// Characters (by id) who were exhausted while standing on an exit hex: an escape is
    /// complete without them.
    var exhaustedOnExit: [String] = []

    /// The conclusion section the scenario was won by, where its goal has more than one way
    /// (`ScenarioPlacements.Goal.conclusion`).
    var conclusion: String?

    /// A character has entered the hex the goal asks someone to reach (`Reach.enter`).
    var goalReached = false
    /// Who holds each carried thing (`ScenarioPlacements.carried`, by its name): a character's id.
    var carriedBy: [String: String] = [:]
    /// Where a carried thing lies that no one holds.
    var carriedLying: [String: HexCoord] = [:]
    /// Carried things that are out of the scenario, and how: "lost" with an exhausted holder,
    /// "spent" at an altar.
    var carriedGone: [String: String] = [:]
    /// The charge on a carried thing (the Staff of Xorn: a token for each point of damage its
    /// holder does the Harrower Infesters).
    var carriedCharge: [String: Int] = [:]
    /// The numbered tokens of a scenario (`ScenarioPlacements.tokens`): the numbers still to be
    /// laid out, in their shuffled order (nil until they are shuffled); those lying on the
    /// board, each on its hex; and those looted.
    var tokenDeck: [Int]?
    var tokenHexes: [HexCoord: Int] = [:]
    var tokensLooted: [Int] = []
    /// The hexes whose token has been looted (none is laid there again).
    var tokenHexesLooted: Set<HexCoord> = []
    /// The characters holding a water tile they looted (Merchant Ship).
    var waterHeld: Set<String> = []
    /// The water the scenario has taken off the map for this party's size.
    var floodSetUp = false
    /// Where the obstacles that roll as rounds end lie (Rockslide Ridge's boulders).
    var rollers: [HexCoord] = []
    /// What a rolling obstacle lies on (a trap, rubble): put back as it rolls on.
    var underRollers: [HexCoord: HexCell] = [:]

    // MARK: - Derived

    /// Reverse lookup: which piece is at a given coordinate.
    func piece(at coord: HexCoord) -> PieceID? {
        piecePositions.first(where: { $0.value == coord })?.key
            ?? bodies.first(where: { $0.value.contains(coord) && piecePositions[$0.key] != nil })?.key
    }

    /// Every hex a figure stands on: its own, or all of its body's.
    func hexes(of piece: PieceID) -> [HexCoord] {
        guard let position = piecePositions[piece] else { return [] }
        return bodies[piece] ?? [position]
    }

    /// The hex of `piece` an attack from `from` is measured to: of a figure on several hexes
    /// the nearest in sight ("if a figure can target any one of these hexes, they can target"
    /// it), else its one hex.
    func nearestHex(of piece: PieceID, to from: HexCoord) -> HexCoord? {
        guard let position = piecePositions[piece] else { return nil }
        guard let body = bodies[piece], body.count > 1 else { return position }
        return body.min { a, b in
            let ka = (LineOfSight.hasLOS(from: from, to: a, board: self) ? 0 : 1, range(from: from, to: a) ?? 99, a)
            let kb = (LineOfSight.hasLOS(from: from, to: b, board: self) ? 0 : 1, range(from: from, to: b) ?? 99, b)
            return ka < kb
        }
    }

    /// All pieces at a given coordinate (normally 0 or 1, but summons can stack).
    func pieces(at coord: HexCoord) -> [PieceID] {
        piecePositions.filter { $0.value == coord }.map(\.key)
    }

    /// Whether a coordinate is occupied by any piece.
    func isOccupied(_ coord: HexCoord) -> Bool {
        piecePositions.values.contains(coord)
    }

    // MARK: - Walls between hexes

    /// Wall lines: the sides between neighbouring hexes of two map tiles that no door or corridor
    /// joins. The edge of a map tile is a wall, also where two tiles' full hexes meet (beside a
    /// door, say): such hexes are not adjacent, nothing moves or is pushed across the line, range
    /// isn't counted across it and it blocks line of sight (GH p.19, FAQ).
    var wallEdges: Set<HexEdge> = []

    /// Hexes joined though far apart: a character beside one may spend 1 movement to stand
    /// beside the other (the two altars of Demonic Rift). Not the hexes themselves — those
    /// can't be entered — but the hexes around each.
    var crossings: [HexCoord] = []

    /// Where a character on `hex` may cross to for 1 movement: the hexes beside the other end of
    /// a crossing it stands beside.
    func crossingExits(from hex: HexCoord) -> [HexCoord] {
        guard crossings.count == 2 else { return [] }
        var exits: [HexCoord] = []
        for (near, far) in [(crossings[0], crossings[1]), (crossings[1], crossings[0])] where areAdjacent(hex, near) {
            exits += neighbors(of: far).filter { cells[$0] != nil }
        }
        return exits
    }

    /// Whether a wall line runs between two neighbouring hexes.
    func isWalled(_ a: HexCoord, _ b: HexCoord) -> Bool {
        !wallEdges.isEmpty && wallEdges.contains(HexEdge(a, b))
    }

    /// Whether two hexes are adjacent: neighbours with no wall line between them.
    func areAdjacent(_ a: HexCoord, _ b: HexCoord) -> Bool {
        a.isAdjacent(to: b) && !isWalled(a, b)
    }

    /// The hexes adjacent to one (on the map or not), leaving out those across a wall line.
    func neighbors(of hex: HexCoord) -> [HexCoord] {
        wallEdges.isEmpty ? hex.neighbors : hex.neighbors.filter { !isWalled(hex, $0) }
    }

    /// The room a hex is in: every hex reached from it without going through a doorway or
    /// across a wall. Tiles joined by a corridor are one large room; a hex in a doorway is in no
    /// room (FAQ).
    func room(of hex: HexCoord) -> Set<HexCoord> {
        func inRoom(_ other: HexCoord) -> Bool {
            guard let cell = cells[other] else { return false }
            return cell.overlay != .wall && cell.overlay != .door
        }
        guard inRoom(hex) else { return [] }
        var seen: Set<HexCoord> = [hex]
        var frontier = [hex]
        while let next = frontier.popLast() {
            for neighbor in neighbors(of: next) where inRoom(neighbor) && !seen.contains(neighbor) {
                seen.insert(neighbor)
                frontier.append(neighbor)
            }
        }
        return seen
    }

    /// Whether range can be counted through a hex: it is on the map, not a wall and not a closed
    /// door. Figures and obstacles don't matter.
    func rangePasses(through hex: HexCoord) -> Bool {
        guard let cell = cells[hex] else { return false }
        return cell.overlay != .wall && !isClosedDoor(hex)
    }

    /// How many hexes apart two hexes are, counted as range is: hex by hex, never through a wall
    /// or across a wall line (GH p.19, FAQ: two hexes with a wall line between them are two
    /// hexes apart). Nil when the count would pass `limit`, or no way round exists.
    func range(from start: HexCoord, to end: HexCoord, limit: Int = 99) -> Int? {
        if start == end { return 0 }
        let straight = start.distance(to: end)
        guard straight <= limit else { return nil }
        // Nothing in the way of the straight line: that is the count.
        let line = start.line(to: end)
        if zip(line, line.dropFirst()).allSatisfy({ !isWalled($0, $1) && ($1 == end || rangePasses(through: $1)) }) {
            return straight
        }
        var frontier = [start]
        var seen: Set<HexCoord> = [start]
        var steps = 0
        while !frontier.isEmpty, steps < limit {
            steps += 1
            var next: [HexCoord] = []
            for hex in frontier {
                for neighbor in hex.neighbors where !seen.contains(neighbor) && !isWalled(hex, neighbor) {
                    if neighbor == end { return steps }
                    guard rangePasses(through: neighbor) else { continue }
                    seen.insert(neighbor)
                    next.append(neighbor)
                }
            }
            frontier = next
        }
        return nil
    }

    /// How far apart two hexes are for telling and for ordering (nearest first): the range count,
    /// or the plain distance where no count reaches.
    func steps(from start: HexCoord, to end: HexCoord) -> Int {
        range(from: start, to: end) ?? start.distance(to: end)
    }

    /// Whether `end` is within `range` hexes of `start`, counted not through walls.
    func isWithin(_ range: Int, from start: HexCoord, to end: HexCoord) -> Bool {
        self.range(from: start, to: end, limit: range) != nil
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

    /// Whether a wall to break down still stands on this hex: a `breakable-wall` connector, shut,
    /// with the objective that is its hit points on it (Harrower Hive).
    func isStandingWall(_ coord: HexCoord?) -> Bool {
        guard let coord, let door = doors.first(where: { $0.coord == coord }), !door.isOpen,
              door.subType == BoardBuilder.breakableWallSubType else { return false }
        if case .objective = piece(at: coord) { return true }
        return false
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

    /// Hexes the figure whose move is being planned treats as traps though they aren't (Toxic
    /// Moor's water, to a poisoned character summon). Set only while that plan is made.
    var avoidedAsTraps: Set<HexCoord> = []

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
        cells[coord]?.trapEffect = nil
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

    /// Whether an obstacle on `hex` would cut one part of the map off from another: the hexes
    /// beside it could no longer all reach each other (GH p.15: obstacles can never be placed so,
    /// even where a figure could fly or jump over). A closed door counts as a way through — the
    /// room behind it is part of the map.
    func obstacleWouldDivideMap(at hex: HexCoord) -> Bool {
        func open(_ other: HexCoord) -> Bool {
            guard other != hex, let cell = cells[other] else { return false }
            return cell.overlay != .wall && cell.overlay != .obstacle
        }
        let around = neighbors(of: hex).filter(open)
        guard let first = around.first else { return false }
        var seen: Set<HexCoord> = [first]
        var frontier = [first]
        while let next = frontier.popLast() {
            for neighbor in neighbors(of: next) + crossingExits(from: next) where open(neighbor) && !seen.contains(neighbor) {
                seen.insert(neighbor)
                frontier.append(neighbor)
            }
        }
        return !around.allSatisfy(seen.contains)
    }

    /// Remove an obstacle from a hex (makes it passable again).
    func removeObstacle(at coord: HexCoord) {
        guard cells[coord] != nil else { return }
        cells[coord]?.overlay = nil
        cells[coord]?.overlaySubType = nil
        cells[coord]?.passable = true
    }

    /// Place a trap at a hex. `effect` is what it does as the card or ability that makes it
    /// prints (`damage` is then the amount it deals, if it deals any); without one it is
    /// guessed from `subType`, the art it is drawn with.
    func placeTrap(at coord: HexCoord, damage: Int, subType: String? = nil, effect: TrapEffect? = nil) {
        guard cells[coord] != nil else { return }
        cells[coord]?.overlay = .trap
        cells[coord]?.overlaySubType = subType
        cells[coord]?.trapDamage = damage
        cells[coord]?.trapEffect = effect
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
