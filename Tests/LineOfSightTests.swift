import XCTest
@testable import GlavenGameLib

/// Line-of-sight rules (GH rulebook): LOS exists if a line can be drawn from any corner of the
/// attacker's hex to any corner of the target's hex without touching a wall. Only walls block
/// LOS — void hexes (not on the revealed map) and `.wall` overlays. Obstacles, traps, hazards,
/// difficult terrain and figures do NOT block LOS.
///
/// Board geometry is pointy-top, odd-row offset: odd rows are shifted half a hex to the right.
final class LineOfSightTests: XCTestCase {

    // MARK: - Helpers

    /// Board with only the given cells.
    private func board(with coords: [HexCoord]) -> BoardState {
        let board = BoardState()
        for coord in coords {
            board.cells[coord] = HexCell(coord: coord, tileRef: "test", passable: true)
        }
        return board
    }

    /// Mark a cell as an obstacle (impassable, but transparent for LOS).
    private func placeObstacle(_ board: BoardState, _ coord: HexCoord) {
        board.cells[coord]!.passable = false
        board.cells[coord]!.overlay = .obstacle
    }

    /// Mark a cell as a wall overlay (blocks LOS).
    private func placeWall(_ board: BoardState, _ coord: HexCoord) {
        board.cells[coord]!.passable = false
        board.cells[coord]!.overlay = .wall
    }

    // MARK: - Open board

