import XCTest
@testable import GlavenGameLib

/// The scenario level (rulebook p.15; gh-rules.md SET-3, SET-4): half the average character
/// level, rounded up, moved by the difficulty and kept within 0–7 — as the game sets it when a
/// scenario starts — and what the level fixes: the monsters' level and the bonus experience.
/// (Solo play's +1 is not here. Gold per token is in LootRuleTests, trap damage in
/// MovementRuleTests.)
@MainActor
final class ScenarioLevelRuleTests: XCTestCase {

    /// A party of these levels at this difficulty.
    private func party(levels: [Int], difficulty: DifficultyMode) throws -> GameManager {
        let gm = try SaveAndContinueTestsSupport.manager()
        for (name, level) in zip(["brute", "tinkerer", "spellweaver", "scoundrel"], levels) {
            gm.characterManager.addCharacter(name: name, edition: "gh")
            gm.characterManager.setLevel(level, for: try XCTUnwrap(gm.game.characters.last))
        }
        gm.game.difficulty = difficulty
        return gm
    }

    /// …and Black Barrow started on the board by it.
    private func start(levels: [Int], difficulty: DifficultyMode) throws -> GameManager {
        let gm = try party(levels: levels, difficulty: difficulty)
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        gm.boardCoordinator.boardScene = nil
        return gm
    }

    /// SET-3: "the recommended scenario level is equal to the average level of the characters
    /// divided by 2 and rounded up"; Easy −1, Hard +1, Very Hard +2.
    func testTheScenarioLevelForSeveralPartiesAndEveryDifficulty() throws {
        let cases: [(levels: [Int], normal: Int)] = [
            ([1, 1], 1),            // 1 ÷ 2 = 0.5
            ([1, 2], 1),            // 1.5 ÷ 2 = 0.75
            ([2, 2], 1),
            ([2, 3, 3], 2),         // 2.67 ÷ 2 = 1.33
            ([4, 4, 4, 4], 2),
            ([5, 5], 3),            // 2.5
            ([1, 9], 3),            // 5 ÷ 2 = 2.5
            ([6, 6, 7], 4),         // 6.33 ÷ 2 = 3.17
            ([7, 8, 9], 4),
            ([9, 9, 9, 9], 5),      // 4.5
        ]
        let shifts: [(DifficultyMode, Int)] = [(.easy, -1), (.normal, 0), (.hard, 1), (.veryHard, 2)]
        for (levels, normal) in cases {
            let gm = try party(levels: levels, difficulty: .normal)
            for (difficulty, shift) in shifts {
                // What starting a scenario does first: the level is fixed from the party.
                gm.game.difficulty = difficulty
                gm.levelManager.calculateAndApplyLevel()
                XCTAssertEqual(gm.game.level, normal + shift, "levels \(levels) on \(difficulty.label)")
            }
        }
    }

    /// SET-3: the level is never below 0 or above 7 — and (SET-4) it is the monsters' level and
    /// decides the bonus experience, 4 + 2L.
    func testTheLevelStaysWithinZeroAndSevenAndSetsTheMonsters() throws {
        let low = try start(levels: [1, 1], difficulty: .easy)
        XCTAssertEqual(low.game.level, 0)
        XCTAssertEqual(low.levelManager.experience(), 4)
        // The game's own "Story" setting (two levels down) can't take it below 0 either.
        low.game.difficulty = .story
        low.levelManager.calculateAndApplyLevel()
        XCTAssertEqual(low.game.level, 0)
        low.game.difficulty = .easy

        let high = try start(levels: [9, 9, 9, 9], difficulty: .veryHard)
        XCTAssertEqual(high.game.level, 7)
        XCTAssertEqual(high.levelManager.experience(), 18)
        high.levelManager.setLevel(9)
        XCTAssertEqual(high.game.level, 7, "set by hand, still no higher than 7")
        high.levelManager.setLevel(-3)
        XCTAssertEqual(high.game.level, 0)

        for gm in [low, try start(levels: [5, 5], difficulty: .normal), try start(levels: [9, 9, 9, 9], difficulty: .veryHard)] {
            let onBoard = gm.game.monsters.filter { !$0.aliveEntities.isEmpty }
            XCTAssertFalse(onBoard.isEmpty)
            for monster in onBoard {
                XCTAssertEqual(monster.level, gm.game.level, "\(monster.name) is of the scenario's level")
                XCTAssertTrue(monster.aliveEntities.allSatisfy { $0.level == gm.game.level })
            }
        }
    }
}
