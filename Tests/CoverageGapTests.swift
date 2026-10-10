import XCTest
@testable import GlavenGameLib

// =============================================================================
// Tests to fill coverage gaps identified in the feature audit.
// =============================================================================

// Advantage and Disadvantage — Strengthen, Muddle, a ranged attack on an adjacent enemy, the two
// cancelling, two sources of Disadvantage counting once — are tested by the cards a real attack
// draws: ConditionRuleTests.testStrengthenGivesAdvantageMuddleDisadvantageAndBothCancel,
// AttackRuleTests.testARangedAttackOnAnAdjacentEnemyDrawsTwoCardsAndKeepsTheWorse and
// testAnArcherBesideItsTargetShootsWithDisadvantage. (The tests that were here handed
// CombatResolver the flag they then asserted.)

// MARK: - Monster Trap Avoidance with Fallback

final class MonsterTrapAvoidanceFallbackTests: XCTestCase {

    /// Monster avoids trap when alternative path exists.
    func testAvoidsTrap_whenAlternativeExists() throws {
        let board = makeBoard(cols: 10, rows: 5)
        let trapCoord = HexCoord(4, 2)
        board.cells[trapCoord] = HexCell(coord: trapCoord, tileRef: "test",
                                          passable: true, overlay: .trap, trapDamage: 3)

        let path = Pathfinder.findPath(
            board: board, from: HexCoord(2, 2), to: HexCoord(6, 2),
            avoidTraps: true, occupiedByEnemy: []
        )

        let avoiding = try XCTUnwrap(path)
        XCTAssertFalse(avoiding.contains(trapCoord), "Should avoid trap when alternative exists")
        XCTAssertEqual(avoiding.first, HexCoord(2, 2))
        XCTAssertEqual(avoiding.last, HexCoord(6, 2))
    }

    /// Monster walks through trap when it's the only path.
    func testWalksThroughTrap_whenOnlyPath() throws {
        let board = makeBoard(cols: 8, rows: 3)
        // Block all rows except through the trap
        for row in 0..<3 {
            board.cells[HexCoord(3, row)]!.passable = false
        }
        // Open a gap with a trap
        board.cells[HexCoord(3, 1)] = HexCell(coord: HexCoord(3, 1), tileRef: "test",
                                               passable: true, overlay: .trap, trapDamage: 3)

        let path = Pathfinder.findPath(
            board: board, from: HexCoord(1, 1), to: HexCoord(5, 1),
            avoidTraps: true, occupiedByEnemy: []
        )

        let only = try XCTUnwrap(path, "Should find path through trap as fallback")
        XCTAssertTrue(only.contains(HexCoord(3, 1)), "Path goes through trap when no alternative")
    }

    /// Without trap avoidance (a character's own move) the path is simply the shortest: in a
    /// corridor one hex wide it runs straight over the trap, where an avoiding path has to as well.
    func testAvoidTraps_false_takesTheShortestWayOverTheTrap() throws {
        let board = makeBoard(cols: 10, rows: 5)
        for hex in Array(board.cells.keys) where hex.row != 2 { board.cells[hex] = nil }
        let trapCoord = HexCoord(4, 2)
        board.cells[trapCoord] = HexCell(coord: trapCoord, tileRef: "test",
                                          passable: true, overlay: .trap, trapDamage: 3)

        let direct = try XCTUnwrap(Pathfinder.findPath(
            board: board, from: HexCoord(2, 2), to: HexCoord(6, 2),
            avoidTraps: false, occupiedByEnemy: []
        ))
        XCTAssertEqual(direct, (2...6).map { HexCoord($0, 2) }, "straight along the corridor, trap and all")

        // On an open floor both ways are found, and the avoiding one is no shorter.
        let open = makeBoard(cols: 10, rows: 5)
        open.cells[trapCoord] = HexCell(coord: trapCoord, tileRef: "test", passable: true, overlay: .trap, trapDamage: 3)
        let shortest = try XCTUnwrap(Pathfinder.findPath(board: open, from: HexCoord(2, 2), to: HexCoord(6, 2),
                                                         avoidTraps: false, occupiedByEnemy: []))
        let avoiding = try XCTUnwrap(Pathfinder.findPath(board: open, from: HexCoord(2, 2), to: HexCoord(6, 2),
                                                         avoidTraps: true, occupiedByEnemy: []))
        XCTAssertEqual(shortest.count - 1, HexCoord(2, 2).distance(to: HexCoord(6, 2)))
        XCTAssertGreaterThanOrEqual(avoiding.count, shortest.count)
        XCTAssertFalse(avoiding.contains(trapCoord))
    }
}

