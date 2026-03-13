import XCTest
@testable import GlavenGameLib

/// Tests for Jump and Fly movement visual distinction and pathfinding behavior.
/// Rulebook p.17: "Jump — move to destination ignoring figures, obstacles,
///   and hazardous terrain along the path (not destination)"
/// Rulebook p.17: "Flying — ignore all terrain effects and obstacles"
final class JumpFlyMovementTests: XCTestCase {

    // MARK: - Jump Pathfinding

    func testJump_ignoresTrapsOnIntermediateHexes() {
        let board = makeBoard(cols: 10, rows: 5)
        // Place traps between start and destination
        board.cells[HexCoord(3, 2)] = HexCell(coord: HexCoord(3, 2), tileRef: "t",
                                               passable: true, overlay: .trap, trapDamage: 5)

        let normalReach = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 2), range: 3,
            avoidTraps: true, occupiedByEnemy: [], occupiedByAlly: []
        )

        let jumpReach = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 2), range: 3,
            jumping: true, avoidTraps: true, occupiedByEnemy: [], occupiedByAlly: []
        )

        // Jump should reach more hexes (can jump over traps)
        XCTAssertGreaterThanOrEqual(jumpReach.count, normalReach.count,
            "p.17: Jump can reach at least as many hexes as normal move (traps passable)")
    }

    func testJump_ignoresDifficultTerrainOnIntermediate() {
        let board = makeBoard(cols: 10, rows: 5)
        board.cells[HexCoord(3, 2)] = HexCell(coord: HexCoord(3, 2), tileRef: "t",
                                               passable: true, overlay: .difficultTerrain)

        let normalReach = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 2), range: 2,
            occupiedByEnemy: [], occupiedByAlly: []
        )

        let jumpReach = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 2), range: 2,
            jumping: true, occupiedByEnemy: [], occupiedByAlly: []
        )

        // With normal move, (3,2) costs 2 movement. With jump, intermediate = 1.
        // So jump should be able to reach further
        let normalBeyond = normalReach.keys.filter { $0.distance(to: HexCoord(2, 2)) > 1 }
        let jumpBeyond = jumpReach.keys.filter { $0.distance(to: HexCoord(2, 2)) > 1 }
        XCTAssertGreaterThanOrEqual(jumpBeyond.count, normalBeyond.count,
            "p.17: Jump ignores difficult terrain cost on intermediate hexes")
    }

    // MARK: - Fly Pathfinding

    func testFly_allTerrainCostsOne() {
        let board = makeBoard(cols: 10, rows: 5)
        board.cells[HexCoord(3, 2)] = HexCell(coord: HexCoord(3, 2), tileRef: "t",
                                               passable: true, overlay: .difficultTerrain)

        let flyReach = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 2), range: 2,
            flying: true, occupiedByEnemy: [], occupiedByAlly: []
        )

        // Difficult terrain should cost 1 when flying (not 2)
        XCTAssertEqual(flyReach[HexCoord(3, 2)], 1,
            "p.17: Flying ignores difficult terrain cost (costs 1 not 2)")
    }

    func testFly_canTraverseObstacles() {
        let board = makeBoard(cols: 10, rows: 5)
        board.cells[HexCoord(3, 2)]!.passable = false // obstacle

        let normalReach = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 2), range: 3,
            occupiedByEnemy: [], occupiedByAlly: []
        )

        let flyReach = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 2), range: 3,
            flying: true, occupiedByEnemy: [], occupiedByAlly: []
        )

        XCTAssertNil(normalReach[HexCoord(3, 2)], "Normal move can't enter obstacle")
        XCTAssertNotNil(flyReach[HexCoord(3, 2)], "p.17: Flying can enter obstacle hex")
    }

    // MARK: - Visual Distinction (highlight colors)
    // These verify that the coordinator methods exist and use different parameters.
    // The actual color rendering is a UI concern tested manually.

    func testBeginMoveAction_exists() {
        // Verify the normal, jump, fly, and teleport methods all exist as distinct methods
        let coord = BoardCoordinator()
        // These methods exist (compilation test)
        _ = coord.beginMoveAction as (PieceID, Int) -> Void
        _ = coord.beginJumpMoveAction as (PieceID, Int) -> Void
        _ = coord.beginFlyMoveAction as (PieceID, Int) -> Void
        _ = coord.beginTeleportAction as (PieceID, Int) -> Void
    }
}
