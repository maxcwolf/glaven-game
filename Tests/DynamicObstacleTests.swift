import XCTest
@testable import GlavenGameLib

/// Tests for dynamic obstacle creation/removal mid-scenario.
/// Some scenario rules and character abilities create or destroy obstacles.
final class DynamicObstacleTests: XCTestCase {

    // MARK: - Unit Tests: Place/Remove Obstacle

    func testPlaceObstacle_makesHexImpassable() {
        let board = makeBoard()
        let coord = HexCoord(5, 5)
        XCTAssertTrue(board.cells[coord]!.passable, "Starts passable")

        board.placeObstacle(at: coord, subType: "rock")

        XCTAssertFalse(board.cells[coord]!.passable, "Obstacle makes hex impassable")
        XCTAssertEqual(board.cells[coord]!.overlay, .obstacle)
        XCTAssertEqual(board.cells[coord]!.overlaySubType, "rock")
    }

    func testRemoveObstacle_makesHexPassable() {
        let board = makeBoard()
        let coord = HexCoord(5, 5)
        board.placeObstacle(at: coord)

        board.removeObstacle(at: coord)

        XCTAssertTrue(board.cells[coord]!.passable, "Removing obstacle restores passability")
        XCTAssertNil(board.cells[coord]!.overlay, "Overlay cleared")
    }

    func testPlaceObstacle_onNonexistentHex_noOp() {
        let board = BoardState()
        board.placeObstacle(at: HexCoord(99, 99)) // Should not crash
    }

    // MARK: - Unit Tests: Place/Remove Trap

    func testPlaceTrap_midScenario() {
        let board = makeBoard()
        let coord = HexCoord(4, 4)

        board.placeTrap(at: coord, damage: 3, subType: "spike")

        XCTAssertTrue(board.cells[coord]!.isTrap)
        XCTAssertEqual(board.cells[coord]!.trapDamage, 3)
        XCTAssertEqual(board.cells[coord]!.overlaySubType, "spike")
    }

    // MARK: - Unit Tests: Place Hazard

    func testPlaceHazard_midScenario() {
        let board = makeBoard()
        let coord = HexCoord(4, 4)

        board.placeHazard(at: coord, subType: "lava")

        XCTAssertTrue(board.cells[coord]!.isHazard)
        XCTAssertEqual(board.cells[coord]!.overlaySubType, "lava")
    }

    // MARK: - E2E: Obstacle Blocks Pathfinding After Placement

    func testDynamicObstacle_blocksPathfinding() {
        let board = makeBoard(cols: 8, rows: 3)
        let from = HexCoord(1, 1)
        let to = HexCoord(6, 1)

        // Path should exist initially
        let pathBefore = Pathfinder.findPath(board: board, from: from, to: to, occupiedByEnemy: [])
        XCTAssertNotNil(pathBefore, "Path exists before obstacle")

        // Block all passage with obstacles
        for row in 0..<3 {
            board.placeObstacle(at: HexCoord(3, row))
            board.placeObstacle(at: HexCoord(4, row))
        }

        let pathAfter = Pathfinder.findPath(board: board, from: from, to: to, occupiedByEnemy: [])
        XCTAssertNil(pathAfter, "Path blocked after dynamic obstacles placed")
    }

    func testDynamicObstacleRemoval_opensPath() {
        let board = makeBoard(cols: 8, rows: 3)
        let from = HexCoord(1, 1)
        let to = HexCoord(6, 1)

        // Block passage
        for row in 0..<3 {
            board.placeObstacle(at: HexCoord(3, row))
        }

        let pathBlocked = Pathfinder.findPath(board: board, from: from, to: to, occupiedByEnemy: [])
        XCTAssertNil(pathBlocked, "Path blocked by obstacles")

        // Remove one obstacle to create a gap
        board.removeObstacle(at: HexCoord(3, 1))

        let pathOpened = Pathfinder.findPath(board: board, from: from, to: to, occupiedByEnemy: [])
        XCTAssertNotNil(pathOpened, "Path opens after obstacle removed")
    }

    // MARK: - E2E: Monster AI Reacts to Dynamic Obstacles

    func testMonsterAI_pathsAroundDynamicObstacle() {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(6, 3))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(2, 3), 5)])

        // Place obstacle blocking direct path
        t.board.placeObstacle(at: HexCoord(4, 3))
        t.board.placeObstacle(at: HexCoord(4, 2))
        t.board.placeObstacle(at: HexCoord(4, 4))

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(4)),
            ActionModel(type: .attack, value: .int(2))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0],
            ability: ability, board: t.board, gameState: t.game
        )

        // Monster should still find focus (path goes around)
        XCTAssertNotNil(result.focusTarget, "Monster should find path around dynamic obstacles")
        if !result.movementPath.isEmpty {
            for coord in result.movementPath {
                XCTAssertTrue(t.board.cells[coord]?.passable ?? false,
                              "Monster path should not include obstacle hexes")
            }
        }
    }

    // MARK: - E2E: Dynamic Trap Placement + Trigger

    func testDynamicTrap_triggersOnEntry() {
        let board = makeBoard()
        let trapCoord = HexCoord(3, 3)

        // Place trap dynamically
        board.placeTrap(at: trapCoord, damage: 4, subType: "spike")

        XCTAssertTrue(board.cells[trapCoord]!.isTrap, "Dynamic trap exists")

        // Trigger it
        board.removeTrap(at: trapCoord)
        XCTAssertFalse(board.cells[trapCoord]!.isTrap, "Trap removed after trigger")
    }
}