// MARK: - Scenario Victory/Defeat Edge Cases

final class ScenarioFinishEdgeCaseTests: XCTestCase {

    /// End a scenario with no rewards of its own, so only what every scenario gives is counted.
    private func finish(_ t: TestGame, success: Bool) throws {
        t.game.scenario = Scenario(data: ScenarioData(index: "test", name: "Test", edition: "gh"))
        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                 monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: success)
        XCTAssertEqual(t.game.completedScenarios.isEmpty, !success)
    }

    /// Verify gold and XP are kept on defeat (GH p.47).
    func testDefeat_goldAndXPKept() throws {
        let t = TestGame()
        let char = t.addCharacter()
        char.loot = 25
        char.experience = 50

        try finish(t, success: false)
        XCTAssertEqual(char.loot, 25, "Gold kept on defeat")
        XCTAssertEqual(char.experience, 50, "XP kept on defeat")
    }

    /// Verify a defeat leaves every character's gold alone.
    func testDefeat_goldUntouched() throws {
        let t = TestGame()
        let active = t.addCharacter(name: "active", pos: HexCoord(2, 2))
        let absent = t.addCharacter(name: "absent", pos: HexCoord(3, 3))
        active.loot = 10
        absent.loot = 20
        absent.absent = true

        try finish(t, success: false)
        XCTAssertEqual(active.loot, 10, "Active character keeps gold")
        XCTAssertEqual(absent.loot, 20, "Absent character keeps gold")
    }

    /// Verify multiple characters all receive bonus XP on victory.
    func testVictory_allCharactersGetBonusXP() throws {
        let t = TestGame()
        let c1 = t.addCharacter(name: "brute", pos: HexCoord(2, 2))
        let c2 = t.addCharacter(name: "scoundrel", pos: HexCoord(3, 3))
        c1.experience = 0
        c2.experience = 0
        t.game.level = 2 // bonus = 4 + 2*2 = 8

        let absent = t.addCharacter(name: "tinkerer", pos: HexCoord(4, 4))
        absent.experience = 0
        absent.absent = true
        try finish(t, success: true)
        XCTAssertEqual(c1.experience, 8, "Character 1 gets exactly the bonus XP")
        XCTAssertEqual(c2.experience, 8, "Character 2 gets exactly the bonus XP")
        XCTAssertEqual(absent.experience, 0, "one who wasn't in the scenario gets none")
    }

    /// Verify scenario cleanup resets character state between scenarios.
    func testScenarioCleanup_resetsCharacterState() throws {
        let t = TestGame()
        let char = t.addCharacter()
        char.exhausted = true
        char.longRest = true
        char.discardedCards = [1, 2, 3]
        char.activeCards = [4, 5]
        char.spentItems = ["gh-1"]
        char.consumedItems = ["gh-2"]

        try finish(t, success: true)
        XCTAssertFalse(char.exhausted, "Exhaustion cleared")
        XCTAssertFalse(char.longRest, "Long rest cleared")
        XCTAssertTrue(char.discardedCards.isEmpty, "Discard returned to hand")
        XCTAssertTrue(char.activeCards.isEmpty, "Active cards returned to hand")
        XCTAssertTrue(char.spentItems.isEmpty, "Spent items cleared")
        XCTAssertTrue(char.consumedItems.isEmpty, "Consumed items cleared")
        XCTAssertTrue(char.handCards.contains(1), "Discarded card 1 in hand")
        XCTAssertTrue(char.handCards.contains(4), "Active card 4 in hand")
    }
}

// End-of-turn looting is tested through real turns in LootRuleTests
// (testACharacterLootsTheirHexAsTheirTurnEnds, testSummonsAndMonstersDoNotLootAtTheEndOfTheirTurns,
// testAFigurePushedOntoATokenDoesNotPickItUp), RestRuleTests.testARestTurnEndsWithLooting and
// TurnFlowTests.testAStunnedCharacterStillLootsAtTheEndOfTheTurn.
