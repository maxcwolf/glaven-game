import XCTest
@testable import GlavenGameLib

/// Walls (GH p.19 and the FAQ): the edge of a map tile is a wall, still there as a line where two
/// tiles' full hexes meet beside a door. The hexes either side of such a line are not adjacent —
/// two hexes apart "for all intents and purposes (including looting)" — nothing moves or is
/// pushed across it, range is counted round it and a sight line that touches a wall is blocked.
@MainActor
final class WallLineTests: XCTestCase {

    /// Black Barrow with door 1 open: the two wall lines beside the door, each as (hex in the
    /// first room, hex in the second), and the door between them.
    private func blackBarrow() throws -> (sim: ScenarioSimulator, lines: [HexEdge], door: HexCoord) {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2, autoResolvePrompts: true))
        let door = try XCTUnwrap(sim.coord.boardState.doors.first { !$0.isOpen }).coord
        sim.coord.openDoor(at: door)
        let lines = sim.coord.boardState.wallEdges.filter { $0.a.isAdjacent(to: door) && $0.b.isAdjacent(to: door) }
            .sorted { ($0.a, $0.b) < ($1.a, $1.b) }
        return (sim, lines, door)
    }

    /// Stand a character and a monster either side of the first wall line.
    private func faceOff(_ sim: ScenarioSimulator, across line: HexEdge) throws -> (me: PieceID, foe: PieceID) {
        let coord = sim.coord
        let me = PieceID.character(try XCTUnwrap(sim.gm.game.characters.first).id)
        let foe = try XCTUnwrap(coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return true }; return false }.sorted().first)
        for hex in [line.a, line.b] {
            for other in coord.boardState.pieces(at: hex) { coord.removePieceFromBoard(other) }
        }
        coord.boardState.piecePositions[me] = line.a
        coord.boardState.piecePositions[foe] = line.b
        return (me, foe)
    }

    func testTheHexesEitherSideOfADoorHaveAWallLineBetweenThem() throws {
        let (sim, lines, door) = try blackBarrow()
        let board = sim.coord.boardState
        XCTAssertEqual(lines.count, 2, "one above the door and one below")
        for line in lines {
            XCTAssertTrue(line.a.isAdjacent(to: line.b), "the two hexes touch")
            XCTAssertNotEqual(board.cells[line.a]?.tileRef, board.cells[line.b]?.tileRef, "and lie on different tiles")
            XCTAssertFalse(board.areAdjacent(line.a, line.b), "but they are not adjacent")
            XCTAssertEqual(board.range(from: line.a, to: line.b), 2, "they are two hexes apart: through the doorway")
            XCTAssertTrue(board.areAdjacent(line.a, door) && board.areAdjacent(line.b, door), "the doorway joins both")
        }
    }

    func testNoFigureWalksJumpsOrFliesAcrossAWallLine() throws {
        let (sim, lines, door) = try blackBarrow()
        let board = sim.coord.boardState
        let line = try XCTUnwrap(lines.first)
        for piece in board.pieces(at: door) + board.pieces(at: line.b) { sim.coord.removePieceFromBoard(piece) }
        for mode in MoveMode.allCases {
            let way = try XCTUnwrap(Pathfinder.findPathDetailed(board: board, from: line.a, to: line.b, mode: mode), "\(mode)")
            XCTAssertEqual(way.path, [line.a, door, line.b], "\(mode): the only way is through the doorway")
            XCTAssertEqual(way.cost, 2, "\(mode)")
            XCTAssertNil(Pathfinder.reachableHexes(board: board, from: line.a, range: 1, mode: mode)[line.b], "\(mode): not within one step")
        }
    }

    func testThereIsNoMeleeAcrossAWallLine() throws {
        let (sim, lines, _) = try blackBarrow()
        let (me, foe) = try faceOff(sim, across: try XCTUnwrap(lines.first))
        XCTAssertFalse(sim.coord.targetableEnemies(of: me, range: 1).contains(foe), "the enemy across the line is not adjacent")
        XCTAssertTrue(sim.coord.targetableEnemies(of: me, range: 2).contains(foe), "it is two hexes away, seen through the doorway")
        let board = sim.coord.boardState
        let (mine, theirs) = (try XCTUnwrap(board.piecePositions[me]), try XCTUnwrap(board.piecePositions[foe]))
        XCTAssertFalse(MonsterAI.canAttack(from: theirs, to: mine, range: 1, board: board), "nor can the monster strike back in melee")
        XCTAssertTrue(MonsterAI.canAttack(from: theirs, to: mine, range: 2, board: board))
    }

    /// A ranged attack on a figure across the line is not an attack on an adjacent figure.
    func testARangedAttackAcrossAWallLineHasNoDisadvantage() throws {
        let (sim, lines, _) = try blackBarrow()
        let line = try XCTUnwrap(lines.first)
        let board = sim.coord.boardState
        XCTAssertTrue(LineOfSight.hasLOS(from: line.a, to: line.b, board: board), "seen through the doorway")
        XCTAssertFalse(board.areAdjacent(line.a, line.b))
        XCTAssertFalse(board.neighbors(of: line.a).contains(line.b))
    }

    func testThereIsNoLootingAcrossAWallLine() throws {
        let (sim, lines, _) = try blackBarrow()
        let line = try XCTUnwrap(lines.first)
        let coord = sim.coord
        let me = PieceID.character(try XCTUnwrap(sim.gm.game.characters.first).id)
        for hex in [line.a, line.b] {
            for other in coord.boardState.pieces(at: hex) { coord.removePieceFromBoard(other) }
        }
        coord.boardState.piecePositions[me] = line.a
        coord.boardState.lootTokens = [line.b: 1]
        XCTAssertFalse(coord.collectLootInRange(pieceID: me, range: 1), "Loot 1 doesn't reach across the line")
        XCTAssertEqual(coord.boardState.lootTokens[line.b], 1)
        XCTAssertTrue(coord.collectLootInRange(pieceID: me, range: 2), "Loot 2 does: the hex is two away")
    }

    func testNothingIsPushedAcrossAWallLine() throws {
        let (sim, lines, door) = try blackBarrow()
        let line = try XCTUnwrap(lines.first)
        let coord = sim.coord
        let foe = try XCTUnwrap(coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return true }; return false }.sorted().first)
        for hex in [line.a, line.b, door] {
            for other in coord.boardState.pieces(at: hex) { coord.removePieceFromBoard(other) }
        }
        coord.boardState.piecePositions[foe] = line.a
        // Pushed from straight behind, the hex across the line is the one directly away.
        let behind = try XCTUnwrap(line.a.neighbors.first { $0.distance(to: line.b) == 2 && line.b.pushCandidates(awayFrom: $0).isEmpty == false
            && line.a.pushCandidates(awayFrom: $0).contains(line.b) && coord.boardState.cells[$0] != nil })
        XCTAssertTrue(line.a.pushCandidates(awayFrom: behind).contains(line.b), "geometry: the hex across is further from the attacker")
        let steps = coord.forcedMoveSteps(for: foe, from: line.a, attackerPos: behind, stepsLeft: 1, isPush: true)
        XCTAssertFalse(steps.contains(line.b), "but the wall line stops the push")
    }

    // MARK: - Line of sight

    /// A board of two "tiles" (columns 0–2 and 3–5) that touch all along, with wall lines between
    /// them except round the `doorway` hexes.
    private func twoTiles(doorway: Set<HexCoord> = []) -> BoardState {
        let board = makeBoard(cols: 6, rows: 5)
        for hex in board.cells.keys where !doorway.contains(hex) {
            for neighbor in hex.neighbors where board.cells[neighbor] != nil && !doorway.contains(neighbor)
                && (hex.col <= 2) != (neighbor.col <= 2) {
                board.wallEdges.insert(HexEdge(hex, neighbor))
            }
        }
        return board
    }

    func testAWallLineBlocksLineOfSightAndRange() {
        let board = twoTiles()
        for (from, to) in [(HexCoord(2, 2), HexCoord(3, 2)), (HexCoord(1, 2), HexCoord(4, 2)), (HexCoord(0, 0), HexCoord(5, 4)), (HexCoord(2, 1), HexCoord(3, 1))] {
            XCTAssertFalse(LineOfSight.hasLOS(from: from, to: to, board: board), "\(from) can't see \(to) through the wall")
            XCTAssertFalse(LineOfSight.hasLOS(from: to, to: from, board: board), "nor \(to) see \(from)")
            XCTAssertNil(board.range(from: from, to: to), "and no range reaches it")
        }
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(0, 0), to: HexCoord(2, 4), board: board), "within a tile nothing is in the way")
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(2, 1), to: HexCoord(2, 3), board: board), "also along the wall")
    }

    func testFiguresSeeThroughADoorwayInAWallLine() {
        let doorway = HexCoord(3, 2)
        let board = twoTiles(doorway: [doorway])
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(0, 2), to: HexCoord(5, 2), board: board), "straight through the doorway")
        XCTAssertEqual(board.range(from: HexCoord(0, 2), to: HexCoord(5, 2)), 5)
        // The hexes either side of the wall beside the doorway see each other but are two apart.
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(2, 1), to: HexCoord(3, 1), board: board))
        XCTAssertEqual(board.range(from: HexCoord(2, 1), to: HexCoord(3, 1)), 2)
        // Far from the doorway the wall still blocks.
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(2, 4), to: HexCoord(3, 4), board: board))
        XCTAssertEqual(board.range(from: HexCoord(2, 4), to: HexCoord(3, 4)), 4, "round by the doorway")
    }

    /// FAQ: "Walls and closed doors are the only things that block line of sight."
    func testAClosedDoorBlocksLineOfSight() {
        let board = BoardState()
        for col in 0..<5 { board.cells[HexCoord(col, 0)] = HexCell(coord: HexCoord(col, 0), tileRef: "test", passable: true) }
        let door = HexCoord(2, 0)
        board.cells[door]?.overlay = .door
        board.doors = [DoorInfo(coord: door, childTileRef: "test", subType: "stone", refPoint: HexCoord(0, 0), origin: HexCoord(0, 0))]
        XCTAssertFalse(LineOfSight.hasLOS(from: HexCoord(0, 0), to: HexCoord(4, 0), board: board), "the shut door is a wall")
        XCTAssertNil(board.range(from: HexCoord(0, 0), to: HexCoord(4, 0)), "and range isn't counted through it")
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(1, 0), to: door, board: board), "the door itself is seen")
        board.doors[0].isOpen = true
        XCTAssertTrue(LineOfSight.hasLOS(from: HexCoord(0, 0), to: HexCoord(4, 0), board: board), "open, it is a doorway")
        XCTAssertEqual(board.range(from: HexCoord(0, 0), to: HexCoord(4, 0)), 4)
    }

    // MARK: - Range

    /// Range is counted hex by hex round a wall, never through it.
    func testRangeIsCountedRoundAWall() {
        let board = makeBoard(cols: 5, rows: 3)
        board.cells[HexCoord(2, 0)] = nil
        board.cells[HexCoord(2, 1)] = nil
        XCTAssertEqual(HexCoord(1, 0).distance(to: HexCoord(3, 0)), 2, "two hexes as the crow flies")
        XCTAssertEqual(board.range(from: HexCoord(1, 0), to: HexCoord(3, 0)), 5, "five round the end of the wall")
        XCTAssertFalse(board.isWithin(4, from: HexCoord(1, 0), to: HexCoord(3, 0)))
        XCTAssertTrue(board.isWithin(5, from: HexCoord(1, 0), to: HexCoord(3, 0)))
        XCTAssertEqual(board.range(from: HexCoord(0, 0), to: HexCoord(1, 2)), HexCoord(0, 0).distance(to: HexCoord(1, 2)),
                       "with nothing in the way range is the plain count")
    }

    /// Obstacles and figures don't change range: only walls do.
    func testRangeIsCountedThroughObstaclesAndFigures() {
        let board = makeBoard(cols: 5, rows: 1)
        board.placeObstacle(at: HexCoord(1, 0))
        board.piecePositions[.monster(name: "bandit-guard", standee: 1)] = HexCoord(2, 0)
        XCTAssertEqual(board.range(from: HexCoord(0, 0), to: HexCoord(4, 0)), 4)
    }
}
