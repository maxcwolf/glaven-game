import XCTest
@testable import GlavenGameLib

/// Tests for personal quest auto-tracking and completion.
/// Rulebook p.36: "When a character fulfills the conditions of the personal quest,
///  the character must retire."
final class PersonalQuestAutotrackTests: XCTestCase {

    // MARK: - Unit Tests: Completion Check

    func testIsComplete_allRequirementsMet() {
        let quest = loadQuest("512") // Gold quest: 200 gold
        XCTAssertNotNil(quest)
        guard let quest = quest else { return }

        let char = GameCharacter(name: "brute", edition: "gh", level: 5, characterData: nil)
        char.personalQuest = "512"
        char.personalQuestProgress = [200]

        XCTAssertTrue(PersonalQuestEvaluator.isComplete(character: char, quest: quest))
    }

    func testIsComplete_notMet() {
        let quest = loadQuest("512")
        guard let quest = quest else { return }

        let char = GameCharacter(name: "brute", edition: "gh", level: 5, characterData: nil)
        char.personalQuest = "512"
        char.personalQuestProgress = [150]

        XCTAssertFalse(PersonalQuestEvaluator.isComplete(character: char, quest: quest))
    }

    func testIsComplete_multipleRequirements() {
        let quest = loadQuest("510") // 2 requirements
        guard let quest = quest else { return }

        let char = GameCharacter(name: "brute", edition: "gh", level: 5, characterData: nil)
        char.personalQuest = "510"
        char.personalQuestProgress = [3, 1]  // Both met

        XCTAssertTrue(PersonalQuestEvaluator.isComplete(character: char, quest: quest))
    }

    func testIsComplete_partialProgress() {
        let quest = loadQuest("510")
        guard let quest = quest else { return }

        let char = GameCharacter(name: "brute", edition: "gh", level: 5, characterData: nil)
        char.personalQuest = "510"
        char.personalQuestProgress = [3, 0]  // First met, second not

        XCTAssertFalse(PersonalQuestEvaluator.isComplete(character: char, quest: quest))
    }

    // MARK: - Unit Tests: Gold Autotrack

    func testAutotrack_gold() {
        let t = TestGame()
        let char = t.addCharacter()
        char.personalQuest = "512"  // Need 200 gold
        char.loot = 250

        let complete = PersonalQuestEvaluator.updateProgress(
            character: char, game: t.game, editionStore: t.editionStore
        )

        XCTAssertTrue(complete, "Quest complete when gold >= 200")
        XCTAssertEqual(char.personalQuestProgress[0], 200, "Progress capped at requirement")
    }

    func testAutotrack_gold_notEnough() {
        let t = TestGame()
        let char = t.addCharacter()
        char.personalQuest = "512"
        char.loot = 100

        let complete = PersonalQuestEvaluator.updateProgress(
            character: char, game: t.game, editionStore: t.editionStore
        )

        XCTAssertFalse(complete)
        XCTAssertEqual(char.personalQuestProgress[0], 100)
    }

    // MARK: - Unit Tests: Scenario Autotrack

    func testAutotrack_scenario() {
        let t = TestGame()
        let char = t.addCharacter()
        char.personalQuest = "510"  // Three Crypts, then follow #52 Noxious Cellar to a conclusion

        // The first requirement, three Crypt scenarios, is counted from the character's record.
        char.record.scenariosCompleted = ["gh-4", "gh-5", "gh-6"]
        PersonalQuestEvaluator.updateProgress(character: char, game: t.game, editionStore: t.editionStore)
        XCTAssertEqual(t.game.manualScenarios, ["gh-52"], "the quest's scenario is unlocked at once (FAQ)")

        // #52 and #53 are on the way; the conclusion is #54 Palace of Ice.
        for (won, progress) in [("52", 0), ("53", 0), ("54", 1)] {
            t.game.completedScenarios.insert("gh-\(won)")
            let complete = PersonalQuestEvaluator.updateProgress(character: char, game: t.game, editionStore: t.editionStore)
            XCTAssertEqual(char.personalQuestProgress, [3, progress], "after #\(won)")
            XCTAssertEqual(complete, won == "54")
        }
        let chain = PersonalQuestEvaluator.questChain(
            PersonalQuestRequirement(name: "", counter: nil, autotrack: "scenario:52|53", requires: [1]),
            edition: "gh", editionStore: t.editionStore)
        XCTAssertEqual(chain.map(\.index), ["52", "53", "54"])
    }

    /// The other quests with a scenario of their own end with the last one of their chain.
    func testEveryQuestChainEndsWhereTheStoryDoes() throws {
        let t = TestGame()
        let ends = ["510": ["52", "53", "54"], "513": ["59", "60"], "521": ["55", "56"], "526": ["57", "58"], "529": ["61", "62"]]
        for (questId, expected) in ends {
            let quest = try XCTUnwrap(t.editionStore.personalQuest(cardId: questId, edition: "gh"))
            let chains = quest.requirements.map { PersonalQuestEvaluator.questChain($0, edition: "gh", editionStore: t.editionStore).map(\.index) }
            XCTAssertEqual(chains.filter { !$0.isEmpty }, [expected], "quest \(questId)")
        }
    }

