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
