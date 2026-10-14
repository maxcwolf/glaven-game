import XCTest
import SpriteKit
@testable import GlavenGameLib

/// The random dungeon deck (rulebook pp. 50–51): three rooms, each a room card's map with a
/// monster card's figures on its twelve numbered hexes.
@MainActor
final class RandomDungeonTests: XCTestCase {

    // MARK: - The cards

    private var rooms: [DungeonRoomCard] { DungeonCardStore.shared.rooms() }

    private static var loadedMonsterCards: [ScenarioData]?

    private func monsterCards() throws -> [ScenarioData] {
        if let loaded = Self.loadedMonsterCards { return loaded }
        let gm = try SaveAndContinueTestsSupport.manager()
        let cards = gm.editionStore.sections(for: "gh").filter { $0.group == "randomMonsterCard" }
        Self.loadedMonsterCards = cards
        return cards
    }

    private static func onTile(_ ref: String, _ x: Int, _ y: Int) -> Bool {
        let grid = TileGrids.grid(for: ref)
        return y >= 0 && y < grid.count && x >= 0 && x < grid[y].count && grid[y][x]
    }

    /// All twenty room cards (534–553), each with its twelve numbers on hexes of its tiles (or the
    /// hex where a room's two tiles meet), its obstacles on other hexes, and its entrances and exits
    /// on half-hexes at a tile's edge.
    func testEveryRoomCardIsWritten() throws {
        XCTAssertEqual(rooms.count, 20)
        XCTAssertEqual(Set(rooms.map(\.card)), Set(534...553))
        XCTAssertEqual(Set(rooms.map(\.name)).count, 20)
        for room in rooms {
            let refs = room.tiles.map(\.ref)
            let seams = room.tiles.compactMap(\.join).map { DungeonRoomCard.Place(tile: refs[0], x: $0.first[0], y: $0.first[1]) }
            func usable(_ place: DungeonRoomCard.Place) -> Bool {
                Self.onTile(place.tile, place.x, place.y) || seams.contains(place)
                    || room.tiles.contains { tile in tile.join.map { [place.x, place.y] == $0.second && place.tile == tile.ref } ?? false }
            }
            XCTAssertEqual(Set(room.numbers.keys), Set((1...12).map(String.init)), room.name)
            XCTAssertEqual(Set(room.numbers.values).count, 12, "\(room.name): two numbers on one hex")
            for (number, place) in room.numbers {
                XCTAssertTrue(refs.contains(place.tile) && usable(place), "\(room.name) \(number) is off its tiles")
            }
            let numbered = Set(room.numbers.values)
            for overlay in room.overlays {
                XCTAssertTrue(["obstacle", "difficult-terrain"].contains(overlay.type), room.name)
                for cell in overlay.cells {
                    let place = DungeonRoomCard.Place(tile: overlay.tile, x: cell[0], y: cell[1])
                    XCTAssertTrue(Self.onTile(overlay.tile, cell[0], cell[1]), "\(room.name) \(overlay.subType) is off its tile")
                    XCTAssertFalse(numbered.contains(place), "\(room.name) \(overlay.subType) covers a number")
                }
            }
            XCTAssertFalse(room.entrances.isEmpty, room.name)
            XCTAssertFalse(room.exits.isEmpty, room.name)
            for passage in room.entrances + room.exits {
                XCTAssertTrue(["A", "B"].contains(passage.type), room.name)
                XCTAssertFalse(Self.onTile(passage.tile, passage.x, passage.y), "\(room.name) \(passage.type) is on the tile, not at its edge")
                let hex = HexCoord(passage.x, passage.y)
                XCTAssertTrue(hex.neighbors.contains { Self.onTile(passage.tile, $0.col, $0.row) }, "\(room.name) \(passage.type) is not at the tile's edge")
            }
            XCTAssertFalse(room.minor.isEmpty || room.major.isEmpty, room.name)
        }
    }

