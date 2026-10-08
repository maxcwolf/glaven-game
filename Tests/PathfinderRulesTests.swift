import XCTest
@testable import GlavenGameLib

/// Gloomhaven movement-rule tests for Pathfinder (rulebook p.17-18 and the monster
/// movement rules on negative hexes).
///
/// Many tests use a single-row "corridor" board (`makeBoard(cols: n, rows: 1)`): in row 0
/// only the east/west neighbours exist, so every route runs along (0,0) … (n-1,0).
final class PathfinderRulesTests: XCTestCase {

    private func h(_ col: Int, _ row: Int) -> HexCoord { HexCoord(col, row) }

    private func corridor(_ length: Int) -> BoardState { makeBoard(cols: length, rows: 1) }

    private func line(_ cols: ClosedRange<Int>) -> [HexCoord] { cols.map { HexCoord($0, 0) } }

    // MARK: - Jump

    func testJump_passesOverObstacle() {
        let board = corridor(6)
        board.placeObstacle(at: h(2, 0))

        XCTAssertNil(Pathfinder.findPath(board: board, from: h(0, 0), to: h(4, 0)),
                     "a normal move can't cross an obstacle")

        let path = Pathfinder.findPath(board: board, from: h(0, 0), to: h(4, 0), mode: .jump)
        XCTAssertEqual(path, line(0...4), "jump passes over the obstacle")
        XCTAssertEqual(Pathfinder.findPath(board: board, from: h(0, 0), to: h(4, 0), jumping: true), path,
                       "legacy jumping: flag behaves like mode: .jump")
        XCTAssertEqual(Pathfinder.movementCost(of: path!, board: board, mode: .jump), 4)

        let reach = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 3, mode: .jump)
        XCTAssertEqual(reach[h(1, 0)], 1)
        XCTAssertNil(reach[h(2, 0)], "a jump can't END on an obstacle")
        XCTAssertEqual(reach[h(3, 0)], 3, "jumping over the obstacle costs 1 for it")
    }

    func testJump_passesOverEnemyAndAlly() {
        let board = corridor(6)
        let enemy: Set<HexCoord> = [h(2, 0)]
        let ally: Set<HexCoord> = [h(3, 0)]

        XCTAssertNil(Pathfinder.findPath(board: board, from: h(0, 0), to: h(5, 0),
                                         occupiedByEnemy: enemy, occupiedByAlly: ally),
                     "a normal move can't pass through an enemy")
        let path = Pathfinder.findPath(board: board, from: h(0, 0), to: h(5, 0), mode: .jump,
                                       occupiedByEnemy: enemy, occupiedByAlly: ally)
        XCTAssertEqual(path, line(0...5), "jump passes over enemies and allies")

        let reach = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 5, mode: .jump,
                                              occupiedByEnemy: enemy, occupiedByAlly: ally)
        XCTAssertNil(reach[h(2, 0)], "can't land on the enemy")
        XCTAssertNil(reach[h(3, 0)], "can't land on the ally")
        XCTAssertEqual(reach[h(4, 0)], 4)
    }

    func testJump_intermediateDifficultTerrainCostsOne() {
        let board = corridor(6)
        board.cells[h(1, 0)]!.overlay = .difficultTerrain
        board.cells[h(2, 0)]!.overlay = .difficultTerrain

        let normal = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 3)
        XCTAssertEqual(normal[h(1, 0)], 2)
        XCTAssertNil(normal[h(2, 0)], "normal move: 2 + 2 > 3")
        XCTAssertNil(normal[h(3, 0)])

        let jump = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 3, mode: .jump)
        XCTAssertEqual(jump[h(1, 0)], 2, "landing on difficult terrain costs 2")
        XCTAssertEqual(jump[h(2, 0)], 3, "1 (jumped over) + 2 (difficult landing)")
        XCTAssertEqual(jump[h(3, 0)], 3, "difficult terrain jumped over costs 1 each")
    }

    func testJump_landingOnDifficultTerrainCostsTwo() {
        let board = corridor(4)
        board.cells[h(1, 0)]!.overlay = .difficultTerrain

        XCTAssertNil(Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 1, mode: .jump)[h(1, 0)],
                     "jump 1 can't land on difficult terrain")
        XCTAssertEqual(Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 2, mode: .jump)[h(1, 0)], 2)
        XCTAssertEqual(Pathfinder.findPathDetailed(board: board, from: h(0, 0), to: h(1, 0), mode: .jump)?.cost, 2)
        XCTAssertNil(Pathfinder.findPath(board: board, from: h(0, 0), to: h(1, 0), mode: .jump, maxCost: 1))
    }

    func testJump_trapJumpedOverDoesNotCount_trapLandedOnDoes() {
        let board = corridor(4)
        board.placeTrap(at: h(1, 0), damage: 3)

        let over = Pathfinder.findPathDetailed(board: board, from: h(0, 0), to: h(2, 0), mode: .jump)
        XCTAssertEqual(over?.negativeHexes, 0, "a trap jumped over doesn't trigger")
        XCTAssertEqual(over?.cost, 2)

        let onto = Pathfinder.findPathDetailed(board: board, from: h(0, 0), to: h(1, 0), mode: .jump)
        XCTAssertEqual(onto?.negativeHexes, 1, "a trap on the landing hex triggers")

        let avoiding = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 2,
                                                 mode: .jump, avoidTraps: true)
        XCTAssertEqual(avoiding[h(2, 0)], 2)
        XCTAssertNil(avoiding[h(1, 0)])
    }

    func testJumpAndFly_cannotCrossVoidOrWall() {
        let gap = corridor(5)
        gap.cells.removeValue(forKey: h(2, 0))
        XCTAssertNil(Pathfinder.findPath(board: gap, from: h(0, 0), to: h(4, 0), mode: .jump),
                     "jump can't cross a hex that doesn't exist")
        XCTAssertNil(Pathfinder.findPath(board: gap, from: h(0, 0), to: h(4, 0), mode: .fly),
                     "flying can't cross a hex that doesn't exist")

        let wall = corridor(5)
        wall.cells[h(2, 0)]!.overlay = .wall
        wall.cells[h(2, 0)]!.passable = false
        XCTAssertNil(Pathfinder.findPath(board: wall, from: h(0, 0), to: h(4, 0), mode: .jump),
                     "jump can't cross a wall")
        XCTAssertNil(Pathfinder.findPath(board: wall, from: h(0, 0), to: h(4, 0), mode: .fly),
                     "flying can't cross a wall")
        XCTAssertNil(Pathfinder.reachableHexes(board: wall, from: h(0, 0), range: 4, mode: .fly)[h(3, 0)])
    }

    // MARK: - Fly

    func testFly_passesOverEnemyButCannotEndOnIt() {
        let board = corridor(5)
        let enemy: Set<HexCoord> = [h(2, 0)]

        let path = Pathfinder.findPathDetailed(board: board, from: h(0, 0), to: h(4, 0), mode: .fly,
                                               occupiedByEnemy: enemy)
        XCTAssertEqual(path?.path, line(0...4))
        XCTAssertEqual(path?.cost, 4)
        XCTAssertNil(Pathfinder.findPath(board: board, from: h(0, 0), to: h(2, 0), mode: .fly,
                                         occupiedByEnemy: enemy),
                     "flying must still end in an unoccupied hex")

        let reach = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 4, flying: true,
                                              occupiedByEnemy: enemy, occupiedByAlly: [h(3, 0)])
        XCTAssertNil(reach[h(2, 0)], "can't end on an enemy")
        XCTAssertNil(reach[h(3, 0)], "can't end on an ally")
        XCTAssertEqual(reach[h(4, 0)], 4)
    }

    func testFly_ignoresTrapsHazardsAndDifficultTerrain() {
        let board = corridor(5)
        board.placeTrap(at: h(1, 0), damage: 3)
        board.placeHazard(at: h(2, 0))
        board.cells[h(3, 0)]!.overlay = .difficultTerrain

        let result = Pathfinder.findPathDetailed(board: board, from: h(0, 0), to: h(4, 0), mode: .fly)
        XCTAssertEqual(result?.cost, 4)
        XCTAssertEqual(result?.negativeHexes, 0)
        XCTAssertEqual(Pathfinder.negativeHexesEntered(along: line(0...4), board: board, mode: .fly), [])
        let reach = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 3, mode: .fly, avoidTraps: true)
        XCTAssertEqual(reach[h(3, 0)], 3, "negative hexes never matter when flying")
    }

    // MARK: - Occupancy

    func testNormalMove_cannotPassEnemy() {
        let board = corridor(5)
        let reach = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 4,
                                              occupiedByEnemy: [h(2, 0)])
        XCTAssertEqual(Set(reach.keys), [h(0, 0), h(1, 0)])
    }

    func testNormalMove_passesAllyButCannotEndOnIt() {
        let board = corridor(5)
        let reach = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 4,
                                              occupiedByAlly: [h(2, 0)])
        XCTAssertNil(reach[h(2, 0)])
        XCTAssertEqual(reach[h(3, 0)], 3, "allies can be moved through")
        XCTAssertNil(Pathfinder.findPath(board: board, from: h(0, 0), to: h(2, 0), occupiedByAlly: [h(2, 0)]))
    }

    func testCannotEndOnHexOccupiedByAnyFigureOnTheBoard() {
        let board = corridor(5)
        board.placePiece(.character("mover"), at: h(0, 0))
        board.placePiece(.objective(id: 1), at: h(3, 0)) // in neither occupancy set

        XCTAssertNil(Pathfinder.findPath(board: board, from: h(0, 0), to: h(3, 0)),
                     "can't end on a hex holding any figure")
        let reach = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 4)
        XCTAssertEqual(reach[h(0, 0)], 0, "the mover's own hex is not blocked")
        XCTAssertNil(reach[h(3, 0)])
        XCTAssertEqual(reach[h(4, 0)], 4,
                       "passage is only blocked by occupiedByEnemy; other figures can be passed")
    }

    // MARK: - Monster AI: negative hexes (traps + hazards)

    /// 7x3 board, bottom row blocked. Column 3 (which every route must cross) holds
    /// traps on both open hexes, and (2,1) is also trapped:
    ///   straight along row 1 → 6 movement, 2 traps
    ///   up through (3,0)     → 7 movement, 1 trap
    private func trapOnlyBoard() -> BoardState {
        let board = makeBoard(cols: 7, rows: 3)
        for col in 0..<7 { board.cells[h(col, 2)]!.passable = false }
        board.placeTrap(at: h(2, 1), damage: 2)
        board.placeTrap(at: h(3, 1), damage: 2)
        board.placeTrap(at: h(3, 0), damage: 2)
        return board
    }

    func testTrapOnlyRoute_fallsBackToPathWithFewestNegativeHexes() {
        let board = trapOnlyBoard()

        let ai = Pathfinder.findPathDetailed(board: board, from: h(0, 1), to: h(6, 1))
        XCTAssertNotNil(ai, "the only routes cross traps, so the AI must fall back to one")
        XCTAssertEqual(ai?.negativeHexes, 1, "fallback uses the fewest negative hexes possible")
        XCTAssertEqual(ai?.cost, 7)
        XCTAssertEqual(Pathfinder.negativeHexesEntered(along: ai!.path, board: board), [h(3, 0)])

        let legacy = Pathfinder.findPath(board: board, from: h(0, 1), to: h(6, 1), avoidTraps: true)
        XCTAssertEqual(legacy, ai?.path)

        let cheapest = Pathfinder.findPathDetailed(board: board, from: h(0, 1), to: h(6, 1), avoidTraps: false)
        XCTAssertEqual(cheapest?.cost, 6)
        XCTAssertEqual(cheapest?.negativeHexes, 2)

        XCTAssertEqual(Pathfinder.findPathDetailed(board: board, from: h(0, 1), to: h(6, 1), maxCost: 6)?.negativeHexes, 2,
                       "within a 6-point budget only the 2-trap path exists")
        XCTAssertEqual(Pathfinder.findPathDetailed(board: board, from: h(0, 1), to: h(6, 1), maxCost: 7)?.negativeHexes, 1)
    }

    func testCheapestTarget_fallsBackWhenOnlyRouteCrossesTrap() {
        let board = trapOnlyBoard()
        let result = Pathfinder.cheapestTarget(board: board, from: h(0, 1), targets: [h(6, 1)])
        XCTAssertNotNil(result, "focus must not be lost just because every route has a trap")
        XCTAssertEqual(result?.target, h(6, 1))
        XCTAssertEqual(result?.cost, 7)

        let detailed = Pathfinder.cheapestTargetPath(board: board, from: h(0, 1), targets: [h(6, 1)])
        XCTAssertEqual(detailed?.negativeHexes, 1)
        XCTAssertEqual(detailed?.path.first, h(0, 1))
        XCTAssertEqual(detailed?.path.last, h(6, 1))
    }

    func testCheapestTargetPath_prefersTrapFreeTargetOverCheaperTrapRoute() {
        let board = corridor(9)
        board.placeTrap(at: h(3, 0), damage: 2)
        let targets: Set<HexCoord> = [h(2, 0), h(7, 0)]

        let ai = Pathfinder.cheapestTargetPath(board: board, from: h(4, 0), targets: targets)
        XCTAssertEqual(ai?.target, h(7, 0), "a trap-free target beats a cheaper one behind a trap")
        XCTAssertEqual(ai?.cost, 3)
        XCTAssertEqual(ai?.negativeHexes, 0)

        let plain = Pathfinder.cheapestTargetPath(board: board, from: h(4, 0), targets: targets, avoidTraps: false)
        XCTAssertEqual(plain?.target, h(2, 0))
        XCTAssertEqual(plain?.negativeHexes, 1)
    }

    func testHazards_avoidedWhenAlternativeExists() {
        let board = makeBoard(cols: 10, rows: 5)
        board.placeHazard(at: h(4, 2), subType: "fire")

        let ai = Pathfinder.findPathDetailed(board: board, from: h(2, 2), to: h(6, 2))
        XCTAssertNotNil(ai)
        XCTAssertFalse(ai!.path.contains(h(4, 2)), "AI treats hazardous terrain as an obstacle")
        XCTAssertEqual(ai?.negativeHexes, 0)
        XCTAssertEqual(ai?.cost, 5)
        XCTAssertNil(Pathfinder.pathCost(board: board, from: h(2, 2), to: h(6, 2), maxCost: 3))
        XCTAssertEqual(Pathfinder.pathCost(board: board, from: h(2, 2), to: h(6, 2)), 5)

        let plain = Pathfinder.findPathDetailed(board: board, from: h(2, 2), to: h(6, 2), avoidTraps: false)
        XCTAssertEqual(plain?.cost, 4)
        XCTAssertTrue(plain!.path.contains(h(4, 2)))
    }

    func testHazardOnlyCorridor_fallsBack() {
        let board = corridor(5)
        board.placeHazard(at: h(2, 0))
        let result = Pathfinder.findPathDetailed(board: board, from: h(0, 0), to: h(4, 0))
        XCTAssertEqual(result?.path, line(0...4))
        XCTAssertEqual(result?.negativeHexes, 1)
        XCTAssertNotNil(Pathfinder.cheapestTarget(board: board, from: h(0, 0), targets: [h(4, 0)]))
    }

    func testReachable_avoidTrapsExcludesNegativeHexesAndWhatLiesBehindThem() {
        let board = corridor(5)
        board.placeHazard(at: h(2, 0))

        let ai = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 4, avoidTraps: true)
        XCTAssertEqual(Set(ai.keys), [h(0, 0), h(1, 0)])

        let character = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 4)
        XCTAssertEqual(character[h(2, 0)], 2)
        XCTAssertEqual(character[h(4, 0)], 4)
    }

    // MARK: - Characters

    func testCharacterCanReachTrapHex() {
        let board = makeBoard(cols: 10, rows: 5)
        board.placeTrap(at: h(3, 2), damage: 3)

        let reach = Pathfinder.reachableHexes(board: board, from: h(2, 2), range: 2)
        XCTAssertEqual(reach[h(3, 2)], 1, "characters may deliberately step onto a trap")

        let result = Pathfinder.findPathDetailed(board: board, from: h(2, 2), to: h(3, 2), maxCost: 1)
        XCTAssertEqual(result?.path, [h(2, 2), h(3, 2)])
        XCTAssertEqual(result?.negativeHexes, 1)
    }

    func testCharacterCanMoveThroughTrap() {
        let board = corridor(5)
        board.placeTrap(at: h(2, 0), damage: 3)
        let reach = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 4)
        XCTAssertEqual(reach[h(4, 0)], 4)
        let path = Pathfinder.findPath(board: board, from: h(0, 0), to: h(4, 0), maxCost: 4)
        XCTAssertEqual(path, line(0...4))
        XCTAssertEqual(Pathfinder.negativeHexesEntered(along: path!, board: board), [h(2, 0)])
    }

    func testCharacterPrefersTrapFreePathWithinBudget() {
        let board = makeBoard(cols: 10, rows: 5)
        board.placeTrap(at: h(4, 2), damage: 3)

        let tight = Pathfinder.findPathDetailed(board: board, from: h(2, 2), to: h(6, 2), maxCost: 4)
        XCTAssertEqual(tight?.cost, 4, "with exactly 4 movement the trap must be crossed")
        XCTAssertEqual(tight?.negativeHexes, 1)

        let roomy = Pathfinder.findPathDetailed(board: board, from: h(2, 2), to: h(6, 2), maxCost: 5)
        XCTAssertEqual(roomy?.cost, 5, "with a spare point the trap-free detour is preferred")
        XCTAssertEqual(roomy?.negativeHexes, 0)
        XCTAssertFalse(roomy!.path.contains(h(4, 2)))

        XCTAssertNil(Pathfinder.findPath(board: board, from: h(2, 2), to: h(6, 2), maxCost: 3))
    }

    func testEqualCostPaths_preferTheOneAvoidingTrap() {
        // (2,2) → (3,1) has two shortest paths: via (2,1) or via (3,2).
        for (trap, expectedVia) in [(h(2, 1), h(3, 2)), (h(3, 2), h(2, 1))] {
            let board = makeBoard(cols: 10, rows: 5)
            board.placeTrap(at: trap, damage: 3)
            let path = Pathfinder.findPath(board: board, from: h(2, 2), to: h(3, 1), avoidTraps: false)
            XCTAssertEqual(path, [h(2, 2), expectedVia, h(3, 1)],
                           "among equal-cost paths the trap-free one is chosen (trap at \(trap))")
        }
    }

    // MARK: - Doors

    private func doorCorridor() -> BoardState {
        let board = corridor(7)
        board.doors.append(DoorInfo(coord: h(3, 0), childTileRef: "x", subType: "stone",
                                    refPoint: h(3, 0), origin: h(0, 0)))
        board.cells[h(3, 0)]!.overlay = .door
        return board
    }

    func testClosedDoor_blocksMonstersButNotCharacters() {
        let board = doorCorridor()
        XCTAssertTrue(board.isClosedDoor(h(3, 0)))
        XCTAssertFalse(board.isClosedDoor(h(2, 0)))

        XCTAssertNil(Pathfinder.findPath(board: board, from: h(0, 0), to: h(5, 0), canOpenDoors: false),
                     "monsters treat a closed door as a wall")
        XCTAssertNil(Pathfinder.findPath(board: board, from: h(0, 0), to: h(3, 0), canOpenDoors: false),
                     "monsters can't stand on a closed door")
        XCTAssertNil(Pathfinder.findPath(board: board, from: h(0, 0), to: h(5, 0), mode: .jump, canOpenDoors: false))
        XCTAssertNil(Pathfinder.findPath(board: board, from: h(0, 0), to: h(5, 0), mode: .fly, canOpenDoors: false))
        XCTAssertNil(Pathfinder.cheapestTarget(board: board, from: h(0, 0), targets: [h(5, 0)], canOpenDoors: false))

        XCTAssertEqual(Pathfinder.findPath(board: board, from: h(0, 0), to: h(3, 0)), line(0...3),
                       "characters may enter a closed door hex (opening it)")

        let monster = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 6, canOpenDoors: false)
        XCTAssertEqual(Set(monster.keys), [h(0, 0), h(1, 0), h(2, 0)])
        let character = Pathfinder.reachableHexes(board: board, from: h(0, 0), range: 6)
        XCTAssertEqual(character[h(3, 0)], 3)
        XCTAssertEqual(character[h(5, 0)], 5)
    }

    func testOpenDoor_doesNotBlockMonsters() {
        let board = doorCorridor()
        board.doors[0].isOpen = true
        XCTAssertFalse(board.isClosedDoor(h(3, 0)))
        XCTAssertEqual(Pathfinder.findPath(board: board, from: h(0, 0), to: h(5, 0), canOpenDoors: false),
                       line(0...5))
    }

    // MARK: - Path helpers

    func testMovementCostOfPath_respectsMode() {
        let board = corridor(5)
        board.cells[h(1, 0)]!.overlay = .difficultTerrain
        board.cells[h(3, 0)]!.overlay = .difficultTerrain

        XCTAssertEqual(Pathfinder.movementCost(of: line(0...4), board: board), 6)
        XCTAssertEqual(Pathfinder.movementCost(of: line(0...4), board: board, mode: .jump), 4)
        XCTAssertEqual(Pathfinder.movementCost(of: line(0...3), board: board, mode: .jump), 4,
                       "jump: 2 hexes jumped over + difficult landing (2)")
        XCTAssertEqual(Pathfinder.movementCost(of: line(0...4), board: board, mode: .fly), 4)
        XCTAssertEqual(Pathfinder.movementCost(of: [h(0, 0)], board: board), 0)
    }

    func testTruncatePath_respectsBudgetModeAndOccupancy() {
        let board = corridor(6)
        board.cells[h(2, 0)]!.overlay = .difficultTerrain
        let path = line(0...5)

        XCTAssertEqual(Pathfinder.truncatePath(path, budget: 2, board: board), line(0...1),
                       "entering the difficult hex would cost a third point")
        XCTAssertEqual(Pathfinder.truncatePath(path, budget: 3, board: board), line(0...2))
        XCTAssertEqual(Pathfinder.truncatePath(path, budget: 3, board: board, mode: .jump), line(0...3),
                       "jumping over difficult terrain costs 1")
        XCTAssertEqual(Pathfinder.truncatePath(path, budget: 3, board: board, mode: .fly), line(0...3))
        XCTAssertEqual(Pathfinder.truncatePath(path, budget: 10, board: board), path)

        // Can't stop on an occupied hex: step back.
        XCTAssertEqual(Pathfinder.truncatePath(path, budget: 3, board: board, occupied: [h(2, 0)]), line(0...1))
        board.placePiece(.character("mover"), at: h(0, 0))
        board.placePiece(.summon(id: "ally"), at: h(1, 0))
        XCTAssertEqual(Pathfinder.truncatePath(path, budget: 2, board: board), [h(0, 0)])
    }

    func testTruncatePath_jumpCannotLandOnObstacle() {
        let board = corridor(6)
        board.placeObstacle(at: h(2, 0))
        let path = line(0...4)
        XCTAssertEqual(Pathfinder.truncatePath(path, budget: 2, board: board, mode: .jump), line(0...1))
        XCTAssertEqual(Pathfinder.truncatePath(path, budget: 3, board: board, mode: .jump), line(0...3))
    }

    func testNegativeHexesEntered_isModeAware() {
        let board = corridor(5)
        board.placeTrap(at: h(1, 0), damage: 2)
        board.placeHazard(at: h(3, 0))

        XCTAssertEqual(Pathfinder.negativeHexesEntered(along: line(0...4), board: board), [h(1, 0), h(3, 0)])
        XCTAssertEqual(Pathfinder.negativeHexesEntered(along: line(0...3), board: board, mode: .jump), [h(3, 0)])
        XCTAssertEqual(Pathfinder.negativeHexesEntered(along: line(0...4), board: board, mode: .jump), [])
        XCTAssertEqual(Pathfinder.negativeHexesEntered(along: line(0...4), board: board, mode: .fly), [])
        XCTAssertEqual(Pathfinder.negativeHexesEntered(along: line(1...2), board: board), [],
                       "the start hex isn't entered by the move")
        XCTAssertTrue(board.isNegativeHex(h(1, 0)))
        XCTAssertTrue(board.isNegativeHex(h(3, 0)))
        XCTAssertFalse(board.isNegativeHex(h(2, 0)))
    }

    // MARK: - Legacy flags

    func testLegacyFlags_matchMoveMode() {
        let board = makeBoard(cols: 8, rows: 6)
        board.placeObstacle(at: h(3, 2))
        board.placeTrap(at: h(4, 3), damage: 2)
        board.cells[h(2, 3)]!.overlay = .difficultTerrain
        let enemies: Set<HexCoord> = [h(3, 3)]

        for (flying, jumping, mode) in [(true, false, MoveMode.fly), (false, true, .jump), (false, false, .normal)] {
            XCTAssertEqual(MoveMode(flying: flying, jumping: jumping), mode)
            let legacy = Pathfinder.reachableHexes(board: board, from: h(2, 2), range: 4, flying: flying,
                                                   jumping: jumping, occupiedByEnemy: enemies)
            let modern = Pathfinder.reachableHexes(board: board, from: h(2, 2), range: 4, mode: mode,
                                                   occupiedByEnemy: enemies)
            XCTAssertEqual(legacy, modern, "\(mode)")
        }
    }

    // MARK: - MonsterAI integration (through the default AI pathfinding calls)

    private func moveAttackAbility(move: Int) -> AbilityModel {
        AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(move)),
            ActionModel(type: .attack, value: .int(2))
        ])
    }

    func testMonsterAI_trapOnlyCorridor_stillFocusesAndMoves() {
        let t = TestGame()
        for c in 0..<12 {
            for r in 0..<12 where r != 3 { t.board.cells[h(c, r)]!.passable = false }
        }
        t.board.placeTrap(at: h(3, 3), damage: 2)
        t.addCharacter(pos: h(6, 3))
        let monster = t.addSimpleMonster(positions: [(1, h(1, 3), 5)])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0], ability: moveAttackAbility(move: 5),
            board: t.board, gameState: t.game)

        XCTAssertNotNil(result.focusTarget, "a trap on the only route must not cancel the focus")
        XCTAssertEqual(result.movementPath.last, h(5, 3), "moves through the trap to the attack hex")
    }

    func testMonsterAI_avoidsHazardWhenDetourExists() {
        let t = TestGame()
        t.board.placeHazard(at: h(4, 3))
        t.addCharacter(pos: h(7, 3))
        let monster = t.addSimpleMonster(positions: [(1, h(2, 3), 5)])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0], ability: moveAttackAbility(move: 5),
            board: t.board, gameState: t.game)

        XCTAssertFalse(result.movementPath.contains(h(4, 3)), "hazardous terrain is avoided like a trap")
        XCTAssertEqual(result.movementPath.last.map { $0.distance(to: h(7, 3)) }, 1,
                       "the detour still reaches a melee attack hex")
    }
}
