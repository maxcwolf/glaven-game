import Foundation

/// Builds the map of a drawn random dungeon as the map data's tile tree (`VGBScenario`), so the
/// board reveals it room by room like any scenario: the first room is the root; the room behind
/// each exit hangs from that exit as a door, turned so it lies flush against the edge the exit
/// is on and covers none of the rooms before it; a room of two tiles has them joined as the card
/// draws them.
enum RandomDungeonMap {
    struct Built {
        var scenario: VGBScenario
        /// The traps the monster cards put on numbered hexes, by tile in tile coordinates.
        var traps: ScenarioTraps
        /// Each room by its path of exits from the first, with its cards.
        var rooms: [[Int]: (card: DungeonRoomCard, monsters: ScenarioData)]
        /// The room cards that couldn't be laid without covering a room before them.
        var unplaced: [String] = []
    }

    /// Treasure ids of the dungeon's treasure tiles: the monster card and the number.
    static func treasureID(card: String, marker: String) -> String { "rnd-\(card)-\(marker)" }

    static func build(_ dungeon: RandomDungeon,
                      room card: (String) -> DungeonRoomCard?,
                      monsters: (String) -> ScenarioData?) -> Built? {
        guard let firstCard = card(dungeon.first.room), let firstMonsters = monsters(dungeon.first.monsters) else { return nil }
        var trapKinds: [ScenarioTraps.Kind] = []
        var unplaced: [String] = []
        var rooms: [[Int]: (card: DungeonRoomCard, monsters: ScenarioData)] = [:]

        /// A placed room: the cells of its tiles on the board.
        func cells(of roomCard: DungeonRoomCard, entranceTile: String, turns: Int, axis: BoardBuilder.TurnAxis?) -> Set<HexCoord> {
            var result: Set<HexCoord> = []
            for placed in tilePlacements(of: roomCard, entranceTile: entranceTile, turns: turns, axis: axis) {
                for (y, row) in TileGrids.grid(for: placed.ref).enumerated() {
                    for (x, exists) in row.enumerated() where exists {
                        result.insert(global(x, y, turns: placed.turns, axis: placed.axis))
                    }
                }
            }
            return result
        }

        func tileData(_ roomCard: DungeonRoomCard, monsterCard: ScenarioData, room: RandomDungeon.Room,
                      path: [Int], isFirst: Bool, entranceTile: String, turns: Int, axis: BoardBuilder.TurnAxis?,
                      occupied: Set<HexCoord>) -> VGBMapTileData {
            rooms[path] = (roomCard, monsterCard)
            let placements = tilePlacements(of: roomCard, entranceTile: entranceTile, turns: turns, axis: axis)
            let roomCells = cells(of: roomCard, entranceTile: entranceTile, turns: turns, axis: axis)
            let taken = occupied.union(roomCells)

            // What each tile carries: the card's overlays, the monster card's things on its
            // numbers, and (in the first room) where the party may start.
            var overlays: [String: [VGBOverlay]] = [:]
            var figures: [String: [VGBMonster]] = [:]
            for overlay in roomCard.overlays {
                overlays[overlay.tile, default: []].append(VGBOverlay(
                    ref: VGBOverlayRef(type: overlay.type, subType: overlay.subType, id: nil, amount: nil),
                    direction: direction(of: overlay.cells), cells: overlay.cells))
            }
            let numbered = monsterCard.rooms?.first?.monster ?? []
            for monster in numbered {
                guard let marker = monster.marker, let place = roomCard.numbers[marker] else { continue }
                func type(_ count: String?) -> String { monster.type ?? count ?? "none" }
                figures[place.tile, default: []].append(VGBMonster(
                    monster: monster.name, initialX: place.x, initialY: place.y,
                    twoPlayer: type(monster.player2), threePlayer: type(monster.player3), fourPlayer: type(monster.player4)))
            }
            for thing in monsterCard.overlays ?? [] {
                guard let marker = thing.marker?.stringValue, let place = roomCard.numbers[marker],
                      let ref = overlayRef(thing, card: monsterCard.index, marker: marker) else { continue }
                overlays[place.tile, default: []].append(VGBOverlay(ref: ref, direction: "default", cells: [[place.x, place.y]]))
                if thing.type == "trap" {
                    let effects = (thing.values ?? []).map(\.stringValue)
                    trapKinds.append(ScenarioTraps.Kind(
                        damage: effects.contains("damage"),
                        conditions: effects.compactMap { ConditionName(rawValue: $0) },
                        count: 1, tiles: [place.tile.lowercased(): [[place.x, place.y]]]))
                }
            }
            if isFirst, room.entrance < roomCard.entrances.count {
                let entrance = roomCard.entrances[room.entrance]
                let entranceHex = globalOf(entrance.place, in: placements)
                let filled = Set(numbered.compactMap { $0.marker.flatMap { roomCard.numbers[$0] } })
                    .union((monsterCard.overlays ?? []).compactMap { $0.marker.flatMap { roomCard.numbers[$0.stringValue] } })
                for placed in placements {
                    var starts: [[Int]] = []
                    let covered = Set(roomCard.overlays.filter { $0.tile == placed.ref }.flatMap(\.cells))
                    for (y, row) in TileGrids.grid(for: placed.ref).enumerated() {
                        for (x, exists) in row.enumerated() where exists {
                            let place = DungeonRoomCard.Place(tile: placed.ref, x: x, y: y)
                            guard !filled.contains(place), !covered.contains([x, y]) else { continue }
                            if global(x, y, turns: placed.turns, axis: placed.axis).distance(to: entranceHex) <= 2 {
                                starts.append([x, y])
                            }
                        }
                    }
                    for cell in starts {
                        overlays[placed.ref, default: []].append(VGBOverlay(
                            ref: VGBOverlayRef(type: "starting-location", subType: nil, id: nil, amount: nil),
                            direction: "default", cells: [cell]))
                    }
                }
            }

            // The room behind each exit hangs from the tile the exit is on.
            var exitDoors: [String: [VGBDoor]] = [:]
            for (index, next) in room.next.enumerated() where index < roomCard.exits.count {
                let exit = roomCard.exits[index]
                guard let nextCard = card(next.room), let nextMonsters = monsters(next.monsters),
                      next.entrance < nextCard.entrances.count else { continue }
                let entrance = nextCard.entrances[next.entrance]
                let doorHex = globalOf(exit.place, in: placements)
                let inside = Set(doorHex.neighbors).intersection(roomCells)
                // Of the six ways to turn the next room with its entrance on the door, the one
                // lying on the far side of the door from this room and covering no room before.
                var best: (turns: Int, score: Int)?
                for nextTurns in 0..<6 {
                    let nextAxis: BoardBuilder.TurnAxis = (refPoint: (doorHex.col, doorHex.row), origin: (entrance.x, entrance.y))
                    let nextCells = cells(of: nextCard, entranceTile: entrance.tile, turns: nextTurns, axis: nextAxis)
                    guard nextCells.isDisjoint(with: taken), !nextCells.contains(doorHex) else { continue }
                    let touching = Set(doorHex.neighbors).intersection(nextCells)
                    let across = Set(inside.map { Self.opposite(of: $0, across: doorHex) })
                    let score = touching.intersection(across).count * 2 - touching.intersection(inside).count
                    if best == nil || score > best!.score { best = (nextTurns, score) }
                }
                guard let chosen = best, chosen.score > 0 else { unplaced.append(next.room); continue }
                let nextAxis: BoardBuilder.TurnAxis = (refPoint: (doorHex.col, doorHex.row), origin: (entrance.x, entrance.y))
                let child = tileData(nextCard, monsterCard: nextMonsters, room: next, path: path + [index], isFirst: false,
                                     entranceTile: entrance.tile, turns: chosen.turns, axis: nextAxis,
                                     occupied: taken)
                exitDoors[exit.tile, default: []].append(VGBDoor(
                    subType: "stone", direction: doorDirection(doorHex, inside: inside),
                    room1X: exit.x, room1Y: exit.y, room2X: entrance.x, room2Y: entrance.y, mapTileData: child))
            }

            // The entrance tile is the room's root; a second tile hangs from it by a corridor.
            func data(for placed: TilePlacement, doors extra: [VGBDoor]) -> VGBMapTileData {
                VGBMapTileData(ref: placed.ref, doors: extra + (exitDoors[placed.ref] ?? []),
                               overlays: overlays[placed.ref] ?? [], monsters: figures[placed.ref] ?? [], turns: placed.turns)
            }
            guard let root = placements.first else {
                return VGBMapTileData(ref: entranceTile, doors: [], overlays: [], monsters: [], turns: turns)
            }
            var corridors: [VGBDoor] = []
            for other in placements.dropFirst() {
                guard let join = other.join else { continue }
                corridors.append(VGBDoor(subType: "corridor", direction: "default",
                                         room1X: join.parent[0], room1Y: join.parent[1],
                                         room2X: join.child[0], room2Y: join.child[1],
                                         mapTileData: data(for: other, doors: [])))
            }
            return data(for: root, doors: corridors)
        }

        let entranceTile = firstCard.entrances.indices.contains(dungeon.first.entrance)
            ? firstCard.entrances[dungeon.first.entrance].tile : firstCard.tiles[0].ref
        let root = tileData(firstCard, monsterCard: firstMonsters, room: dungeon.first, path: [], isFirst: true,
                            entranceTile: entranceTile, turns: 0, axis: nil, occupied: [])
        let scenario = VGBScenario(id: 0, title: "Random Dungeon", mapTileData: root, angle: 0, additionalMonsters: nil)
        return Built(scenario: scenario, traps: ScenarioTraps(page: nil, kinds: trapKinds), rooms: rooms, unplaced: unplaced)
    }

