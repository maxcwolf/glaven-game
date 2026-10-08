import XCTest
@testable import GlavenGameLib

/// AoE pattern geometry and targeting, using the real GHS patterns from
/// `Resources/EditionData/gh/monster/deck/*.json`. Pattern hex coordinates are odd-row offset
/// (the board's own pointy-top convention).
final class AoEPatternResolverTests: XCTestCase {

    // MARK: - Real GH patterns

    /// Deep Terror 733/734: grey hex + 5 red hexes in a straight line.
    let deepTerrorLine = "(0,5,active)|(1,3,target)|(1,4,target)|(2,1,target)|(2,2,target)|(3,0,target)"
    /// Spitting Drake 563 / Flame Demon 630 / Ancient Artillery 704: ranged 7-hex flower.
    let flower = "(0,1,target)|(1,0,target)|(1,1,target)|(1,2,target)|(2,0,target)|(2,1,target)|(2,2,target)"
    /// Cultist 604/605 (on death): grey center + all 6 surrounding red hexes.
    let meleeRing = "(0,1,target)|(1,0,target)|(1,1,active)|(1,2,target)|(2,0,target)|(2,1,target)|(2,2,target)"
    /// Spitting Drake 558 / Ancient Artillery 703, 707: ranged 3-hex triangle.
    let triangle = "(0,1,target)|(1,0,target)|(1,1,target)"
    /// Frost Demon 624/625: grey hex + 2 adjacent red hexes (cleave).
    let cleave = "(0,1,active)|(1,0,target)|(1,1,target)"
    /// Harrower Infester 729: grey hex + 3 red hexes in a line.
    let infesterLine = "(1,0,active)|(1,1,target)|(2,2,target)|(2,3,target)"
    /// Savvas Lavaflow 720: grey hex + 3 red hexes in a line.
    let lavaflowLine = "(0,0,active)|(0,1,target)|(1,2,target)|(1,3,target)"

    // MARK: - Helpers

    private func cube(_ h: AoEResolver.PatternHex) -> (Int, Int, Int) { (h.cubeX, h.cubeY, h.cubeZ) }