    func testLOS_clearOnOpenBoard() {
        let board = makeBoard(cols: 12, rows: 12)
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(3, 4), to: HexCoord(5, 4), board: board))
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(1, 1), to: HexCoord(10, 10), board: board))
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(0, 11), to: HexCoord(11, 0), board: board))
    }

    func testLOS_sameHex() {
        let board = makeBoard(cols: 4, rows: 4)
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(1, 1), to: HexCoord(1, 1), board: board))
    }

    // MARK: - Obstacles and other overlays never block

    func testLOS_notBlockedBySolidLineOfObstacles() {
        let board = makeBoard(cols: 12, rows: 12)
        // A complete vertical barrier of obstacles spanning column 4 between the hexes.
        placeObstacle(board, HexCoord(4, 3))
        placeObstacle(board, HexCoord(4, 4))
        placeObstacle(board, HexCoord(4, 5))
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(3, 4), to: HexCoord(5, 4), board: board),
                      "obstacles do not hinder ranged attacks")
    }

    func testLOS_notBlockedByObstacleDirectlyBetween() {
        let board = makeBoard(cols: 12, rows: 12)
        placeObstacle(board, HexCoord(4, 4))
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(2, 4), to: HexCoord(6, 4), board: board))
    }

    func testLOS_notBlockedByTrapsHazardsDifficultTerrainOrFigures() {
        let board = makeBoard(cols: 12, rows: 12)
        board.cells[HexCoord(4, 3)]!.overlay = .trap
        board.cells[HexCoord(4, 4)]!.overlay = .hazard
        board.cells[HexCoord(4, 5)]!.overlay = .difficultTerrain
        board.placePiece(.monster(name: "blocker", standee: 1), at: HexCoord(4, 4))
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(3, 4), to: HexCoord(5, 4), board: board))
    }

    // MARK: - Walls block

    func testLOS_blockedByWallOverlays() {
        let board = makeBoard(cols: 12, rows: 12)
        placeWall(board, HexCoord(4, 3))
        placeWall(board, HexCoord(4, 4))
        placeWall(board, HexCoord(4, 5))
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(3, 4), to: HexCoord(5, 4), board: board),
                       "a solid wall between the hexes blocks LOS")
    }

    func testLOS_blockedByVoidHexes() {
        let board = makeBoard(cols: 12, rows: 12)
        // Hexes that aren't on the map (gap between tiles) are walls.
        board.cells[HexCoord(4, 3)] = nil
        board.cells[HexCoord(4, 4)] = nil
        board.cells[HexCoord(4, 5)] = nil
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(3, 4), to: HexCoord(5, 4), board: board))
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(5, 4), to: HexCoord(3, 4), board: board))
    }

    func testLOS_blockedAcrossVoidBetweenTwoCorridors() {
        // Two parallel corridors (rows 2 and 4) with nothing on the map in row 3.
        var coords: [HexCoord] = []
        for col in 0..<10 {
            coords.append(HexCoord(col, 2))
            coords.append(HexCoord(col, 4))
        }
        let board = board(with: coords)

        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(2, 2), to: HexCoord(2, 4), board: board),
                       "the void row between the corridors is a wall")
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(2, 2), to: HexCoord(6, 4), board: board))
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(0, 4), to: HexCoord(9, 2), board: board))
        // Within the same corridor sight is clear.
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(0, 2), to: HexCoord(9, 2), board: board))
    }

    func testLOS_throughGapBetweenCorridors() {
        // Same two corridors, joined by one hex (5,3) in the otherwise-void row.
        var coords: [HexCoord] = [HexCoord(5, 3)]
        for col in 0..<10 {
            coords.append(HexCoord(col, 2))
            coords.append(HexCoord(col, 4))
        }
        let board = board(with: coords)

        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(5, 2), to: HexCoord(5, 4), board: board),
                      "a straight line through the opening is clear")
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(1, 2), to: HexCoord(1, 4), board: board),
                       "far from the opening the void still blocks")
    }

    func testLOS_aroundCornerOfLShapedRoom() {
        // L-shaped room: a horizontal arm (rows 0-1, cols 0-7) and a vertical arm (rows 0-7, cols 0-1).
        var coords: [HexCoord] = []
        for row in 0..<8 {
            for col in 0..<8 where row <= 1 || col <= 1 {
                coords.append(HexCoord(col, row))
            }
        }
        let board = board(with: coords)
        // Ends of the two arms can't see each other: the void square between them is in the way.
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(7, 1), to: HexCoord(1, 7), board: board))
        // The corner hex sees down both arms.
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(0, 0), to: HexCoord(7, 1), board: board))
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(0, 0), to: HexCoord(0, 7), board: board))
    }

    // MARK: - Corner grazing

    func testLOS_lineGrazingWallCornerIsNotBlocked() {
        let board = makeBoard(cols: 12, rows: 12)
        board.cells[HexCoord(4, 3)] = nil
        board.cells[HexCoord(4, 4)] = nil
        // The only clear line runs along the bottom of row 4, touching the void hex (4,4) only
        // at its bottom corner — the corner shared with the open hexes (3,5) and (4,5).
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(3, 4), to: HexCoord(5, 4), board: board),
                      "touching a single corner of a wall hex does not block")
    }

    func testLOS_lineThroughVoidInteriorIsBlocked() {
        let board = makeBoard(cols: 12, rows: 12)
        board.cells[HexCoord(4, 3)] = nil
        board.cells[HexCoord(4, 4)] = nil
        // Removing (3,5) too: the grazing line from the previous test now passes through the
        // interior of a void hex.
        board.cells[HexCoord(3, 5)] = nil
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(3, 4), to: HexCoord(5, 4), board: board))
    }

    func testLOS_seesPastSingleVoidHex() {
        let board = makeBoard(cols: 12, rows: 12)
        board.cells[HexCoord(4, 5)] = nil
        // A single wall hex in the middle of a row can be seen around (corner-to-corner).
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(2, 5), to: HexCoord(6, 5), board: board))
    }

    // MARK: - Adjacency

    func testLOS_adjacentAlwaysVisible() {
        let board = makeBoard(cols: 12, rows: 12)
        placeWall(board, HexCoord(5, 5))
        board.cells[HexCoord(6, 5)] = nil
        for from in [HexCoord(5, 6), HexCoord(4, 5), HexCoord(6, 6)] {
            for neighbor in from.neighbors where board.cells[neighbor]?.passable == true {
                XCTAssertTrue(LineOfSight.hasLOS(from: from, to: neighbor, board: board),
                              "adjacent hexes \(from)->\(neighbor) always have LOS")
            }
        }
    }

    func testLOS_adjacentCellsWithEverythingElseVoid() {
        // Two adjacent cells in each direction, nothing else on the map.
        for (i, neighbor) in HexCoord(4, 4).neighbors.enumerated() {
            let board = board(with: [HexCoord(4, 4), neighbor])
            XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(4, 4), to: neighbor, board: board),
                          "direction \(i)")
        }
        for (i, neighbor) in HexCoord(3, 3).neighbors.enumerated() {
            let board = board(with: [HexCoord(3, 3), neighbor])
            XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(3, 3), to: neighbor, board: board),
                          "odd row, direction \(i)")
        }
    }

    // MARK: - Properties

    func testLOS_isSymmetric() {
        // Deterministic pseudo-random walls; LOS must be the same in both directions.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return seed
        }
        for _ in 0..<3 {
            let board = makeBoard(cols: 8, rows: 8)
            for coord in Array(board.cells.keys) {
                switch next() % 7 {
                case 0: board.cells[coord] = nil
                case 1: board.cells[coord]!.overlay = .wall
                case 2: board.cells[coord]!.overlay = .obstacle
                default: break
                }
            }
            let coords = Array(board.cells.keys)
            for a in coords {
                for b in coords {
                    XCTAssertEqual(LineOfSight.hasLOS(from: a, to: b, board: board),
                                   LineOfSight.hasLOS(from: b, to: a, board: board),
                                   "LOS \(a)<->\(b) must be symmetric")
                }
            }
        }
    }

    func testLOS_obstaclesNeverChangeVisibility() {
        // Converting every non-endpoint cell into an obstacle must not change any LOS result.
        let open = makeBoard(cols: 8, rows: 8)
        open.cells[HexCoord(3, 3)] = nil
        open.cells[HexCoord(3, 4)] = nil
        let cluttered = makeBoard(cols: 8, rows: 8)
        cluttered.cells[HexCoord(3, 3)] = nil
        cluttered.cells[HexCoord(3, 4)] = nil
        for coord in Array(cluttered.cells.keys) where (coord.col + coord.row) % 2 == 0 {
            cluttered.cells[coord]!.passable = false
            cluttered.cells[coord]!.overlay = .obstacle
        }
        for a in open.cells.keys {
            for b in open.cells.keys {
                XCTAssertEqual(LineOfSight.hasLOS(from: a, to: b, board: open),
                               LineOfSight.hasLOS(from: a, to: b, board: cluttered),
                               "\(a)->\(b)")
            }
        }
    }

    func testLOS_withRange() {
        let board = makeBoard(cols: 12, rows: 12)
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(2, 4), to: HexCoord(5, 4), range: 3, board: board))
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(2, 4), to: HexCoord(6, 4), range: 3, board: board))
    }

    func testBlocksLineOfSight() {
        let board = makeBoard(cols: 4, rows: 4)
        placeObstacle(board, HexCoord(1, 1))
        placeWall(board, HexCoord(2, 2))
        XCTAssertFalse(LineOfSight.blocksLineOfSight(HexCoord(0, 0), board: board))
        XCTAssertFalse(LineOfSight.blocksLineOfSight(HexCoord(1, 1), board: board), "obstacle")
        XCTAssertTrue(LineOfSight.blocksLineOfSight(HexCoord(2, 2), board: board), "wall overlay")
        XCTAssertTrue(LineOfSight.blocksLineOfSight(HexCoord(9, 9), board: board), "off the map")
    }
}