    // MARK: - Unit Tests: Scenarios Completed Autotrack

    func testAutotrack_scenariosCompleted() {
        let t = TestGame()
        let char = t.addCharacter()
        char.personalQuest = "518"  // Need 15 different scenarios completed (by this character)

        for i in 1...15 {
            char.record.scenariosCompleted.insert("gh-\(i)")
        }

        let complete = PersonalQuestEvaluator.updateProgress(
            character: char, game: t.game, editionStore: t.editionStore
        )

        XCTAssertTrue(complete, "Quest complete with 15 scenarios")
    }

    // MARK: - Unit Tests: Battle Goals Autotrack

    func testAutotrack_battleGoals() {
        let t = TestGame()
        let char = t.addCharacter()
        char.personalQuest = "519"  // Need 15 checkmarks from battle goals
        // Checkmarks on the sheet may come from events and treasures: those don't count (FAQ).
        char.battleGoalProgress = 15
        XCTAssertFalse(PersonalQuestEvaluator.updateProgress(character: char, game: t.game, editionStore: t.editionStore))
        XCTAssertEqual(char.personalQuestProgress, [0])

        char.record.battleGoalChecks = 15
        let complete = PersonalQuestEvaluator.updateProgress(
            character: char, game: t.game, editionStore: t.editionStore
        )

        XCTAssertTrue(complete)
    }

    // MARK: - Unit Tests: Retired Chars Autotrack

    func testAutotrack_retiredChars() {
        let t = TestGame()
        let char = t.addCharacter()
        char.personalQuest = "532"  // Need to see 2 other characters retire

        // Two who retired before this character joined: not theirs to count.
        let retired1 = GameCharacter(name: "old1", edition: "gh", level: 9, characterData: nil)
        let retired2 = GameCharacter(name: "old2", edition: "gh", level: 9, characterData: nil)
        t.game.retiredCharacters.append(retired1.toSnapshot())
        t.game.retiredCharacters.append(retired2.toSnapshot())
        XCTAssertFalse(PersonalQuestEvaluator.updateProgress(character: char, game: t.game, editionStore: t.editionStore))
        XCTAssertEqual(char.personalQuestProgress, [0])

        char.record.retirementsSeen = 2
        let complete = PersonalQuestEvaluator.updateProgress(
            character: char, game: t.game, editionStore: t.editionStore
        )

        XCTAssertTrue(complete)
    }

    // MARK: - Unit Tests: Item Ownership Autotrack

    func testAutotrack_item() {
        let t = TestGame()
        let char = t.addCharacter()
        char.personalQuest = "520"  // Need item 113 + 7 manual
        char.items = ["gh-113"]
        char.personalQuestProgress = [0, 7]  // manual progress already tracked

        PersonalQuestEvaluator.updateProgress(
            character: char, game: t.game, editionStore: t.editionStore
        )

        XCTAssertEqual(char.personalQuestProgress[0], 1, "Has item 113")
    }

    // MARK: - Unit Tests: No Quest Assigned

    func testUpdateProgress_noQuest() {
        let t = TestGame()
        let char = t.addCharacter()
        char.personalQuest = nil

        let complete = PersonalQuestEvaluator.updateProgress(
            character: char, game: t.game, editionStore: t.editionStore
        )

        XCTAssertFalse(complete)
    }

    // MARK: - E2E: Scenario Completion Triggers Quest Check

    func testE2E_scenarioVictory_updatesQuestProgress() {
        let t = TestGame()
        let char = t.addCharacter()
        char.personalQuest = "518"  // Need 15 scenarios completed

        // This character has already won 14 scenarios
        for i in 1...14 {
            char.record.scenariosCompleted.insert("gh-\(i)")
        }

        // Complete scenario 15 via finishScenario
        if let scenario = t.editionStore.scenarios(for: "gh").first(where: { $0.index == "15" }) {
            t.game.scenario = Scenario(data: scenario)
            let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                      monsterManager: t.monsterManager, levelManager: t.levelManager)
            sm.finishScenario(success: true)

            // Quest should be complete (15 scenarios)
            XCTAssertEqual(char.personalQuestProgress.first, 15,
                           "Quest progress updated to 15 after 15th scenario")

            // Campaign log should note quest completion
            let retireEntry = t.game.campaignLog.contains { $0.type == .characterRetired }
            XCTAssertTrue(retireEntry, "Campaign log should note quest completion")
        }
    }

    /// Progress is counted after a loss too (kills and gold count either way); a loss just
    /// isn't a scenario won.
    func testE2E_scenarioDefeat_stillCountsProgress() {
        let t = TestGame()
        let char = t.addCharacter()
        char.personalQuest = "512"  // Need 200 gold
        char.loot = 250  // Has enough gold

        var scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        scenarioData.rewards = ScenarioRewards()
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: false)

        XCTAssertEqual(char.personalQuestProgress.first, 200, "the gold counts after a loss")
        XCTAssertTrue(char.record.scenariosCompleted.isEmpty, "a loss isn't a scenario won")
    }

    // MARK: - Helpers

    private func loadQuest(_ cardId: String) -> PersonalQuestData? {
        let store = EditionDataStore()
        store.loadAllEditions()
        return store.personalQuest(cardId: cardId)
    }
}