    /// Draws a dungeon whose every room can be laid out. Now and then a room drawn would lie on
    /// a room before it, whichever way it is turned; the rules don't say what then, and the game
    /// draws the dungeon again.
    static func draw(rooms: [DungeonRoomCard], monsterCards: [ScenarioData], roomCards: [String]? = nil,
                     monsterCardsUsed: [String]? = nil, random: inout GameRandom) -> (RandomDungeon, Built)? {
        for _ in 0..<20 {
            guard let dungeon = RandomDungeon.draw(rooms: rooms, monsterCards: monsterCards.map(\.index),
                                                   roomCards: roomCards, monsterCardsUsed: monsterCardsUsed,
                                                   random: &random),
                  let built = build(dungeon, room: { name in rooms.first { $0.name == name } },
                                    monsters: { index in monsterCards.first { $0.index == index } })
            else { return nil }
            if built.unplaced.isEmpty { return (dungeon, built) }
        }
        return nil
    }

    // MARK: - Geometry

    struct TilePlacement {
        var ref: String
        var turns: Int
        var axis: BoardBuilder.TurnAxis?
        /// For a tile hanging from the room's root: the corridor's hex in the parent's and its own frame.
        var join: (parent: [Int], child: [Int])?
    }

    /// Where the room's tiles lie: the entrance tile at `turns` on `axis`, the other tile joined
    /// to it as the card draws them.
    static func tilePlacements(of room: DungeonRoomCard, entranceTile: String, turns: Int,
                               axis: BoardBuilder.TurnAxis?) -> [TilePlacement] {
        guard let rootTile = room.tiles.first(where: { $0.ref == entranceTile }) ?? room.tiles.first else { return [] }
        var result = [TilePlacement(ref: rootTile.ref, turns: turns, axis: axis, join: nil)]
        for other in room.tiles where other.ref != rootTile.ref {
            // The join is written on the second tile: its hex `second` lies on `first` of the first tile.
            guard let join = other.join ?? rootTile.join else { continue }
            let rootIsFirst = other.join != nil
            let parentCoord = rootIsFirst ? join.first : join.second
            let childCoord = rootIsFirst ? join.second : join.first
            let refPoint = global(parentCoord[0], parentCoord[1], turns: turns, axis: axis)
            let otherTurns = ((turns + other.matchTurns - rootTile.matchTurns) % 6 + 6) % 6
            result.append(TilePlacement(ref: other.ref, turns: otherTurns,
                                        axis: (refPoint: (refPoint.col, refPoint.row), origin: (childCoord[0], childCoord[1])),
                                        join: (parentCoord, childCoord)))
        }
        return result
    }

