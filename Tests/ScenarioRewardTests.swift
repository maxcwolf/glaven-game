import XCTest
@testable import GlavenGameLib

/// Completing a Gloomhaven scenario applies every reward its data lists that the campaign
/// models: items, item designs, collective gold, battle goal checks, character unlocks and
/// "choose one location" unlocks (GH p.47). Each test plays the real scenario's rewards.
@MainActor
final class ScenarioRewardTests: XCTestCase {

    private var gm: GameManager!

    override func setUpWithError() throws {
        gm = try SaveAndContinueTestsSupport.manager()
    }

    override func tearDown() {
        gm = nil
    }

    private var game: GameState { gm.game }

    @discardableResult
    private func addParty(_ names: String...) -> [GameCharacter] {
        for name in names { gm.characterManager.addCharacter(name: name, edition: "gh") }
        return names.compactMap { name in game.characters.first { $0.name == name } }
    }

    private func scenario(_ index: String) throws -> ScenarioData {
        try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil },
                      "GH scenario \(index)")
    }

    /// Start the scenario and win it.
    private func complete(_ data: ScenarioData, choices: ScenarioRewardChoices = ScenarioRewardChoices()) {
        gm.scenarioManager.setScenario(data)
        gm.scenarioManager.finishScenario(success: true, choices: choices)
    }

    // MARK: - Items

    func testItemReward_goesToOneCharacter() throws {
        let party = addParty("brute", "tinkerer")
        complete(try scenario("53"))  // Staff of Xorn (114)

        XCTAssertEqual(party[0].items, ["gh-114"], "one character takes the item")
        XCTAssertTrue(party[1].items.isEmpty, "only one copy is given")
        XCTAssertFalse(game.unlockedItems.contains("gh-114"), "the copy went to a character, not the supply")
        XCTAssertTrue(game.campaignLog.contains { $0.type == .itemAcquired && $0.message.contains("Staff of Xorn") })
    }

    func testItemReward_goesToTheChosenCharacter() throws {
        let party = addParty("brute", "tinkerer")
        var choices = ScenarioRewardChoices()
        choices.itemRecipients["gh-114"] = [party[1].id]
        complete(try scenario("53"), choices: choices)

        XCTAssertTrue(party[0].items.isEmpty)
        XCTAssertEqual(party[1].items, ["gh-114"], "the players' choice receives the item")
    }

    func testItemReward_skipsCharactersWhoAlreadyOwnIt() throws {
        let party = addParty("brute", "tinkerer")
        party[0].items = ["gh-114"]
        var choices = ScenarioRewardChoices()
        choices.itemRecipients["gh-114"] = [party[0].id]  // can't own two copies
        complete(try scenario("53"), choices: choices)

        XCTAssertEqual(party[0].items, ["gh-114"], "no second copy for its owner")
        XCTAssertEqual(party[1].items, ["gh-114"], "the copy goes to a character who can own it")
    }

    func testItemReward_nobodyCanTakeIt_goesToTheSupply() throws {
        let party = addParty("brute")
        party[0].items = ["gh-114"]
        XCTAssertFalse(gm.itemManager.isItemAvailable(try XCTUnwrap(gm.editionStore.itemData(id: 114, edition: "gh"))))
        complete(try scenario("53"))

        XCTAssertEqual(party[0].items, ["gh-114"])
        XCTAssertTrue(game.unlockedItems.contains("gh-114"), "an untakeable copy goes to the city's supply")
    }

    func testItemReward_twoCopies_goToDifferentCharacters() throws {
        let party = addParty("brute", "tinkerer", "spellweaver")
        complete(try scenario("68"))  // 2× Major Healing Potion (27)

        XCTAssertEqual(party.filter { $0.items.contains("gh-27") }.count, 2, "two characters gain a copy each")
        XCTAssertTrue(party.allSatisfy { $0.items.filter { $0 == "gh-27" }.count <= 1 })
    }

    func testItemReward_moreCopiesThanCharacters_restGoToTheSupply() throws {
        let party = addParty("brute")
        complete(try scenario("68"))

        XCTAssertEqual(party[0].items, ["gh-27"])
        XCTAssertTrue(game.unlockedItems.contains("gh-27"), "the copy no one could take is in the supply")
    }

    func testItemReward_absentCharactersReceiveNothing() throws {
        let party = addParty("brute", "tinkerer")
        party[0].absent = true
        complete(try scenario("53"))

        XCTAssertTrue(party[0].items.isEmpty, "an absent character didn't play the scenario")
        XCTAssertEqual(party[1].items, ["gh-114"])
    }

    func testSoloScenarioItem_goesToTheSoloCharacter() throws {
        let party = addParty("tinkerer", "brute")
        let solo = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.solo == "brute" })
        complete(solo)  // Imposing Blade (134)

        XCTAssertEqual(party[1].items, ["gh-134"])
        XCTAssertTrue(party[0].items.isEmpty)
    }

    // MARK: - Item designs

    func testItemDesign_addsTheItemToTheShop() throws {
        addParty("brute")
        let drill = try XCTUnwrap(gm.editionStore.itemData(id: 112, edition: "gh"))
        XCTAssertFalse(gm.itemManager.isItemAvailable(drill), "a design item starts out of the supply")

        complete(try scenario("65"))  // Ancient Drill design (112)

        XCTAssertTrue(game.unlockedItems.contains("gh-112"))
        XCTAssertTrue(gm.itemManager.isItemAvailable(drill), "every copy is now for sale")
        XCTAssertTrue(gm.itemManager.inStock(drill))
        XCTAssertTrue(game.characters.allSatisfy { $0.items.isEmpty }, "a design gives nobody the item")
    }

    // MARK: - Collective gold

    func testCollectiveGold_splitEvenlyByDefault() throws {
        let party = addParty("brute", "tinkerer", "spellweaver")
        let before = party.map(\.loot)
        complete(try scenario("55"))  // 10 collective gold

        let gained = zip(party, before).map { $0.loot - $1 }
        XCTAssertEqual(gained.reduce(0, +), 10, "all of the collective gold is handed out")
        XCTAssertEqual(gained, [4, 3, 3])
    }

    func testCollectiveGold_splitAsTheyChoose() throws {
        let party = addParty("brute", "tinkerer")
        for character in party { character.loot = 0 }
        var choices = ScenarioRewardChoices()
        choices.collectiveGold = [party[0].id: 10, party[1].id: 0]
        complete(try scenario("55"), choices: choices)

        XCTAssertEqual(party[0].loot, 10)
        XCTAssertEqual(party[1].loot, 0)
    }

    func testCollectiveGold_aSplitThatDoesNotAddUp_isSplitEvenly() throws {
        let party = addParty("brute", "tinkerer")
        for character in party { character.loot = 0 }
        var choices = ScenarioRewardChoices()
        choices.collectiveGold = [party[0].id: 50]
        complete(try scenario("55"), choices: choices)

        XCTAssertEqual(party.map(\.loot), [5, 5])
    }

    // MARK: - Battle goal checks

    func testBattleGoalReward_givesEachCharacterChecks() throws {
        let party = addParty("brute", "tinkerer")
        complete(try scenario("41"))  // 2 checkmarks

        XCTAssertEqual(party.map(\.battleGoalProgress), [2, 2])
    }

    /// Eighteen checkmarks is the most a character can hold (six perks' worth, p.46).
    func testBattleGoalChecksStopAtEighteen() throws {
        let party = addParty("brute", "tinkerer")
        party[0].battleGoalProgress = 17
        party[1].battleGoalProgress = 18
        complete(try scenario("41"))  // 2 checkmarks

        XCTAssertEqual(party.map(\.battleGoalProgress), [18, 18])
        XCTAssertEqual(gm.characterManager.perksAvailable(for: party[1]), 6)
    }

    /// Reputation from a scenario stays within −20…+20 (p.48).
    func testScenarioReputationStaysWithinTwenty() throws {
        addParty("brute")
        game.partyReputation = 19
        complete(try scenario("12"))  // reputation +4
        XCTAssertEqual(game.partyReputation, 20)
        game.partyReputation = -19
        complete(try scenario("11"))  // reputation −2
        XCTAssertEqual(game.partyReputation, -20)
    }

    // MARK: - Character unlocks

    func testUnlockCharacterReward_unlocksTheClass() throws {
        addParty("brute")
        XCTAssertFalse(game.unlockedCharacters.contains("gh-angry-face"))
        complete(try scenario("44"))

        XCTAssertTrue(game.unlockedCharacters.contains("gh-angry-face"))
        XCTAssertTrue(game.campaignLog.contains { $0.type == .characterUnlocked })
    }

    // MARK: - Choose a location

    func testChooseLocation_unlocksTheFirstByDefault() throws {
        addParty("brute")
        complete(try scenario("13"))  // one of 15, 17, 20

        XCTAssertTrue(game.manualScenarios.contains("gh-15"))
        XCTAssertFalse(game.manualScenarios.contains("gh-17"))
        XCTAssertFalse(game.manualScenarios.contains("gh-20"))
        XCTAssertTrue(gm.scenarioManager.isAvailable(try scenario("15")))
    }

    func testChooseLocation_unlocksOnlyTheChosenOne() throws {
        addParty("brute")
        var choices = ScenarioRewardChoices()
        choices.location = "17"
        complete(try scenario("13"), choices: choices)

        XCTAssertEqual(game.manualScenarios, ["gh-17"])
        XCTAssertTrue(gm.scenarioManager.isAvailable(try scenario("17")))
        XCTAssertFalse(gm.scenarioManager.isAvailable(try scenario("15")))
    }

    func testChooseLocation_ignoresAChoiceNotOffered() throws {
        addParty("brute")
        var choices = ScenarioRewardChoices()
        choices.location = "99"
        complete(try scenario("13"), choices: choices)

        XCTAssertEqual(game.manualScenarios, ["gh-15"])
    }

    // MARK: - No rewards on a failure

    func testFailedScenario_givesNoRewards() throws {
        let party = addParty("brute")
        gm.scenarioManager.setScenario(try scenario("53"))
        gm.scenarioManager.finishScenario(success: false)

        XCTAssertTrue(party[0].items.isEmpty)
        XCTAssertTrue(game.unlockedItems.isEmpty)
    }

    // MARK: - Treasures

    /// Black Barrow's treasure 7 is a random side scenario (p.43): one is unlocked and named.
    func testARandomScenarioTreasureUnlocksOne() throws {
        let brute = addParty("brute")[0]
        gm.scenarioManager.setScenario(try scenario("1"))
        let before = game.manualScenarios
        let label = gm.scenarioManager.lootTreasure("7", by: brute)
        let unlocked = game.manualScenarios.subtracting(before)
        XCTAssertEqual(unlocked.count, 1, "a random side scenario is unlocked")
        let drawn = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { unlocked.contains($0.id) })
        XCTAssertEqual(drawn.random, true)
        XCTAssertTrue(label?.contains(drawn.name) == true, "the reward names it: \(label ?? "nil")")
    }

    /// Treasure 1 is a random item design: one joins the city's supply.
    func testARandomItemDesignTreasureUnlocksOne() throws {
        let brute = addParty("brute")[0]
        gm.scenarioManager.setScenario(try scenario("1"))
        let before = game.unlockedItems
        gm.scenarioManager.lootTreasure("1", by: brute)
        let unlocked = game.unlockedItems.subtracting(before)
        XCTAssertEqual(unlocked.count, 1, "a random item design joins the supply")
        let item = try XCTUnwrap(gm.editionStore.items(for: "gh").first { unlocked.contains("gh-\($0.id)") })
        XCTAssertTrue(item.random)
    }
}
