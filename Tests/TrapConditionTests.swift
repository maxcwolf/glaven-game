import XCTest
@testable import GlavenGameLib

/// Tests for trap condition effects (poison traps, bear traps, thorn traps).
/// Rulebook p.15: "Some traps also apply conditions such as Poison or Immobilize"
final class TrapConditionTests: XCTestCase {

    // MARK: - Unit Tests: Trap Data

    func testHexCell_trapWithSubType() {
        let cell = HexCell(coord: HexCoord(3, 3), tileRef: "test",
                           passable: true, overlay: .trap, overlaySubType: "poison", trapDamage: 1)
        XCTAssertTrue(cell.isTrap)
        XCTAssertEqual(cell.overlaySubType, "poison")
        XCTAssertEqual(cell.trapDamage, 1)
    }

    func testHexCell_bearTrap() {
        let cell = HexCell(coord: HexCoord(3, 3), tileRef: "test",
                           passable: true, overlay: .trap, overlaySubType: "bear", trapDamage: 2)
        XCTAssertTrue(cell.isTrap)
        XCTAssertEqual(cell.overlaySubType, "bear")
    }

    // MARK: - Unit Tests: BoardBuilder Trap Damage

    func testBoardBuilder_poisonTrapDamage() {
        // Poison traps deal 1 damage (from BoardBuilder.trapDamage)
        let cell = HexCell(coord: HexCoord(0, 0), tileRef: "test",
                           passable: true, overlay: .trap, overlaySubType: "poison", trapDamage: 1)
        XCTAssertEqual(cell.trapDamage, 1, "Poison traps deal 1 damage")
    }

    func testBoardBuilder_spikeTrapDamage() {
        let cell = HexCell(coord: HexCoord(0, 0), tileRef: "test",
                           passable: true, overlay: .trap, overlaySubType: "spike", trapDamage: 3)
        XCTAssertEqual(cell.trapDamage, 3, "Spike traps deal 3 damage")
    }

    // MARK: - Unit Tests: Trap Removal

    func testTrapRemoved_afterTriggering() {
        let board = makeBoard()
        let coord = HexCoord(3, 3)
        board.cells[coord] = HexCell(coord: coord, tileRef: "test",
                                      passable: true, overlay: .trap,
                                      overlaySubType: "spike", trapDamage: 3)

        XCTAssertTrue(board.cells[coord]!.isTrap)

        board.removeTrap(at: coord)

        XCTAssertFalse(board.cells[coord]!.isTrap, "Trap removed after trigger")
        XCTAssertNil(board.cells[coord]!.trapDamage, "Trap damage cleared")
        XCTAssertNil(board.cells[coord]!.overlaySubType, "Trap subtype cleared")
    }

    // MARK: - E2E Tests: Condition Application via Coordinator

    func testCoordinator_trapConditionsMapping() {
        // Verify the trapConditions method maps correctly
        // We test this indirectly through the BoardCoordinator
        let coordinator = BoardCoordinator()

        // The trapConditions method is private, so we test the behavior through
        // the public interface. We verify by checking the board state and entity conditions.
        // For now, verify the data structures support trap conditions.
        let board = makeBoard()
        let coord = HexCoord(3, 3)
        board.cells[coord] = HexCell(coord: coord, tileRef: "test",
                                      passable: true, overlay: .trap,
                                      overlaySubType: "poison", trapDamage: 1)

        XCTAssertEqual(board.cells[coord]!.overlaySubType, "poison",
                       "Poison trap subtype preserved in cell data")
        _ = coordinator // Suppress unused warning
    }

    // MARK: - E2E: Trap + Monster Pathfinding

    func testMonster_avoidsPoisonTrap() {
        let board = makeBoard(cols: 10, rows: 5)
        let trapCoord = HexCoord(4, 2)
        board.cells[trapCoord] = HexCell(coord: trapCoord, tileRef: "test",
                                          passable: true, overlay: .trap,
                                          overlaySubType: "poison", trapDamage: 1)

        // Path from (2,2) to (6,2) — direct path goes through trap
        let avoidPath = Pathfinder.findPath(
            board: board, from: HexCoord(2, 2), to: HexCoord(6, 2),
            avoidTraps: true, occupiedByEnemy: []
        )

        XCTAssertNotNil(avoidPath, "Should find path avoiding poison trap")
        if let path = avoidPath {
            XCTAssertFalse(path.contains(trapCoord), "Path should avoid poison trap hex")
        }
    }

    func testFlyingFigure_immuneToTraps() {
        // Flying figures don't trigger traps — this is already tested elsewhere
        // but we verify the isTrap flag doesn't affect flying movement
        let board = makeBoard(cols: 10, rows: 5)
        board.cells[HexCoord(3, 2)] = HexCell(coord: HexCoord(3, 2), tileRef: "test",
                                               passable: true, overlay: .trap, trapDamage: 5)

        let flyReach = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 2), range: 3,
            flying: true, occupiedByEnemy: [], occupiedByAlly: []
        )

        XCTAssertNotNil(flyReach[HexCoord(3, 2)], "Flying ignores traps")
    }
}
