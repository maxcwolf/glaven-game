import XCTest
@testable import GlavenGameLib

/// Regression tests for difficult-terrain movement-cost accounting in Pathfinder.
///
/// Difficult terrain costs 2 movement to enter (Gloomhaven p.10). Two bugs:
///  - pathCost returned the cost of the first hop-count path to reach the target
///    (FIFO BFS early-return) rather than the minimal-cost path.
///  - findPath ignored terrain cost entirely (pure hop-count BFS), so it could
///    return a path whose movement cost exceeds the cheapest available route.
///
/// Board layout (row 1 is a straight line of difficult terrain):
///   (0,1) -> (1,1)* -> (2,1)* -> (3,1)   straight: cost 2+2+1 = 5
/// A detour through rows 0/2 reaches (3,1) for cost 4, so the true minimum is 4.
final class PathfinderTerrainTests: XCTestCase {

    private func difficultBoard() -> BoardState {
        let board = makeBoard(cols: 6, rows: 3)
        board.cells[HexCoord(1, 1)]!.overlay = .difficultTerrain
        board.cells[HexCoord(2, 1)]!.overlay = .difficultTerrain
        return board
    }

    private func pathCost(_ p: [HexCoord], board: BoardState) -> Int {
        p.dropFirst().reduce(0) { $0 + (board.cells[$1]!.isDifficultTerrain ? 2 : 1) }
    }

    func testPathCost_returnsMinimalCostAroundDifficultTerrain() {
        let board = difficultBoard()
        // Oracle: reachableHexes is already cost-correct.
        let oracle = Pathfinder.reachableHexes(board: board, from: HexCoord(0, 1), range: 20)[HexCoord(3, 1)]
        XCTAssertEqual(oracle, 4, "sanity: the cheapest route to (3,1) costs 4")

        let cost = Pathfinder.pathCost(board: board, from: HexCoord(0, 1), to: HexCoord(3, 1))
        XCTAssertEqual(cost, 4, "pathCost must return the minimal-cost path (4), not the hop-first path (5)")
    }

    func testFindPath_respectsDifficultTerrainCost() {
        let board = difficultBoard()
        let path = Pathfinder.findPath(board: board, from: HexCoord(0, 1), to: HexCoord(3, 1))
        XCTAssertNotNil(path, "a path must exist")
        XCTAssertEqual(path?.first, HexCoord(0, 1), "path starts at the origin")
        XCTAssertEqual(path?.last, HexCoord(3, 1), "path ends at the destination")
        XCTAssertEqual(pathCost(path!, board: board), 4,
                       "findPath must return a movement-cost-minimal path (4), not a hop-count path (5)")
    }

    func testFindPath_unchangedOnUniformBoard() {
        // Guard: with no difficult terrain, the path is still a shortest (hop == cost) path.
        let board = makeBoard(cols: 6, rows: 3)
        let path = Pathfinder.findPath(board: board, from: HexCoord(0, 1), to: HexCoord(3, 1))
        XCTAssertEqual(pathCost(path!, board: board), 3, "uniform board: cost equals hop count (3)")
    }
}
