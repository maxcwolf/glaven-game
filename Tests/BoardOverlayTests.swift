import XCTest
import SpriteKit
@testable import GlavenGameLib

/// Overlays (obstacles, traps, terrain) are drawn on every hex they cover, so a hex that blocks
/// movement never looks like open floor.
@MainActor
final class BoardOverlayTests: XCTestCase {

    /// Start `index` with every room revealed.
    private func boardWithAllRooms(_ index: String) throws -> BoardCoordinator {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        for character in gm.game.characters {
            let free = coord.boardState.startingLocations.first { !coord.boardState.isOccupied($0) }!
            coord.placeCharacter(characterID: character.id, at: free)
        }
        coord.finishSetup()
        coord.openScenarioRooms((scenario.rooms ?? []).compactMap(\.roomNumber))
        return coord
    }

    /// Every hex of every multi-hex overlay in the revealed map gets a sprite.
    func testMultiHexObstaclesAreDrawnOnEveryHex() throws {
        for index in ["1", "11", "32", "34", "52", "72"] {
            let coord = try boardWithAllRooms(index)
            let scene = try XCTUnwrap(coord.boardScene)
            let drawn = Set(scene.overlaySpriteNames)
            let map = try XCTUnwrap(coord.scenarioData)
            let visible = Set(coord.boardState.cells.keys)
            let multiHex = ScenarioMapBuilder.build(from: map).overlays.filter { overlay in
                overlay.cells.count > 1 && overlay.imageName.hasPrefix("obstacle")
                    && visible.contains(HexCoord(overlay.col, overlay.row))
            }
            XCTAssertFalse(multiHex.isEmpty, "scenario \(index) has multi-hex obstacles")
            for overlay in multiHex {
                for cell in overlay.cells {
                    XCTAssertTrue(drawn.contains("overlay_\(cell.0)_\(cell.1)"),
                                  "scenario \(index): \(overlay.imageName) is drawn at \(cell)")
                }
            }
        }
    }

    /// Regression: the scene's row offset was odd for over half the scenarios (GH 2 starts at
    /// −5), which flipped the hex rows' stagger, so figures, obstacles and highlights sat half a
    /// hex off the tile art on every other row. However a board is offset, two hexes must sit
    /// as far apart on screen as they do on the map the tiles are drawn from — at the start
    /// and after every door opens.
    func testHexesLineUpWithTheTileArtInEveryScenario() throws {
        for number in 1...95 {
            let index = String(number)
            guard ScenarioMapStore.shared.scenarioMap(for: index) != nil else { continue }
            let gm = try SaveAndContinueTestsSupport.manager()
            gm.characterManager.addCharacter(name: "brute", edition: "gh")
            guard let scenario = gm.editionStore.scenarios(for: "gh").first(where: { $0.index == index && $0.solo == nil })
            else { continue }
            gm.startScenarioOnBoard(scenario)
            let coord = gm.boardCoordinator
            coord.autoResolvePrompts = true
            coord.turnDelayNanoseconds = 0
            var opened = 0
            repeat {
                let scene = try XCTUnwrap(coord.boardScene)
                let hexes = coord.boardState.cells.keys.sorted()
                let origin = try XCTUnwrap(hexes.first)
                let originOnScreen = scene.sceneCenter(of: origin)
                let originOnMap = HexMath.hexToPixel(col: origin.col, row: origin.row)
                for hex in hexes {
                    let onScreen = scene.sceneCenter(of: hex)
                    let onMap = HexMath.hexToPixel(col: hex.col, row: hex.row)
                    // Map y runs down, scene y up.
                    let misfit = hypot((onScreen.x - originOnScreen.x) - (onMap.x - originOnMap.x),
                                       (onScreen.y - originOnScreen.y) + (onMap.y - originOnMap.y))
                    if misfit > 0.5 {
                        return XCTFail("scenario \(index), after \(opened) doors: \(hex) is \(misfit) off the tile art")
                    }
                }
                guard let door = coord.boardState.doors.first(where: { !$0.isOpen }), opened < 30 else { break }
                coord.openDoor(at: door.coord)
                opened += 1
            } while true
        }
    }

    func testGridOriginsKeepTheRowStagger() {
        for minRow in -7...7 {
            XCTAssertEqual(HexMath.gridOrigin(minCol: 0, minRow: minRow).row & 1, 0, "minRow \(minRow)")
            XCTAssertLessThanOrEqual(HexMath.gridOrigin(minCol: 0, minRow: minRow).row, minRow - 2, "at least the padding")
        }
    }

    func testPiecesUseTheirOwnArtWhenItExists() {
        XCTAssertEqual(BoardScene.overlayPieceName("obstacle-boulder-3", index: 0), "obstacle-boulder-3")
        XCTAssertEqual(BoardScene.overlayPieceName("obstacle-boulder-3", index: 1), "obstacle-boulder-3-2")
        XCTAssertEqual(BoardScene.overlayPieceName("obstacle-boulder-3", index: 2), "obstacle-boulder-3-3")
        XCTAssertEqual(BoardScene.overlayPieceName("obstacle-table", index: 1), "obstacle-table-2")
        // Art without a separate second piece repeats the first.
        XCTAssertEqual(BoardScene.overlayPieceName("obstacle-altar", index: 1), "obstacle-altar")
    }

    /// Renders a scenario's whole map to a PNG for visual review:
    /// `BOARD_RENDER=32 BOARD_RENDER_OUT=/tmp/s32.png swift test --filter testRenderScenarioMap`
    func testRenderScenarioMap() throws {
        let env = ProcessInfo.processInfo.environment
        guard let index = env["BOARD_RENDER"], let out = env["BOARD_RENDER_OUT"] else {
            throw XCTSkip("set BOARD_RENDER and BOARD_RENDER_OUT to render a map")
        }
        let coord = try boardWithAllRooms(index)
        let scene = try XCTUnwrap(coord.boardScene)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 2200, height: 1700))
        view.presentScene(scene)
        scene.camera?.setScale(1.6)
        let texture = try XCTUnwrap(view.texture(from: scene))
        let image = texture.cgImage()
        let rep = NSBitmapImageRep(cgImage: image)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: out))
    }
}
