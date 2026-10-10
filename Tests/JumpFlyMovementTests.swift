import XCTest
@testable import GlavenGameLib

/// Jump and Fly (rulebook p.19; gh-rules.md MOV-2, MOV-3, MOV-4): what each passes over, and
/// where each may end — in the pathfinder, and in the hexes the board offers a character.
/// (A jump springing the trap it lands on, through a real card: MovementRuleTests.)
@MainActor
final class JumpFlyMovementTests: XCTestCase {

    /// A corridor one hex wide along row 2, so there is no way round anything in it.
    private func corridor() -> BoardState {
        let board = makeBoard(cols: 10, rows: 5)
        for hex in Array(board.cells.keys) where hex.row != 2 { board.cells[hex] = nil }
        return board
    }

    private let start = HexCoord(2, 2), next = HexCoord(3, 2), beyond = HexCoord(4, 2), further = HexCoord(5, 2)

    // MARK: - Jump

    /// MOV-3: a jump passes over a trap without springing it, so a jumper keeping clear of traps
    /// (as a monster does) gets past one a walker can't; the trap's own hex is where it would
    /// land, and that is no way of keeping clear.
    func testJump_ignoresTrapsOnIntermediateHexes() {
        let board = corridor()
        board.cells[next] = HexCell(coord: next, tileRef: "t", passable: true, overlay: .trap, trapDamage: 5)

        let walking = Pathfinder.reachableHexes(board: board, from: start, range: 3,
                                                avoidTraps: true, occupiedByEnemy: [], occupiedByAlly: [])
        let jumping = Pathfinder.reachableHexes(board: board, from: start, range: 3, jumping: true,
                                                avoidTraps: true, occupiedByEnemy: [], occupiedByAlly: [])
        XCTAssertNil(walking[next], "a walker avoiding traps doesn't step on it")
        XCTAssertNil(walking[beyond], "and so can't get past it")
        XCTAssertEqual(jumping[beyond], 2, "p.19: a jump goes over the trap")
        XCTAssertEqual(jumping[further], 3)
        XCTAssertNil(jumping[next], "landing on the trap would spring it: not for one avoiding traps")

        let careless = Pathfinder.reachableHexes(board: board, from: start, range: 3, jumping: true,
                                                 avoidTraps: false, occupiedByEnemy: [], occupiedByAlly: [])
        XCTAssertEqual(careless[next], 1, "a character may choose to land there")
    }

    /// MOV-2, MOV-3: difficult terrain costs a walker 2 to enter; a jump passes over it for 1,
    /// and pays the 2 only if it lands there (FAQ: the last hex is a normal move).
    func testJump_ignoresDifficultTerrainExceptWhereItLands() {
        let board = corridor()
        board.cells[next] = HexCell(coord: next, tileRef: "t", passable: true, overlay: .difficultTerrain)

        let walking = Pathfinder.reachableHexes(board: board, from: start, range: 2, occupiedByEnemy: [], occupiedByAlly: [])
        let jumping = Pathfinder.reachableHexes(board: board, from: start, range: 2, jumping: true,
                                                occupiedByEnemy: [], occupiedByAlly: [])
        XCTAssertEqual(walking[next], 2)
        XCTAssertNil(walking[beyond], "Move 2 is spent entering the difficult terrain")
        XCTAssertEqual(jumping[beyond], 2, "p.19: a jump crosses it at one movement point")
        XCTAssertEqual(jumping[next], 2, "FAQ: ending the jump in difficult terrain costs the 2")
        let short = Pathfinder.reachableHexes(board: board, from: start, range: 1, jumping: true,
                                              occupiedByEnemy: [], occupiedByAlly: [])
        XCTAssertNil(short[next], "so Move 1 with Jump can't end there")
    }

    // MARK: - Fly

    func testFly_allTerrainCostsOne() {
        let board = corridor()
        board.cells[next] = HexCell(coord: next, tileRef: "t", passable: true, overlay: .difficultTerrain)

        let flyReach = Pathfinder.reachableHexes(
            board: board, from: start, range: 2,
            flying: true, occupiedByEnemy: [], occupiedByAlly: []
        )

        XCTAssertEqual(flyReach[next], 1, "p.19: Flying ignores difficult terrain cost (costs 1 not 2)")
        XCTAssertEqual(flyReach[beyond], 2)
    }

    func testFly_canTraverseObstacles() {
        let board = corridor()
        board.cells[next]!.passable = false // obstacle

        let normalReach = Pathfinder.reachableHexes(
            board: board, from: start, range: 3,
            occupiedByEnemy: [], occupiedByAlly: []
        )

        let flyReach = Pathfinder.reachableHexes(
            board: board, from: start, range: 3,
            flying: true, occupiedByEnemy: [], occupiedByAlly: []
        )

        XCTAssertNil(normalReach[next], "Normal move can't enter obstacle")
        XCTAssertNil(normalReach[beyond], "nor pass it")
        XCTAssertEqual(flyReach[next], 1, "p.19: Flying can enter obstacle hex")
        XCTAssertEqual(flyReach[beyond], 2, "and fly on over it")
    }

    // MARK: - What the board offers

    /// The hexes offered for a character's move in a corridor with an obstacle and then an enemy
    /// in it: a walk stops before the obstacle; a jump clears the obstacle and the enemy but
    /// lands on neither; flying may end on the obstacle (MOV-4) but never on a figure.
    func testTheHexesOfferedForAWalkAJumpAndAFlight() throws {
        let board = try RuleBoard()
        let coord = board.coord
        coord.boardState = corridor()
        let brute = board.character(at: start)
        let piece = PieceID.character(brute.id)
        coord.boardState.placeObstacle(at: next)
        let enemy = try board.monster(at: beyond)
        XCTAssertEqual(board.hex(enemy.piece), beyond)

        func offered(_ begin: () -> Void) -> Set<HexCoord> {
            coord.interactionMode = .idle
            begin()
            guard case .selectingMove(_, _, let hexes, _, _) = coord.interactionMode else { return [] }
            return hexes.filter { $0.col > start.col }
        }
        XCTAssertEqual(offered { coord.beginMoveAction(pieceID: piece, moveRange: 4) }, [], "a walk: the obstacle is in the way")
        XCTAssertEqual(offered { coord.beginJumpMoveAction(pieceID: piece, moveRange: 4) }, [further, HexCoord(6, 2)],
                       "a jump: over the obstacle and the enemy, onto the free hexes behind")
        XCTAssertEqual(offered { coord.beginFlyMoveAction(pieceID: piece, moveRange: 4) }, [next, further, HexCoord(6, 2)],
                       "flying: the obstacle too, but not the enemy's hex")
    }
}
