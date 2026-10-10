import XCTest
import SwiftData
@testable import GlavenGameLib

/// Scenario setup (GH p.12–15): which standees monsters take, and the scenario level.
@MainActor
final class SetupRulesTests: XCTestCase {

    private func eliteGuardNumbers(seed: UInt64) throws -> Set<Int> {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: seed))
        var numbers = Set<Int>()
        for piece in sim.coord.boardState.eliteStandees {
            if case .monster("bandit-guard", let standee) = piece { numbers.insert(standee) }
        }
        return numbers
    }

    /// "Standees should be placed randomly": within a type monsters act in standee order (elites
    /// first), so which monster holds which number decides who goes first. Black Barrow's two
    /// elite Bandit Guards for four characters don't always hold the same two numbers, and the
    /// six guards between them hold six different ones.
    func testStandeesAreDrawnAtRandomWhenAScenarioIsSetUp() throws {
        var seen = Set<Set<Int>>()
        for seed in 1...12 as ClosedRange<UInt64> {
            let numbers = try eliteGuardNumbers(seed: seed)
            XCTAssertEqual(numbers.count, 2, "two elite guards for four characters")
            seen.insert(numbers)
        }
        XCTAssertGreaterThan(seen.count, 3, "the elites' standees vary from game to game: \(seen)")
        XCTAssertEqual(try eliteGuardNumbers(seed: 5), try eliteGuardNumbers(seed: 5), "the same seed sets up the same game")

        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 3))
        let guards = sim.coord.boardState.piecePositions.keys.compactMap { piece -> Int? in
            if case .monster("bandit-guard", let standee) = piece { return standee }
            return nil
        }
        XCTAssertEqual(guards.count, 6)
        XCTAssertEqual(Set(guards), Set(1...6), "each of the six standees once")
    }

    /// A standee freed by a dead monster is used again, and is then whatever the newcomer is.
    func testAReusedStandeeTakesItsNewMonstersRank() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        let coord = gm.boardCoordinator
        coord.boardState = makeBoard()
        let elite = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .elite, at: HexCoord(3, 3), origin: .placed))
        XCTAssertTrue(coord.boardState.eliteStandees.contains(elite))
        coord.sufferDamage(99, to: elite)
        let normal = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(5, 5), origin: .placed))
        XCTAssertEqual(normal, elite, "boards built by hand number in order, so the freed standee is taken again")
        XCTAssertFalse(coord.boardState.eliteStandees.contains(normal), "and it is a normal monster now")
    }

    /// Only as many monsters of a type as it has standees can be on the board (GH p.13).
    func testNoMonsterIsPlacedOnceItsStandeesAreAllOut() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        let coord = gm.boardCoordinator
        coord.boardState = makeBoard(cols: 12, rows: 12)
        var placed = 0
        for column in 0..<10 where coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(column, 2), origin: .placed) != nil {
            placed += 1
        }
        XCTAssertEqual(placed, 6, "Bandit Guards have six standees")
        let numbers = coord.boardState.piecePositions.keys.compactMap { piece -> Int? in
            if case .monster(_, let standee) = piece { return standee }
            return nil
        }
        XCTAssertEqual(Set(numbers), Set(1...6))
    }

    // MARK: - Scenario level

    private func party(levels: [Int], difficulty: DifficultyMode = .normal, solo: Bool = false) throws -> GameManager {
        let gm = try SaveAndContinueTestsSupport.manager()
        for (name, level) in zip(["brute", "spellweaver", "cragheart", "scoundrel"], levels) {
            gm.characterManager.addCharacter(name: name, edition: "gh")
            gm.characterManager.setLevel(level, for: gm.game.characters.last!)
        }
        gm.game.difficulty = difficulty
        gm.game.solo = solo
        return gm
    }

    /// Solo play (GH p.15): "increase the monster level and trap damage by 1 … without increasing
    /// gold conversion and bonus experience". A level 3 and a level 4 character are scenario
    /// level 2; one player running both meets level 3 monsters and traps, for level 2's rewards.
    func testSoloPlayRaisesMonstersAndTrapsButNotGoldOrExperience() throws {
        let gm = try party(levels: [3, 4], solo: true)
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        XCTAssertEqual(gm.game.level, 2, "the scenario level is the party's")
        let guards = try XCTUnwrap(gm.game.monsters.first { $0.name == "bandit-guard" })
        XCTAssertEqual(guards.level, 3, "monsters are set up a level higher")
        XCTAssertEqual(gm.levelManager.trap(), 2 + 3, "trap damage with them")
        XCTAssertEqual(gm.levelManager.terrain(), 2, "and hazardous terrain, half a trap")
        XCTAssertEqual(gm.levelManager.loot(), 3, "a money token is worth what it is at level 2")
        XCTAssertEqual(gm.levelManager.experience(), 4 + 2 * 2, "and so is the bonus experience")
        // A monster arriving later in the scenario is of the same level.
        gm.boardCoordinator.spawnMonster(name: "living-bones", type: .normal, at: HexCoord(0, 0), origin: .spawned)
        XCTAssertEqual(gm.game.monsters.first { $0.name == "living-bones" }?.level, 3)

        let together = try party(levels: [3, 4])
        together.startScenarioOnBoard(scenario)
        XCTAssertEqual(together.game.monsters.first { $0.name == "bandit-guard" }?.level, 2, "a table of players meets level 2")
        XCTAssertEqual(together.levelManager.trap(), 2 + 2)
    }

    /// Monsters have no level above 7: solo play at scenario level 7 changes nothing.
    func testSoloPlayNeverGoesAboveLevelSeven() throws {
        let gm = try party(levels: [9, 9], difficulty: .veryHard, solo: true)
        gm.levelManager.calculateAndApplyLevel()
        XCTAssertEqual(gm.game.level, 7)
        XCTAssertEqual(gm.game.monsterLevel, 7)
        XCTAssertEqual(gm.levelManager.trap(), 2 + 7)
    }

    /// The rulebook's difficulties are Easy (−1), Normal, Hard (+1) and Very Hard (+2); "Story"
    /// (−2) is the game's own. None takes the scenario level below 0, and solo play counts from
    /// there.
    func testNoDifficultyTakesTheLevelBelowZero() throws {
        for difficulty in [DifficultyMode.story, .easy] {
            let gm = try party(levels: [1, 1], difficulty: difficulty)
            XCTAssertEqual(gm.levelManager.scenarioLevel(), 0, difficulty.label)
            gm.game.solo = true
            gm.levelManager.calculateAndApplyLevel()
            XCTAssertEqual(gm.game.level, 0, difficulty.label)
            XCTAssertEqual(gm.game.monsterLevel, 1, "\(difficulty.label), solo: a level above 0")
        }
        XCTAssertEqual(try party(levels: [3, 3], difficulty: .story).levelManager.scenarioLevel(), 0, "2 − 2")
        XCTAssertEqual(try party(levels: [5, 5], difficulty: .story).levelManager.scenarioLevel(), 1, "3 − 2")
    }

    /// The setup screen says what the solo switch does, in the line under the difficulty.
    func testTheSetupScreenSaysWhatSoloPlayDoes() throws {
        let gm = try party(levels: [3, 4])
        let plain = GameSetupView.difficultyHint(for: gm)
        XCTAssertFalse(plain.contains("solo"))
        gm.game.solo = true
        let hint = GameSetupView.difficultyHint(for: gm)
        XCTAssertTrue(hint.hasPrefix("Scenario level 2"), hint)
        XCTAssertTrue(hint.contains("monsters and traps at level 3"), hint)
        XCTAssertEqual(PlayerTextTests.lint(hint), [])
    }
}
