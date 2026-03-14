import XCTest
@testable import GlavenGameLib

/// Tests for battle goal evaluation (Rulebook p.35).
/// "At the end of every scenario, each character checks whether they
///  achieved their battle goal."
final class BattleGoalTests: XCTestCase {

    private func makeChar(hand: Int = 5, discard: Int = 3, health: Int = 5, maxHealth: Int = 10,
                           kills: Int = 0, coins: Int = 0) -> (GameCharacter, ScenarioCharacterStats) {
        let char = GameCharacter(name: "brute", edition: "gh", level: 3, characterData: nil)
        char.health = health
        char.maxHealth = maxHealth
        char.handCards = Array(1...max(1, hand))
        char.discardedCards = Array(100..<(100 + discard))
        let stats = ScenarioCharacterStats(kills: kills, coinsLooted: coins)
        return (char, stats)
    }

    // MARK: - Unit: Individual Goal Evaluation

    func testStreamliner_458_handPlusDiscardGTE5() {
        let (char, stats) = makeChar(hand: 3, discard: 2)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "458", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), true,
                       "3 hand + 2 discard = 5 >= 5")

        let (char2, stats2) = makeChar(hand: 2, discard: 2)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "458", character: char2, stats: stats2, scenarioXP: 0, alliesExhausted: false), false,
                       "2 + 2 = 4 < 5")
    }

    func testLayabout_459_xpLTE7() {
        let (char, stats) = makeChar()
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "459", character: char, stats: stats, scenarioXP: 7, alliesExhausted: false), true)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "459", character: char, stats: stats, scenarioXP: 8, alliesExhausted: false), false)
    }

    func testWorkhorse_460_xpGTE13() {
        let (char, stats) = makeChar()
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "460", character: char, stats: stats, scenarioXP: 13, alliesExhausted: false), true)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "460", character: char, stats: stats, scenarioXP: 12, alliesExhausted: false), false)
    }

    func testZealot_461_handPlusDiscardLTE3() {
        let (char, stats) = makeChar(hand: 1, discard: 2)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "461", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), true,
                       "1 + 2 = 3 <= 3")

        let (char2, stats2) = makeChar(hand: 2, discard: 2)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "461", character: char2, stats: stats2, scenarioXP: 0, alliesExhausted: false), false,
                       "2 + 2 = 4 > 3")
    }

    func testMasochist_462_healthLTE2() {
        let (char, stats) = makeChar(health: 2)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "462", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), true)

        let (char2, stats2) = makeChar(health: 3)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "462", character: char2, stats: stats2, scenarioXP: 0, alliesExhausted: false), false)
    }

    func testFastHealer_463_fullHP() {
        let (char, stats) = makeChar(health: 10, maxHealth: 10)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "463", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), true)

        let (char2, stats2) = makeChar(health: 9, maxHealth: 10)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "463", character: char2, stats: stats2, scenarioXP: 0, alliesExhausted: false), false)
    }

    func testProtector_466_noAlliesExhausted() {
        let (char, stats) = makeChar()
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "466", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), true)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "466", character: char, stats: stats, scenarioXP: 0, alliesExhausted: true), false)
    }

    func testHoarder_468_coinsGTE5() {
        let (char, _) = makeChar()
        let stats = ScenarioCharacterStats(coinsLooted: 5)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "468", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), true)

        let stats2 = ScenarioCharacterStats(coinsLooted: 4)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "468", character: char, stats: stats2, scenarioXP: 0, alliesExhausted: false), false)
    }

    func testIndigent_469_noCoins() {
        let (char, _) = makeChar()
        let stats = ScenarioCharacterStats(coinsLooted: 0)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "469", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), true)

        let stats2 = ScenarioCharacterStats(coinsLooted: 1)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "469", character: char, stats: stats2, scenarioXP: 0, alliesExhausted: false), false)
    }

    func testPacifist_470_killsLTE3() {
        let (char, _) = makeChar()
        let stats = ScenarioCharacterStats(kills: 3)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "470", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), true)

        let stats2 = ScenarioCharacterStats(kills: 4)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "470", character: char, stats: stats2, scenarioXP: 0, alliesExhausted: false), false)
    }

    func testSadist_471_killsGTE5() {
        let (char, _) = makeChar()
        let stats = ScenarioCharacterStats(kills: 5)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "471", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), true)

        let stats2 = ScenarioCharacterStats(kills: 4)
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "471", character: char, stats: stats2, scenarioXP: 0, alliesExhausted: false), false)
    }

    func testPurist_476_noItemsUsed() {
        let (char, stats) = makeChar()
        char.spentItems = []
        char.consumedItems = []
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "476", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), true)

        char.spentItems = ["gh-1"]
        XCTAssertEqual(BattleGoalEvaluator.evaluate(cardId: "476", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false), false)
    }

    func testUnevaluableGoal_returnsNil() {
        let (char, stats) = makeChar()
        // Neutralizer (464) needs trap event tracking
        XCTAssertNil(BattleGoalEvaluator.evaluate(cardId: "464", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false))
        // Diehard (478) needs continuous HP tracking
        XCTAssertNil(BattleGoalEvaluator.evaluate(cardId: "478", character: char, stats: stats, scenarioXP: 0, alliesExhausted: false))
    }

    // MARK: - E2E: Full Scenario Flow

    func testE2E_battleGoalAwarded_onVictory() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 10; char.maxHealth = 10

        // Select "Fast Healer" battle goal (463): HP must equal max HP
        char.battleGoalCardIds = ["463"]
        char.selectedBattleGoal = 0
        char.battleGoalProgress = 0

        // Set up stats manager
        let statsManager = ScenarioStatsManager(game: t.game)
        statsManager.reset()

        var scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        scenarioData.rewards = ScenarioRewards()
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.scenarioStatsManager = statsManager

        sm.finishScenario(success: true)

        // Fast Healer awards 1 check (health == maxHealth)
        XCTAssertEqual(char.battleGoalProgress, 1, "Should award 1 checkmark for Fast Healer")
    }

    func testE2E_battleGoalFailed_noCheckmarks() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 5; char.maxHealth = 10  // Not full HP

        // Select "Fast Healer" (463) — will fail since HP != maxHP
        char.battleGoalCardIds = ["463"]
        char.selectedBattleGoal = 0
        char.battleGoalProgress = 0

        let statsManager = ScenarioStatsManager(game: t.game)
        statsManager.reset()

        var scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        scenarioData.rewards = ScenarioRewards()
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.scenarioStatsManager = statsManager

        sm.finishScenario(success: true)

        XCTAssertEqual(char.battleGoalProgress, 0, "Failed goal should not award checkmarks")
    }

    func testE2E_twoCheckGoal_awardsBoth() {
        let t = TestGame()
        let char = t.addCharacter()
        char.handCards = Array(1...3)
        char.discardedCards = []

        // Select "Zealot" (461) — need hand+discard <= 3. Awards 1 check.
        // Select "Indigent" (469) — need coins == 0. Awards 2 checks.
        char.battleGoalCardIds = ["469"]
        char.selectedBattleGoal = 0
        char.battleGoalProgress = 0

        // Verify battle goal data loaded from edition
        let bgData = t.editionStore.battleGoals(for: "gh")
        let indigent = bgData.first(where: { $0.cardId == "469" })
        XCTAssertNotNil(indigent, "Indigent should be in battle goal data")
        XCTAssertEqual(indigent?.checks, 2, "Indigent awards 2 checks")

        let statsManager = ScenarioStatsManager(game: t.game)
        statsManager.reset()
        // No coins looted — should pass Indigent

        if let realScenario = t.editionStore.scenarios(for: "gh").first {
            t.game.scenario = Scenario(data: realScenario)
        } else {
            XCTFail("No GH scenarios loaded")
            return
        }

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.scenarioStatsManager = statsManager

        sm.finishScenario(success: true)

        XCTAssertEqual(char.battleGoalProgress, 2, "Indigent awards 2 checkmarks")
    }

    func testE2E_noBattleGoalSelected_noEffect() {
        let t = TestGame()
        let char = t.addCharacter()
        char.selectedBattleGoal = nil
        char.battleGoalProgress = 0

        let statsManager = ScenarioStatsManager(game: t.game)
        statsManager.reset()

        var scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        scenarioData.rewards = ScenarioRewards()
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.scenarioStatsManager = statsManager

        sm.finishScenario(success: true)

        XCTAssertEqual(char.battleGoalProgress, 0, "No battle goal selected = no checkmarks")
    }

    func testE2E_defeatDoesNotEvaluateBattleGoals() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 10; char.maxHealth = 10
        char.battleGoalCardIds = ["463"]  // Fast Healer — would pass
        char.selectedBattleGoal = 0
        char.battleGoalProgress = 0

        let statsManager = ScenarioStatsManager(game: t.game)
        statsManager.reset()

        var scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        scenarioData.rewards = ScenarioRewards()
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.scenarioStatsManager = statsManager

        sm.finishScenario(success: false)

        XCTAssertEqual(char.battleGoalProgress, 0, "Defeat should not evaluate battle goals")
    }

    func testE2E_killBasedGoal_withRealStats() {
        let t = TestGame()
        let char = t.addCharacter()

        // Select "Sadist" (471) — kill >= 5 monsters
        char.battleGoalCardIds = ["471"]
        char.selectedBattleGoal = 0
        char.battleGoalProgress = 0

        let statsManager = ScenarioStatsManager(game: t.game)
        statsManager.reset()

        // Record 6 kills
        for _ in 0..<6 {
            statsManager.recordKill(by: char.name)
        }

        var scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        scenarioData.rewards = ScenarioRewards()
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.scenarioStatsManager = statsManager

        sm.finishScenario(success: true)

        XCTAssertEqual(char.battleGoalProgress, 1, "Sadist achieved with 6 kills")
    }
}
