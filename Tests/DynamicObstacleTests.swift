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

    func testMonsterAI_pathsAroundDynamicObstacle() throws {
        let t = TestGame()
        let character = t.addCharacter(pos: HexCoord(6, 3))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(2, 3), 5)])

        // Place obstacles blocking the direct path: a wall down column 4 with its only gap
        // five rows below the monster.
        let wall = (0...7).map { HexCoord(4, $0) }
        for hex in wall { t.board.placeObstacle(at: hex) }

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
        XCTAssertEqual(result.focusTarget, .character(character.id), "Monster should find path around dynamic obstacles")
        XCTAssertEqual(result.movementPath.count - 1, 4, "it moves its whole Move 4 along the way round")
        for coord in result.movementPath {
            XCTAssertTrue(t.board.cells[coord]?.passable ?? false,
                          "Monster path should not include obstacle hexes")
            XCTAssertFalse(wall.contains(coord))
        }
        let end = try XCTUnwrap(result.movementPath.last)
        XCTAssertLessThan(end.distance(to: HexCoord(4, 8)), HexCoord(2, 3).distance(to: HexCoord(4, 8)), "toward the gap")
        XCTAssertLessThan(end.col, 4, "still on its own side of the wall")
        XCTAssertTrue(result.attackTargets.isEmpty, "the way round is too long to attack this turn")

        // With the obstacle in its line removed, the same monster walks straight up and attacks.
        t.board.removeObstacle(at: HexCoord(4, 3))
        let direct = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0],
            ability: ability, board: t.board, gameState: t.game
        )
        XCTAssertEqual(direct.movementPath.count - 1, 3)
        XCTAssertEqual(direct.movementPath.last, HexCoord(5, 3))
        XCTAssertEqual(direct.attackTargets, [.character(character.id)])
    }

    // MARK: - E2E: Dynamic Trap Placement + Trigger

    /// A trap a card places is sprung by the first figure to walk onto it, for the damage the
    /// card gave it (not the scenario level's), and is gone afterwards.
    @MainActor func testDynamicTrap_triggersOnEntry() async throws {
        let board = try RuleBoard(level: 1)
        let trapCoord = HexCoord(3, 3)
        board.coord.boardState.placeTrap(at: trapCoord, damage: 4, subType: "spike")
        XCTAssertTrue(board.coord.boardState.cells[trapCoord]!.isTrap, "Dynamic trap exists")

        let walker = try board.monster(at: HexCoord(2, 3))
        await board.coord.moveAlong(walker.piece, path: [HexCoord(2, 3), trapCoord, HexCoord(4, 3)], style: .normal)
        XCTAssertEqual(walker.entity.health, 30 - 4, "the trap's own 4 damage, where the level's would be 3")
        XCTAssertFalse(board.coord.boardState.cells[trapCoord]!.isTrap, "Trap removed after trigger")
        XCTAssertEqual(board.hex(walker.piece), HexCoord(4, 3), "and the walk goes on")

        // The next to pass that way finds nothing.
        let second = try board.monster(at: HexCoord(2, 4))
        await board.coord.moveAlong(second.piece, path: [HexCoord(2, 4), trapCoord], style: .normal)
        XCTAssertEqual(second.entity.health, 30)
    }
}