    static func global(_ x: Int, _ y: Int, turns: Int, axis: BoardBuilder.TurnAxis?) -> HexCoord {
        let point = HexMath.normaliseAndRotatePoint(turns: turns, refPoint: axis?.refPoint ?? (0, 0),
                                                    origin: axis?.origin ?? (0, 0), tileCoord: (x, y))
        return HexCoord(point.0, point.1)
    }

    private static func globalOf(_ place: DungeonRoomCard.Place, in placements: [TilePlacement]) -> HexCoord {
        let placed = placements.first { $0.ref == place.tile } ?? placements[0]
        return global(place.x, place.y, turns: placed.turns, axis: placed.axis)
    }

    /// The hex on the far side of `center` from `hex`.
    private static func opposite(of hex: HexCoord, across center: HexCoord) -> HexCoord {
        let a = HexMath.oddRowToCube(hex.col, hex.row)
        let c = HexMath.oddRowToCube(center.col, center.row)
        let o = HexMath.cubeToOddRow(2 * c.x - a.x, 2 * c.y - a.y, 2 * c.z - a.z)
        return HexCoord(o.col, o.row)
    }

    /// A door on a tile's left or right edge stands upright; on the others it lies along the edge.
    private static func doorDirection(_ door: HexCoord, inside: Set<HexCoord>) -> String {
        inside.allSatisfy { $0.row == door.row } && !inside.isEmpty ? "vertical" : "default"
    }

    /// How a multi-hex overlay lies, as the map data names it, from the offset of its second hex.
    private static func direction(of cells: [[Int]]) -> String {
        guard cells.count >= 2, cells[0].count >= 2, cells[1].count >= 2 else { return "default" }
        return cells[0][1] == cells[1][1] ? "horizontal" : "default"
    }

    /// The map data's overlay for a thing a monster card puts on a number.
    private static func overlayRef(_ thing: ScenarioOverlay, card: String, marker: String) -> VGBOverlayRef? {
        switch thing.type {
        case "loot": return VGBOverlayRef(type: "treasure", subType: "coin", id: nil, amount: 1)
        case "treasure": return VGBOverlayRef(type: "treasure", subType: "chest", id: treasureID(card: card, marker: marker), amount: nil)
        case "trap":
            let art = switch thing.value {
            case "bear-trap": "bear"
            case "poison-gas-trap": "poison"
            default: "spike"
            }
            return VGBOverlayRef(type: "trap", subType: art, id: nil, amount: nil)
        case "difficultTerrain": return VGBOverlayRef(type: "difficult-terrain", subType: thing.value, id: nil, amount: nil)
        case "hazardousTerrain": return VGBOverlayRef(type: "hazard", subType: thing.value, id: nil, amount: nil)
        default: return nil
        }
    }
}