    /// All twenty monster cards (554–573): each number holds one thing at most, every monster is
    /// normal, elite or absent for each count of characters and is in the card's monster list
    /// (the data had a forest imp on Defiled's 1 instead of its 7, "mormal" and "nromal", and
    /// Horrific's lurker missing from its list).
    func testEveryMonsterCardIsWritten() throws {
        let cards = try monsterCards()
        XCTAssertEqual(Set(cards.map(\.index)), Set((554...573).map(String.init)))
        let gm = try SaveAndContinueTestsSupport.manager()
        for card in cards {
            let monsters = card.rooms?.first?.monster ?? []
            let markers = monsters.compactMap(\.marker) + (card.overlays ?? []).compactMap { $0.marker?.stringValue }
            XCTAssertEqual(markers.count, Set(markers).count, "\(card.name): two things on one number")
            XCTAssertTrue(Set(markers).isSubset(of: Set((1...12).map(String.init))), card.name)
            for monster in monsters {
                for type in [monster.type, monster.player2, monster.player3, monster.player4].compactMap({ $0 }) {
                    XCTAssertTrue(["normal", "elite"].contains(type), "\(card.name) \(monster.name): \(type)")
                }
                XCTAssertTrue(card.monsters?.contains(monster.name) == true, "\(card.name) doesn't list \(monster.name)")
                XCTAssertNotNil(gm.editionStore.monsterData(name: monster.name, edition: "gh"), monster.name)
            }
        }
    }

    // MARK: - Drawing and laying out

    private func draw(seed: UInt64) throws -> (RandomDungeon, RandomDungeonMap.Built) {
        var random = GameRandom(seed: seed)
        return try XCTUnwrap(RandomDungeonMap.draw(rooms: rooms, monsterCards: try monsterCards(), random: &random))
    }

    /// RD-1, RD-2: three rooms deep, a room behind every exit of the first two, entered by an
    /// entrance of the exit's type; no room card twice.
    func testEveryExitLeadsToARoomOfItsType() throws {
        for seed in UInt64(1)...200 {
            let (dungeon, _) = try draw(seed: seed)
            var seen: [String] = []
            func walk(_ room: RandomDungeon.Room, depth: Int) throws {
                seen.append(room.room)
                let card = try XCTUnwrap(DungeonCardStore.shared.room(named: room.room))
                XCTAssertEqual(room.next.count, depth < 3 ? card.exits.count : 0, "seed \(seed): \(room.room)")
                for (exit, next) in zip(card.exits, room.next) {
                    let nextCard = try XCTUnwrap(DungeonCardStore.shared.room(named: next.room))
                    XCTAssertEqual(nextCard.entrances[next.entrance].type, exit.type, "seed \(seed)")
                    try walk(next, depth: depth + 1)
                }
            }
            try walk(dungeon.first, depth: 1)
            XCTAssertEqual(seen.count, Set(seen).count, "seed \(seed): a room card twice")
        }
    }

    /// Every room behind a door lies beyond it: whichever way the party goes, no two rooms on the
    /// way share a hex, and every exit of the first two rooms has its door.
    func testEveryRoomIsLaidOutApart() throws {
        for seed in UInt64(1)...200 {
            let (dungeon, built) = try draw(seed: seed)
            // Each door of the map: the rooms on the way to it.
            func walk(_ tile: VGBMapTileData, axis: BoardBuilder.TurnAxis?, rooms: [Set<HexCoord>], depth: Int, card: String) {
                var mine = rooms.last ?? []
                for (y, row) in TileGrids.grid(for: tile.ref).enumerated() {
                    for (x, exists) in row.enumerated() where exists {
                        mine.insert(RandomDungeonMap.global(x, y, turns: tile.turns, axis: axis))
                    }
                }
                for earlier in rooms.dropLast() {
                    XCTAssertTrue(earlier.isDisjoint(with: mine), "seed \(seed): \(card) covers a room before it")
                }
                let doors = tile.doors.filter { $0.subType != "corridor" }
                if depth < 3, let roomCard = DungeonCardStore.shared.room(named: card),
                   roomCard.exits.allSatisfy({ $0.tile != tile.ref }) == false {
                    XCTAssertEqual(doors.count, roomCard.exits.filter { $0.tile == tile.ref }.count, "seed \(seed): \(card) has an exit with no door")
                }
                for door in tile.doors {
                    let hex = RandomDungeonMap.global(door.room1X, door.room1Y, turns: tile.turns, axis: axis)
                    let childAxis: BoardBuilder.TurnAxis = (refPoint: (hex.col, hex.row), origin: (door.room2X, door.room2Y))
                    if door.subType == "corridor" {
                        walk(door.mapTileData, axis: childAxis, rooms: Array(rooms.dropLast()) + [mine], depth: depth, card: card)
                    } else {
                        let next = built.rooms.first { $0.value.card.tiles.contains { $0.ref == door.mapTileData.ref } }?.value.card.name ?? "?"
                        walk(door.mapTileData, axis: childAxis, rooms: rooms.dropLast() + [mine, []], depth: depth + 1, card: next)
                    }
                }
            }
            walk(built.scenario.mapTileData, axis: nil, rooms: [[]], depth: 1, card: dungeon.first.room)
        }
    }

