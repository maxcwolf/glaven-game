import XCTest
import SpriteKit
@testable import GlavenGameLib

/// The random dungeon deck (rulebook pp. 50–51): three rooms, each a room card's map with a
/// monster card's figures on its twelve numbered hexes.
@MainActor
final class RandomDungeonTests: XCTestCase {

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