    private func cubeDistance(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
        (abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)) / 2
    }

    /// `count` hexes walking from `start` in neighbor direction `dir` (excluding `start`).
    private func ray(from start: HexCoord, dir: Int, count: Int) -> [HexCoord] {
        var result: [HexCoord] = []
        var current = start
        for _ in 0..<count {
            current = current.neighbors[dir]
            result.append(current)
        }
        return result
    }

    private func enemy(_ n: Int) -> PieceID { .character("hero-\(n)") }

    /// Place enemies at the given hexes; returns their IDs in the same order.
    @discardableResult
    private func placeEnemies(_ board: BoardState, at coords: [HexCoord]) -> [PieceID] {
        coords.enumerated().map { i, coord in
            let id = enemy(i)
            XCTAssertTrue(board.placePiece(id, at: coord))
            return id
        }
    }

    // MARK: - Parsing / geometry

    func testParse_deepTerrorLineIsStraight() {
        let hexes = AoEResolver.parsePattern(deepTerrorLine)
        XCTAssertEqual(hexes.count, 6)
        let active = hexes.first { $0.isActive }!
        XCTAssertEqual(cube(active).0, 0)
        XCTAssertEqual(cube(active).1, 0)
        XCTAssertEqual(cube(active).2, 0)

        let targets = hexes.filter { $0.isTarget }.map(cube)
        XCTAssertEqual(targets.count, 5)
        // Sorted by distance from the attacker they must be k·d for a single unit direction d.
        let sorted = targets.sorted { cubeDistance($0, (0, 0, 0)) < cubeDistance($1, (0, 0, 0)) }
        let d = sorted[0]
        XCTAssertEqual(cubeDistance(d, (0, 0, 0)), 1)
        for (k, t) in sorted.enumerated() {
            XCTAssertEqual(t.0, d.0 * (k + 1))
            XCTAssertEqual(t.1, d.1 * (k + 1))
            XCTAssertEqual(t.2, d.2 * (k + 1))
        }
    }

    func testParse_threeHexLinesAreStraight() {
        for pattern in [infesterLine, lavaflowLine] {
            let targets = AoEResolver.parsePattern(pattern).filter { $0.isTarget }.map(cube)
            let sorted = targets.sorted { cubeDistance($0, (0, 0, 0)) < cubeDistance($1, (0, 0, 0)) }
            let d = sorted[0]
            XCTAssertEqual(cubeDistance(d, (0, 0, 0)), 1, pattern)
            for (k, t) in sorted.enumerated() {
                XCTAssertTrue(t == (d.0 * (k + 1), d.1 * (k + 1), d.2 * (k + 1)), pattern)
            }
        }
    }

    func testParse_flowerIsCenterPlusSixNeighbors() {
        let targets = AoEResolver.parsePattern(flower).filter { $0.isTarget }.map(cube)
        XCTAssertEqual(targets.count, 7)
        // Exactly one hex is adjacent to all six others.
        let centers = targets.filter { c in
            targets.filter { cubeDistance($0, c) == 1 }.count == 6
        }
        XCTAssertEqual(centers.count, 1, "flower must have a center hex touching all 6 petals")
    }

    func testParse_meleeRingSurroundsAttacker() {
        let hexes = AoEResolver.parsePattern(meleeRing)
        let targets = hexes.filter { $0.isTarget }.map(cube)
        XCTAssertEqual(targets.count, 6)
        for t in targets {
            XCTAssertEqual(cubeDistance(t, (0, 0, 0)), 1)
        }
        XCTAssertEqual(Set(targets.map { "\($0)" }).count, 6)
    }

    func testParse_triangleIsMutuallyAdjacent() {
        let targets = AoEResolver.parsePattern(triangle).filter { $0.isTarget }.map(cube)
        XCTAssertEqual(targets.count, 3)
        XCTAssertEqual(cubeDistance(targets[0], targets[1]), 1)
        XCTAssertEqual(cubeDistance(targets[1], targets[2]), 1)
        XCTAssertEqual(cubeDistance(targets[0], targets[2]), 1)
    }

    func testIsMeleePattern() {
        XCTAssertTrue(AoEResolver.isMeleePattern(deepTerrorLine))
        XCTAssertTrue(AoEResolver.isMeleePattern(cleave))
        XCTAssertFalse(AoEResolver.isMeleePattern(flower))
        XCTAssertFalse(AoEResolver.isMeleePattern(triangle))
    }

    // MARK: - Melee AoE

    func testDeepTerrorLine_hitsFiveEnemiesInALine_everyDirection() {
        for dir in 0..<6 {
            let board = makeBoard(cols: 16, rows: 16)
            let attacker = HexCoord(7, 7)
            let enemies = placeEnemies(board, at: ray(from: attacker, dir: dir, count: 5))
            let focus = enemies[2] // focus 3 hexes away — still reachable by the line
            let targets = AoEResolver.resolveTargets(
                pattern: deepTerrorLine, attackerPos: attacker,
                focusTarget: focus, enemies: enemies, board: board
            )
            XCTAssertEqual(targets.count, 5, "direction \(dir)")
            XCTAssertEqual(Set(targets), Set(enemies), "direction \(dir)")
            XCTAssertEqual(targets.first, focus, "focus is listed first")
        }
    }

    func testDeepTerrorLine_fromOddRow() {
        let board = makeBoard(cols: 16, rows: 16)
        let attacker = HexCoord(6, 7) // odd row
        let line = ray(from: attacker, dir: 2, count: 5) // SE diagonal
        let enemies = placeEnemies(board, at: line)
        let targets = AoEResolver.resolveTargets(
            pattern: deepTerrorLine, attackerPos: attacker,
            focusTarget: enemies[4], enemies: enemies, board: board
        )
        XCTAssertEqual(Set(targets), Set(enemies))
    }

    func testDeepTerrorLine_choosesLineContainingFocus() {
        let board = makeBoard(cols: 16, rows: 16)
        let attacker = HexCoord(7, 7)
        // Three enemies along the E line, one focus alone along the W line.
        let east = placeEnemies(board, at: ray(from: attacker, dir: 1, count: 3))
        let focus = PieceID.character("focus")
        board.placePiece(focus, at: ray(from: attacker, dir: 4, count: 2).last!)
        let targets = AoEResolver.resolveTargets(
            pattern: deepTerrorLine, attackerPos: attacker,
            focusTarget: focus, enemies: east + [focus], board: board
        )
        XCTAssertEqual(targets, [focus], "the pattern must cover the focus even if another line hits more")
    }

    func testMeleeRing_hitsAllSixNeighbors() {
        let board = makeBoard(cols: 10, rows: 10)
        let attacker = HexCoord(4, 4)
        let enemies = placeEnemies(board, at: attacker.neighbors)
        // Another enemy two hexes away is not hit.
        let far = PieceID.character("far")
        board.placePiece(far, at: HexCoord(7, 4))
        let targets = AoEResolver.resolveTargets(
            pattern: meleeRing, attackerPos: attacker,
            focusTarget: enemies[3], enemies: enemies + [far], board: board
        )
        XCTAssertEqual(Set(targets), Set(enemies))
    }

    func testCleave_maximizesTargetsWhileHittingFocus() {
        let board = makeBoard(cols: 10, rows: 10)
        let attacker = HexCoord(4, 4)
        let n = attacker.neighbors
        let focus = PieceID.character("focus")
        let other = PieceID.character("other")
        let loner = PieceID.character("loner")
        board.placePiece(focus, at: n[0])
        board.placePiece(other, at: n[1]) // adjacent to focus — cleave can hit both
        board.placePiece(loner, at: n[3]) // opposite side
        let targets = AoEResolver.resolveTargets(
            pattern: cleave, attackerPos: attacker,
            focusTarget: focus, enemies: [focus, other, loner], board: board
        )
        XCTAssertEqual(targets, [focus, other])
    }

    func testMeleePattern_cannotReachFocus_returnsEmpty() {
        let board = makeBoard(cols: 10, rows: 10)
        let focus = PieceID.character("focus")
        board.placePiece(focus, at: HexCoord(7, 4))
        let targets = AoEResolver.resolveTargets(
            pattern: cleave, attackerPos: HexCoord(3, 4),
            focusTarget: focus, enemies: [focus], board: board,
            range: 6 // range is irrelevant for melee patterns
        )
        XCTAssertTrue(targets.isEmpty)
    }

    func testMeleeLine_requiresLineOfSightToEachTarget() {
        let board = makeBoard(cols: 16, rows: 16)
        let attacker = HexCoord(2, 5)
        // A wall across column 4 (rows 4-6) cuts the line after the first hex.
        for row in 4...6 {
            board.cells[HexCoord(4, row)]!.passable = false
            board.cells[HexCoord(4, row)]!.overlay = .wall
        }
        let focus = PieceID.character("focus")
        board.placePiece(focus, at: HexCoord(3, 5))
        let hidden = placeEnemies(board, at: [HexCoord(5, 5), HexCoord(6, 5)])
        let targets = AoEResolver.resolveTargets(
            pattern: deepTerrorLine, attackerPos: attacker,
            focusTarget: focus, enemies: [focus] + hidden, board: board
        )
        XCTAssertEqual(targets, [focus], "enemies behind the wall are out of sight")
    }

    func testObstaclesDoNotStopAoE() {
        let board = makeBoard(cols: 16, rows: 16)
        let attacker = HexCoord(2, 5)
        board.placeObstacle(at: HexCoord(4, 5))
        let enemies = placeEnemies(board, at: [HexCoord(3, 5), HexCoord(5, 5), HexCoord(6, 5)])
        let targets = AoEResolver.resolveTargets(
            pattern: deepTerrorLine, attackerPos: attacker,
            focusTarget: enemies[0], enemies: enemies, board: board
        )
        XCTAssertEqual(Set(targets), Set(enemies))
    }

    func testOnlyListedEnemiesAreHit() {
        // Untargetable figures (e.g. invisible) are filtered out by the caller.
        let board = makeBoard(cols: 10, rows: 10)
        let attacker = HexCoord(4, 4)
        let enemies = placeEnemies(board, at: attacker.neighbors)
        let visible = Array(enemies.prefix(4))
        let targets = AoEResolver.resolveTargets(
            pattern: meleeRing, attackerPos: attacker,
            focusTarget: visible[0], enemies: visible, board: board
        )
        XCTAssertEqual(Set(targets), Set(visible))
    }

    // MARK: - Ranged AoE

    func testFlower_hitsAllSevenWhenOccupied() {
        let board = makeBoard(cols: 16, rows: 16)
        let attacker = HexCoord(2, 6)
        let center = HexCoord(6, 6) // 4 hexes away; nearest petal is 3 away
        let enemies = placeEnemies(board, at: [center] + center.neighbors)
        let focus = enemies[1]
        let targets = AoEResolver.resolveTargets(
            pattern: flower, attackerPos: attacker,
            focusTarget: focus, enemies: enemies, board: board, range: 3
        )
        XCTAssertEqual(targets.count, 7)
        XCTAssertEqual(Set(targets), Set(enemies))
        XCTAssertEqual(targets.first, focus)
    }

    func testFlower_oddRowCenter() {
        let board = makeBoard(cols: 16, rows: 16)
        let attacker = HexCoord(3, 3)
        let center = HexCoord(7, 7)
        let enemies = placeEnemies(board, at: [center] + center.neighbors)
        let targets = AoEResolver.resolveTargets(
            pattern: flower, attackerPos: attacker,
            focusTarget: enemies[0], enemies: enemies, board: board, range: 6
        )
        XCTAssertEqual(Set(targets), Set(enemies))
    }

    func testRangedPattern_placedWithinRangeCoversFocus() {
        let board = makeBoard(cols: 16, rows: 16)
        let attacker = HexCoord(2, 6)
        let focus = PieceID.character("focus")
        board.placePiece(focus, at: HexCoord(5, 6)) // distance 3
        // Range 2: the focus is out of range, but a triangle hex next to it is in range.
        let placement = AoEResolver.bestPlacement(
            pattern: triangle, attackerPos: attacker,
            focusTarget: focus, enemies: [focus], board: board, range: 2
        )
        XCTAssertNotNil(placement)
        XCTAssertEqual(placement?.targets, [focus])
        XCTAssertTrue(placement!.targetHexes.contains(HexCoord(5, 6)))
        XCTAssertTrue(placement!.targetHexes.contains { $0.distance(to: attacker) <= 2 },
                      "at least one red hex is within range")
    }

    func testRangedPattern_outOfReach_returnsEmpty() {
        let board = makeBoard(cols: 16, rows: 16)
        let attacker = HexCoord(2, 6)
        let focus = PieceID.character("focus")
        board.placePiece(focus, at: HexCoord(6, 6)) // distance 4: triangle can't bring a hex to ≤ 2
        let targets = AoEResolver.resolveTargets(
            pattern: triangle, attackerPos: attacker,
            focusTarget: focus, enemies: [focus], board: board, range: 2
        )
        XCTAssertTrue(targets.isEmpty)
    }

    func testRangedPattern_maximizesAdditionalTargets() {
        let board = makeBoard(cols: 16, rows: 16)
        let attacker = HexCoord(2, 6)
        let focusPos = HexCoord(6, 6)
        let focus = PieceID.character("focus")
        board.placePiece(focus, at: focusPos)
        // Two enemies that form a triangle with the focus, and one that doesn't fit with them.
        let a = PieceID.character("a"), b = PieceID.character("b"), c = PieceID.character("c")
        board.placePiece(a, at: focusPos.neighbors[1])
        board.placePiece(b, at: focusPos.neighbors[2])
        board.placePiece(c, at: focusPos.neighbors[4])
        let targets = AoEResolver.resolveTargets(
            pattern: triangle, attackerPos: attacker,
            focusTarget: focus, enemies: [focus, a, b, c], board: board, range: 4
        )
        XCTAssertEqual(targets.first, focus)
        XCTAssertEqual(Set(targets), Set([focus, a, b]))
    }

    func testRangedPattern_requiresLineOfSightToEachTarget() {
        // Two rooms separated by a void column; the drake sees the focus through a gap but not
        // the enemy tucked behind the wall.
        let board = makeBoard(cols: 16, rows: 16)
        for row in 0..<16 where row != 6 {
            board.cells[HexCoord(5, row)] = nil
        }
        let attacker = HexCoord(3, 6)
        let focus = PieceID.character("focus")
        board.placePiece(focus, at: HexCoord(6, 6))
        let hidden = PieceID.character("hidden")
        board.placePiece(hidden, at: HexCoord(6, 8)) // one flower (centered on (6,7)) covers all three
        let neighbor = PieceID.character("neighbor")
        board.placePiece(neighbor, at: HexCoord(7, 6))
        let targets = AoEResolver.resolveTargets(
            pattern: flower, attackerPos: attacker,
            focusTarget: focus, enemies: [focus, hidden, neighbor], board: board, range: 3
        )
        XCTAssertEqual(targets.first, focus)
        XCTAssertTrue(targets.contains(neighbor))
        XCTAssertFalse(targets.contains(hidden), "targets out of line of sight are not hit")
        XCTAssertFalse(LineOfSight.hasLOS(from: attacker, to: HexCoord(6, 8), board: board))
    }

    func testRangedPattern_focusOutOfSight_returnsEmpty() {
        let board = makeBoard(cols: 16, rows: 16)
        for row in 0..<16 {
            board.cells[HexCoord(5, row)] = nil
        }
        let focus = PieceID.character("focus")
        board.placePiece(focus, at: HexCoord(6, 6))
        let targets = AoEResolver.resolveTargets(
            pattern: flower, attackerPos: HexCoord(3, 6),
            focusTarget: focus, enemies: [focus], board: board, range: 3
        )
        XCTAssertTrue(targets.isEmpty)
    }

    func testRangedPattern_defaultRangeIsOne() {
        let board = makeBoard(cols: 10, rows: 10)
        let attacker = HexCoord(4, 4)
        let focus = PieceID.character("focus")
        board.placePiece(focus, at: HexCoord(6, 4)) // distance 2, adjacent hex is at distance 1
        XCTAssertEqual(AoEResolver.resolveTargets(
            pattern: triangle, attackerPos: attacker,
            focusTarget: focus, enemies: [focus], board: board
        ), [focus])
    }

    func testRangedPlacements_allCoverAnchorAndAreInRange() {
        let board = makeBoard(cols: 16, rows: 16)
        let attacker = HexCoord(2, 6)
        let anchor = HexCoord(5, 6)
        let placements = AoEResolver.rangedPlacements(
            pattern: flower, covering: anchor, attackerPos: attacker, range: 2, board: board
        )
        XCTAssertFalse(placements.isEmpty)
        for placement in placements {
            XCTAssertEqual(placement.count, 7)
            XCTAssertTrue(placement.contains(anchor))
            XCTAssertTrue(placement.contains { $0.distance(to: attacker) <= 2 })
        }
        // No duplicates (the flower is symmetric under rotation).
        XCTAssertEqual(Set(placements.map(Set.init)).count, placements.count)
        // A flower can cover the anchor in exactly 7 distinct ways (anchor at each of its hexes),
        // minus those that bring no hex within range 2.
        XCTAssertLessThanOrEqual(placements.count, 7)
    }

    func testFocusNotInEnemyList_returnsEmpty() {
        let board = makeBoard(cols: 10, rows: 10)
        let focus = PieceID.character("focus")
        board.placePiece(focus, at: HexCoord(5, 4))
        XCTAssertTrue(AoEResolver.resolveTargets(
            pattern: cleave, attackerPos: HexCoord(4, 4),
            focusTarget: focus, enemies: [], board: board
        ).isEmpty)
    }
}