    // MARK: - Playing one

    /// A Random Dungeon set up for a party of two (seeded).
    private func startDungeon(index: String = "rnd", seed: UInt64 = 7) throws -> GameManager {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        GameRandom.shared = GameRandom(seed: seed)
        let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index })
        gm.startScenarioOnBoard(data)
        return gm
    }

    /// RD-1, RD-4: the first room is its room card's map with its monster card's monsters for two
    /// characters on their numbers, and the party starts within two hexes of the entrance.
    func testTheFirstRoomIsSetUpFromItsCards() throws {
        for seed in UInt64(1)...12 { try checkFirstRoom(seed: seed) }
    }

    private func checkFirstRoom(seed: UInt64) throws {
        let gm = try startDungeon(seed: seed)
        let scenario = try XCTUnwrap(gm.game.scenario)
        let dungeon = try XCTUnwrap(scenario.randomDungeon)
        let board = gm.boardCoordinator.boardState
        let card = try XCTUnwrap(DungeonCardStore.shared.room(named: dungeon.first.room))
        let monsterCard = try XCTUnwrap(try monsterCards().first { $0.index == dungeon.first.monsters })
        let placements = RandomDungeonMap.tilePlacements(of: card, entranceTile: card.entrances[0].tile, turns: 0, axis: nil)
        func hex(_ place: DungeonRoomCard.Place) -> HexCoord {
            let placed = placements.first { $0.ref == place.tile } ?? placements[0]
            return RandomDungeonMap.global(place.x, place.y, turns: placed.turns, axis: placed.axis)
        }
        // Each monster the card has for two characters stands on its number, normal or elite.
        let expected = (monsterCard.rooms?.first?.monster ?? []).compactMap { entry -> (String, Bool, HexCoord)? in
            guard let type = entry.monsterType(forPlayerCount: 2), let marker = entry.marker,
                  let place = card.numbers[marker] else { return nil }
            return (entry.name, type == .elite, hex(place))
        }
        XCTAssertFalse(expected.isEmpty)
        let standing = board.piecePositions.compactMap { piece, coord -> (String, Bool, HexCoord)? in
            guard case .monster(let name, _) = piece else { return nil }
            return (name, board.eliteStandees.contains(piece), coord)
        }
        XCTAssertEqual(standing.count, expected.count, "\(dungeon.first.room) with \(monsterCard.name)")
        for (name, elite, coord) in expected {
            XCTAssertTrue(standing.contains { $0.0 == name && $0.1 == elite && $0.2 == coord },
                          "\(elite ? "elite " : "")\(name) should stand on \(coord)")
        }
        // Where the party may start: empty hexes within two of the entrance.
        let entrance = hex(card.entrances[0].place)
        XCTAssertFalse(board.startingLocations.isEmpty)
        for start in board.startingLocations {
            XCTAssertLessThanOrEqual(start.distance(to: entrance), 2)
            XCTAssertNil(board.piece(at: start))
        }
        // The exits are doors, shut.
        XCTAssertEqual(board.doors.filter { !$0.isOpen }.count, card.exits.count)
    }

    /// RD-1: opening an exit sets up the room behind it — its monsters on their numbers — and
    /// the dungeon is three rooms deep.
    func testOpeningAnExitRevealsTheNextRoom() throws {
        for seed in UInt64(1)...12 {
            let gm = try startDungeon(seed: seed)
            let coord = gm.boardCoordinator
            let dungeon = try XCTUnwrap(gm.game.scenario?.randomDungeon)
            var room = dungeon.first
            for depth in 2...3 {
                let door = try XCTUnwrap(coord.boardState.doors.first { !$0.isOpen }, "seed \(seed): no door in room \(depth - 1)")
                let before = Set(coord.boardState.cells.keys)
                coord.openDoor(at: door.coord)
                XCTAssertGreaterThan(coord.boardState.cells.count, before.count, "seed \(seed): no room behind the door")
                let next = try XCTUnwrap(room.next.first { next in
                    let card = DungeonCardStore.shared.room(named: next.room)
                    return card?.tiles.contains { tile in coord.boardState.cells.values.contains { $0.tileRef.lowercased() == tile.ref && !before.contains($0.coord) } } == true
                }, "seed \(seed): the room revealed is none of those drawn")
                XCTAssertTrue(gm.game.scenario?.revealedRooms.count == depth, "seed \(seed)")
                room = next
                // The monsters of the new room stand on it.
                let newCells = Set(coord.boardState.cells.keys).subtracting(before)
                let monsters = coord.boardState.piecePositions.filter { if case .monster = $0.key { return newCells.contains($0.value) }; return false }
                let card = try XCTUnwrap(try monsterCards().first { $0.index == next.monsters })
                let expected = (card.rooms?.first?.monster ?? []).filter { $0.monsterType(forPlayerCount: 2) != nil }.count
                XCTAssertEqual(monsters.count, expected, "seed \(seed): \(next.room) with \(card.name)")
            }
            XCTAssertTrue(room.next.isEmpty)
        }
    }

    /// p.50: a random dungeon may be played instead of any scenario, again and again, and doesn't
    /// progress the campaign — though the party keeps its experience, its gold and the success bonus.
    func testTheDungeonIsAlwaysOfferedAndLeavesTheCampaignAlone() throws {
        let gm = try startDungeon()
        XCTAssertTrue(gm.scenarioManager.availableScenarios(for: "gh").contains { $0.index == "rnd" })
        let brute = try XCTUnwrap(gm.game.characters.first)
        let experience = brute.experience
        gm.scenarioManager.finishScenario(success: true)
        XCTAssertFalse(gm.game.completedScenarios.contains("gh-rnd"))
        XCTAssertGreaterThan(brute.experience, experience, "the success bonus")
        XCTAssertTrue(gm.scenarioManager.availableScenarios(for: "gh").contains { $0.index == "rnd" })
        XCTAssertEqual(gm.scenarioManager.availableScenarios(for: "gh").filter { $0.index != "rnd" }.map(\.index), ["1"],
                       "nothing unlocked")
    }

    // MARK: - Reading the cards

    /// Draws each written room card as the game lays it out, its numbers in red and its
    /// entrances (green) and exits (orange) beside them, to check against the card:
    /// `ROOM_SHEET=trail,armory ROOM_SHEET_OUT=/tmp/rooms swift test --filter testRenderRoomSheet`
    /// (`ROOM_SHEET=all` for every card).
    func testRenderRoomSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard let names = env["ROOM_SHEET"], let out = env["ROOM_SHEET_OUT"] else {
            throw XCTSkip("set ROOM_SHEET and ROOM_SHEET_OUT to render room cards")
        }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let cards = DungeonCardStore.shared.rooms()
        let chosen = names == "all" ? cards : cards.filter { names.lowercased().split(separator: ",").contains(Substring($0.name.lowercased())) }
        for card in chosen {
            let gm = try SaveAndContinueTestsSupport.manager()
            gm.characterManager.addCharacter(name: "brute", edition: "gh")
            // The room alone, with an empty monster card, so nothing hides the numbers.
            let empty = ScenarioData(index: "0", name: "", edition: "gh")
            let room = RandomDungeon.Room(room: card.name, monsters: "0", next: [], entrance: 0)
            let built = try XCTUnwrap(RandomDungeonMap.build(RandomDungeon(first: room, depth: 1),
                                                             room: { _ in card }, monsters: { _ in empty }))
            let coord = gm.boardCoordinator
            coord.startScenario(scenario: built.scenario, playerCount: 2)
            let scene = try XCTUnwrap(coord.boardScene)
            let placements = RandomDungeonMap.tilePlacements(of: card, entranceTile: card.entrances[0].tile, turns: 0, axis: nil)
            func hex(_ place: DungeonRoomCard.Place) -> HexCoord {
                let placed = placements.first { $0.ref == place.tile } ?? placements[0]
                return RandomDungeonMap.global(place.x, place.y, turns: placed.turns, axis: placed.axis)
            }
            func label(_ text: String, at hex: HexCoord, color: SKColor) {
                let node = SKLabelNode(fontNamed: "Helvetica-Bold")
                node.text = text
                node.fontSize = 30
                node.fontColor = color
                node.verticalAlignmentMode = .center
                node.position = scene.sceneCenter(of: hex)
                node.zPosition = 1000
                let plate = SKShapeNode(circleOfRadius: 22)
                plate.fillColor = SKColor(white: 0, alpha: 0.75)
                plate.strokeColor = .clear
                plate.position = node.position
                plate.zPosition = 999
                scene.addChild(plate)
                scene.addChild(node)
            }
            for (number, place) in card.numbers { label(number, at: hex(place), color: .red) }
            for entrance in card.entrances { label("in\(entrance.type)", at: hex(entrance.place), color: .green) }
            for exit in card.exits { label("out\(exit.type)", at: hex(exit.place), color: .orange) }
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 1400, height: 1400))
            view.presentScene(scene)
            let texture = try XCTUnwrap(view.texture(from: scene))
            let rep = NSBitmapImageRep(cgImage: texture.cgImage())
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "\(out)/\(card.name.lowercased()).png"))
        }
    }

    /// Draws map tiles with each hex's tile coordinates, for reading a room card's numbered
    /// hexes, obstacles, entrances and exits off its picture:
    /// `TILE_SHEET=f1b,j2a TILE_SHEET_OUT=/tmp/tiles swift test --filter testRenderTileSheet`
    /// writes `/tmp/tiles/f1b.png`… `TILE_SHEET_TURNS=1` turns each tile 60° clockwise first.
    func testRenderTileSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard let refs = env["TILE_SHEET"], let out = env["TILE_SHEET_OUT"] else {
            throw XCTSkip("set TILE_SHEET and TILE_SHEET_OUT to render tiles")
        }
        let turns = Int(env["TILE_SHEET_TURNS"] ?? "0") ?? 0
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        for ref in refs.split(separator: ",").map({ String($0).lowercased() }) {
            let gm = try SaveAndContinueTestsSupport.manager()
            gm.characterManager.addCharacter(name: "brute", edition: "gh")
            let tile = VGBMapTileData(ref: ref, doors: [], overlays: [], monsters: [], turns: turns)
            let map = VGBScenario(id: 0, title: ref, mapTileData: tile, angle: 0, additionalMonsters: nil)
            let coord = gm.boardCoordinator
            coord.startScenario(scenario: map, playerCount: 1)
            let scene = try XCTUnwrap(coord.boardScene)
            // The tile's hexes in white; the ring just off its edge (where entrances and exits
            // are drawn on the cards) in cyan.
            let grid = TileGrids.grid(for: ref)
            func onTile(_ x: Int, _ y: Int) -> Bool {
                y >= 0 && y < grid.count && x >= 0 && x < grid[y].count && grid[y][x]
            }
            var hexes: [(Int, Int, Bool)] = []
            for y in -1...grid.count {
                for x in -1...(grid.map(\.count).max() ?? 0) {
                    if onTile(x, y) { hexes.append((x, y, true)); continue }
                    let point = HexMath.normaliseAndRotatePoint(turns: 0, refPoint: (0, 0), origin: (0, 0), tileCoord: (x, y))
                    let touches = HexCoord(point.0, point.1).neighbors.contains { onTile($0.col, $0.row) }
                    if touches { hexes.append((x, y, false)) }
                }
            }
            for (x, y, inside) in hexes {
                do {
                    let point = HexMath.normaliseAndRotatePoint(turns: turns, refPoint: (0, 0), origin: (0, 0), tileCoord: (x, y))
                    let node = SKLabelNode(fontNamed: "Helvetica-Bold")
                    node.text = "\(x),\(y)"
                    node.fontSize = inside ? 20 : 16
                    node.fontColor = inside ? .white : .cyan
                    node.verticalAlignmentMode = .center
                    node.position = scene.sceneCenter(of: HexCoord(point.0, point.1))
                    node.zPosition = 1000
                    let plate = SKShapeNode(rectOf: CGSize(width: node.frame.width + 6, height: 24), cornerRadius: 3)
                    plate.fillColor = SKColor(white: 0, alpha: 0.75)
                    plate.strokeColor = .clear
                    plate.position = node.position
                    plate.zPosition = 999
                    scene.addChild(plate)
                    scene.addChild(node)
                }
            }
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 1400, height: 1400))
            view.presentScene(scene)
            scene.camera?.setScale(1.0)
            let texture = try XCTUnwrap(view.texture(from: scene))
            let rep = NSBitmapImageRep(cgImage: texture.cgImage())
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "\(out)/\(ref).png"))
        }
    }
}
