import XCTest
@testable import GlavenGameLib

/// Regression tests for line-of-sight blocking.
///
/// The corner-to-corner intersection test used strict inequalities, so a line that
/// entered/exited a blocker exactly at its vertices was treated as unblocked — LOS
/// leaked through obstacles. The clearest manifestation: a *solid wall* of obstacles
/// directly between two hexes failed to block sight.
///
/// Note: whether a SINGLE obstacle at distance 2 blocks LOS is geometry-dependent in
/// Gloomhaven (corner lines can "see around" it), so that case is intentionally not
/// asserted here — only the unambiguous wall and the open-board controls are.
final class LineOfSightTests: XCTestCase {

    func testLOS_clearOnOpenBoard() {
        let board = makeBoard(cols: 12, rows: 12)
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(3, 4), to: HexCoord(5, 4), board: board),
                      "open board: LOS exists")
    }

    func testLOS_blockedBySolidWall() {
        let board = makeBoard(cols: 12, rows: 12)
        // A complete vertical wall of obstacles spanning column 4 between the two hexes.
        board.cells[HexCoord(4, 3)]!.passable = false
        board.cells[HexCoord(4, 4)]!.passable = false
        board.cells[HexCoord(4, 5)]!.passable = false
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(3, 4), to: HexCoord(5, 4), board: board),
                       "a solid wall of obstacles between the hexes blocks LOS")
    }

    func testLOS_clearWhenObstacleOffToTheSide() {
        let board = makeBoard(cols: 12, rows: 12)
        board.cells[HexCoord(4, 0)]!.passable = false  // nowhere near the sight line
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(3, 4), to: HexCoord(5, 4), board: board),
                      "an obstacle far off the sight line does not block LOS")
    }

    func testLOS_adjacentAlwaysVisibleEvenNextToObstacle() {
        let board = makeBoard(cols: 12, rows: 12)
        board.cells[HexCoord(5, 5)]!.passable = false
        let from = HexCoord(5, 6)
        for neighbor in from.neighbors where board.cells[neighbor]?.passable == true {
            XCTAssertTrue(LineOfSight.hasLOS(from: from, to: neighbor, board: board),
                          "adjacent hexes always have LOS")
        }
    }
}
