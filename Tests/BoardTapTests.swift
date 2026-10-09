import XCTest
import SpriteKit
@testable import GlavenGameLib

/// A tap anywhere inside a hex means that hex (or the figure on it), never a neighbour.
@MainActor
final class BoardTapTests: XCTestCase {

    /// Hex centres, and points well inside each hex, map back to that hex for both row parities
    /// and any grid offset.
    func testPointsInsideAHexResolveToIt() {
        let inradius = HexMath.cellStepX / 2
        for offset in [(0, 0), (-3, -2), (2, 5)] {
            let scene = BoardScene(size: CGSize(width: 800, height: 600))
            for row in -2...3 {
                for col in -2...3 {
                    let hex = HexCoord(col + offset.0, row + offset.1)
                    let p = HexMath.hexToPixel(col: col, row: row)
                    let center = CGPoint(x: p.x + HexMath.cellStepX / 2, y: -(p.y + HexMath.cellSize / 2))
                    XCTAssertEqual(BoardScene.hex(at: center, offsetCol: offset.0, offsetRow: offset.1), hex)
                    for step in 0..<12 {
                        let angle = CGFloat(step) * .pi / 6
                        let near = CGPoint(x: center.x + cos(angle) * inradius * 0.85,
                                           y: center.y + sin(angle) * inradius * 0.85)
                        XCTAssertEqual(BoardScene.hex(at: near, offsetCol: offset.0, offsetRow: offset.1), hex,
                                       "\(hex) at \(step * 30)°")
                    }
                }
            }
            _ = scene
        }
    }

    /// Regression: a tap on a target's hex outside its token did nothing, and a tap near a
    /// highlighted hex's edge could pick the hex above or below.
    func testTapsGoToTheFigureOnTheHexOrTheHighlightedHex() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        let scene = try XCTUnwrap(coord.boardScene)
        var pieceTaps: [PieceID] = []
        var hexTaps: [HexCoord] = []
        scene.onPieceTap = { pieceTaps.append($0) }
        scene.onHexTap = { hexTaps.append($0) }

        // A monster: tap inside its hex but outside the token and its HP bar.
        let (monster, monsterHex) = try XCTUnwrap(coord.boardState.piecePositions
            .filter { if case .monster = $0.key { return true }; return false }
            .sorted { $0.key < $1.key }.first)
        let center = scene.sceneCenter(of: monsterHex)
        scene.handleTap(at: CGPoint(x: center.x - 31, y: center.y - 18))
        XCTAssertEqual(pieceTaps, [monster])

        // Every empty hex highlighted (as for a long move or teleport): taps in the band where a
        // hex's frame overlaps its lower neighbours' always pick the hex they are in.
        let empties = coord.boardState.cells.keys.filter { !coord.boardState.isOccupied($0) }
        scene.highlightHexes(Set(empties), style: .move, offsetCol: coord.offsetCol, offsetRow: coord.offsetRow)
        for hex in empties.sorted() {
            let c = scene.sceneCenter(of: hex)
            for dx in [-20.0, 20.0] {
                hexTaps = []
                scene.handleTap(at: CGPoint(x: c.x + dx, y: c.y - 30))
                XCTAssertEqual(hexTaps, [hex], "tap low in \(hex)")
            }
        }
        let empty = try XCTUnwrap(empties.sorted().first)
        scene.clearHighlights()
        hexTaps = []

        // An empty hex that isn't highlighted does nothing.
        XCTAssertFalse(scene.handleTap(at: scene.sceneCenter(of: empty)))
        XCTAssertEqual(hexTaps, [])
    }
}
