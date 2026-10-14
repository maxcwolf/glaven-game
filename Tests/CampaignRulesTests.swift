import XCTest
@testable import GlavenGameLib

/// The campaign's own rules (GH p.34–49 and the FAQ): which scenarios are on the map and open,
/// achievements and their types, what reputation and prosperity may do, and what a retirement
/// leaves behind. Scenarios are won the way play wins them: started on the board and finished.
@MainActor
final class CampaignRulesTests: XCTestCase {

    private var gm: GameManager!
    private var game: GameState { gm.game }
    private var scenarios: ScenarioManager { gm.scenarioManager }

    override func setUpWithError() throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
    }

    private var brute: GameCharacter { game.characters.first { $0.name == "brute" }! }

    private func scenario(_ index: String) throws -> ScenarioData {
        try XCTUnwrap(gm.editionStore.scenarioData(index: index, edition: "gh"), "#\(index)")
    }

    /// The campaign's open scenarios (the random dungeon, always open, aside).
    private func open() -> Set<String> { Set(scenarios.availableScenarios(for: "gh").filter { !$0.isDungeonVariant }.map(\.index)) }

    /// Win a scenario the way the board does: set out, then finish with a victory.
    private func win(_ index: String, choices: ScenarioRewardChoices = ScenarioRewardChoices(),
                     file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(open().contains(index), "#\(index) isn't open", file: file, line: line)
        gm.startScenarioOnBoard(try scenario(index))
        gm.completeScenario(success: true, choices: choices)
    }

    /// As if these were won earlier, with what they award.
    private func alreadyWon(_ indices: [String]) throws {
        for index in indices {
            gm.startScenarioOnBoard(try scenario(index))
            gm.completeScenario(success: true)
        }
    }

    // MARK: - Which scenarios are open

    /// A scenario is open only once something has put it on the map. #20 names #8 as the
    /// scenario to win first, but after #8 it is still off the map: only #7, or the Seer's
    /// choice after #13, unlocks it.
    func testWinningAPrerequisiteDoesntPutAScenarioOnTheMap() throws {
        try win("1"); try win("2"); try win("3"); try win("8")
        XCTAssertEqual(open(), ["4", "13", "14"], "#7 waits for The Power of Enhancement; #20 isn't unlocked")
        XCTAssertFalse(scenarios.isUnlocked(try scenario("20")))

        try win("13", choices: ScenarioRewardChoices(location: "17"))
        XCTAssertTrue(open().contains("17"), "the location chosen at the Temple of the Seer")
        XCTAssertFalse(open().contains("15"))
        XCTAssertFalse(open().contains("20"), "the Seer's other locations stay off the map")

        try win("14")
        XCTAssertTrue(open().contains("7"), "unlocked by #8, and now its achievements are there")
        try win("7")
        XCTAssertTrue(open().contains("20"), "#7 unlocks it")
    }

    /// The same for every scenario that names one to win first: winning that one alone opens
    /// nothing that hasn't been unlocked.
    func testPrerequisitesAloneOpenNothing() throws {
        let cases: [(won: [String], closed: [String], stillOpen: [String])] = [
            (["1", "2", "4", "6"], ["28"], ["8"]),
            (["1", "2", "4", "5", "10"], ["35", "36"], ["21", "22"]),
            (["24"], ["41", "33"], ["30", "32"]),
            (["35"], ["49", "50"], ["45"]),
            (["14"], ["19", "43"], []),
            (["43"], ["37", "64"], []),
        ]
        for (won, closed, stillOpen) in cases {
            gm.newGame()
            gm.setEdition("gh")
            gm.characterManager.addCharacter(name: "brute", edition: "gh")
            gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
            try alreadyWon(won)
            for index in closed {
                XCTAssertFalse(open().contains(index), "#\(index) after \(won)")
                XCTAssertTrue(scenarios.isLocked(try scenario(index)), "#\(index) after \(won)")
            }
            for index in stillOpen { XCTAssertTrue(open().contains(index), "#\(index) after \(won)") }
        }
    }

    /// Requirements: an achievement that must be missing ("INCOMPLETE"), either of two sets,
    /// a scenario another one closes off, and one that isn't replayed.
    func testRequirementsBlocksAndEitherOrSets() throws {
        try win("1"); try win("2")
        XCTAssertEqual(open(), ["3", "4"])
        XCTAssertFalse(open().contains("1"), "a won scenario isn't open again")
        try win("3")
        XCTAssertEqual(open(), ["4", "8", "9"])

        // #9 gives The Dead Invade: #8 needs it missing, and #9 closes #8 off as well.
        try win("9")
        XCTAssertFalse(open().contains("8"))
        XCTAssertTrue(scenarios.isBlocked(try scenario("8")))
        XCTAssertTrue(open().isSuperset(of: ["11", "12"]))

        // #26 Ancient Cistern: Water-Breathing or Through the Ruins. Unlocked with neither, it
        // stays closed; either one opens it.
        game.manualScenarios.insert("gh-26")
        game.completedScenarios.formUnion(["gh-23", "gh-43"])   // the scenarios it names
        XCTAssertFalse(open().contains("26"))
        game.gainGlobalAchievement("water-breathing")
        XCTAssertTrue(open().contains("26"))
        game.globalAchievements.remove("water-breathing")
        game.gainPartyAchievement("through-the-ruins")
        XCTAssertTrue(open().contains("26"))

        // #11 and #12 need End of the Invasion missing, and each closes the other.
        try win("11")
        XCTAssertFalse(open().contains("12"))
        XCTAssertTrue(open().isSuperset(of: ["16", "18"]))
    }

    // MARK: - Achievements

    /// #51 The Void asks for End of Corruption three times over: each of #46, #47 and #48
    /// awards one, and the third opens it.
    func testTheVoidOpensAfterThreeEndsOfCorruption() throws {
        game.completedScenarios.formUnion(["gh-37", "gh-38", "gh-39"])
        game.manualScenarios.formUnion(["gh-46", "gh-47", "gh-48"])
        for id in ["across-the-divide", "through-the-trench", "redthorns-aid"] { game.gainPartyAchievement(id) }

        try win("46")
        XCTAssertTrue(scenarios.isUnlocked(try scenario("51")), "on the map…")
        XCTAssertFalse(open().contains("51"), "…but not open after one")
        try win("47")
        XCTAssertEqual(scenarios.globalAchievementCount("end-of-corruption"), 2)
        XCTAssertFalse(open().contains("51"))
        try win("48")
        XCTAssertEqual(scenarios.globalAchievementCount("end-of-corruption"), 3)
        XCTAssertTrue(open().contains("51"))

        // The count is saved with the campaign.
        let restored = GameState()
        restored.restore(from: game.toSnapshot(), editionStore: gm.editionStore)
        XCTAssertEqual(restored.globalAchievementCount("end-of-corruption"), 3)
    }

    /// A campaign begins under City Rule: Militaristic (scenario book p.1). An achievement of a
    /// type replaces the one of that type; achievements without a type stay.
    func testANewAchievementOfATypeReplacesTheOld() throws {
        gm.beginNewGame()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
        XCTAssertEqual(game.globalAchievements, ["city-rule-militaristic"])

        try alreadyWon(["11"])   // City Rule: Economic, End of the Invasion
        XCTAssertEqual(game.globalAchievements, ["city-rule-economic", "end-of-the-invasion"])
        try alreadyWon(["22"])   // Artifact: Recovered
        XCTAssertTrue(game.globalAchievements.contains("artifact-recovered"))
        try alreadyWon(["35"])   // City Rule: Demonic, Artifact: Lost
        XCTAssertEqual(game.globalAchievements, ["city-rule-demonic", "artifact-lost", "end-of-the-invasion"])
        try alreadyWon(["50"])   // City Rule: Militaristic again
        XCTAssertEqual(game.globalAchievements.filter { $0.hasPrefix("city-rule") }, ["city-rule-militaristic"])

        // Artifact: Lost closes #31, which needs Artifact: Recovered (and #27, which needs it not lost).
        game.manualScenarios.formUnion(["gh-31", "gh-27"])
        game.completedScenarios.formUnion(["gh-14", "gh-19"])
        game.gainGlobalAchievement("the-power-of-enhancement")
        game.gainPartyAchievement("stonebreakers-censer")
        XCTAssertFalse(open().contains("31"))
        XCTAssertFalse(open().contains("27"))
    }

    /// The Drake's Command with The Drake's Treasure makes The Drake Aided, with its events
    /// (GH p.49), and Scorched Summit — which needs it missing — closes.
    func testTheDrakesCommandAndTreasureAidTheDrake() throws {
        try alreadyWon(["25"])   // The Drake's Command; unlocks #33 and #34
        XCTAssertTrue(open().isSuperset(of: ["33", "34"]))
        try win("33")            // The Drake's Treasure
        XCTAssertTrue(game.globalAchievements.contains("the-drake-aided"))
        XCTAssertTrue(gm.eventCardManager.deck(.city).contains("75"))
        XCTAssertTrue(gm.eventCardManager.deck(.road).contains("66"))
        XCTAssertFalse(open().contains("34"))
    }

    /// Every achievement a scenario asks for, or takes away, is one the game can award: the
    /// data once asked for "Dept Collection" and took away "The Demmon's Errand".
    func testEveryAchievementAScenarioNamesCanBeEarned() throws {
        let store = gm.editionStore
        let all = store.scenarios(for: "gh") + store.sections(for: "gh")
        var global = Set(GameState.startingGlobalAchievements["gh"] ?? [])
        global.insert("the-drake-aided")   // from The Drake's Command and Treasure (p.49)
        var party: Set<String> = []
        for data in all {
            global.formUnion(data.rewards?.globalAchievements ?? [])
            party.formUnion(data.rewards?.partyAchievements ?? [])
        }
        func walk(_ effect: EventEffect) {
            let ids = (effect.values ?? []).compactMap(\.stringValue)
            if effect.type == "globalAchievement" { global.formUnion(ids) }
            if effect.type == "partyAchievement" { party.formUnion(ids) }
            (effect.subEffects ?? []).forEach(walk)
            (effect.condition?.effects ?? []).forEach(walk)
        }
        for card in store.events(for: "gh") {
            for outcome in (card.options ?? []).flatMap({ $0.outcomes ?? [] }) {
                (outcome.effects ?? []).forEach(walk)
                (outcome.condition?.effects ?? []).forEach(walk)
            }
        }
        for index in 1...75 {
            guard let reward = store.treasureReward(index: index, edition: "gh") else { continue }
            for part in reward.split(separator: "|") where part.hasPrefix("partyAchievement:") {
                party.insert(String(part.dropFirst("partyAchievement:".count)))
            }
        }
        XCTAssertTrue(global.count > 15 && party.count > 20, "the data was read")

        func name(_ raw: String) -> String {
            String(raw.drop { $0 == "!" }.split(separator: ":").first ?? "")
        }
        for data in all {
            for requirement in data.requirements ?? [] {
                for id in requirement.global ?? [] {
                    XCTAssertTrue(global.contains(name(id)), "#\(data.index) asks for global achievement \(id)")
                }
                for id in requirement.party ?? [] {
                    XCTAssertTrue(party.contains(name(id)), "#\(data.index) asks for party achievement \(id)")
                }
            }
            for id in data.rewards?.lostPartyAchievements ?? [] {
                XCTAssertTrue(party.contains(id), "#\(data.index) takes away party achievement \(id)")
            }
        }
        // Each has its printed name, too.
        for id in global { XCTAssertNotNil(store.resolveLabel(key: "globalAchievements.\(id)", edition: "gh"), id) }
        for id in party { XCTAssertNotNil(store.resolveLabel(key: "partyAchievements.\(id)", edition: "gh"), id) }
    }

    /// Every scenario of the campaign can be put on the map by something: it starts there, a
    /// scenario unlocks it, or an event, a treasure, a personal quest or a random draw does.
    func testEveryScenarioCanBeUnlocked() throws {
        let store = gm.editionStore
        let campaign = store.scenarios(for: "gh").filter { $0.parent == nil && $0.group == nil && $0.solo == nil }
        XCTAssertEqual(campaign.count, 95)
        var sources: Set<String> = []
        for data in campaign {
            sources.formUnion(data.unlocks ?? [])
            sources.formUnion(data.rewards?.chooseLocation ?? [])
        }
        func walk(_ effect: EventEffect) {
            if effect.type == "unlockScenario" { sources.formUnion((effect.values ?? []).map(\.stringValue)) }
            (effect.subEffects ?? []).forEach(walk)
        }
        for card in store.events(for: "gh") {
            (card.options ?? []).flatMap { $0.outcomes ?? [] }.flatMap { $0.effects ?? [] }.forEach(walk)
        }
        for index in 1...75 {
            guard let reward = store.treasureReward(index: index, edition: "gh") else { continue }
            for part in reward.split(separator: "|") where part.hasPrefix("scenario:") {
                sources.insert(String(part.dropFirst("scenario:".count)))
            }
        }
        for quest in store.personalQuests(for: "gh") {
            for requirement in quest.requirements {
                if let first = PersonalQuestEvaluator.questChain(requirement, edition: "gh", editionStore: store).first {
                    sources.insert(first.index)
                }
            }
        }
        let unreachable = campaign.filter { !$0.isInitial && $0.random != true && !sources.contains($0.index) }.map(\.index)
        // In the box these four come from sealed content the game doesn't have yet.
        XCTAssertEqual(unreachable.sorted(), ["72", "73", "76", "77"], "nothing unlocks these")
    }

    /// City event 67, refusing to pay: Debt Collection and #92 Back Alley Brawl, which asks for
    /// exactly that achievement.
    func testRefusingTheDebtCollectorsOpensTheBackAlleyBrawl() throws {
        game.events.cityDeck = ["67"] + gm.eventCardManager.deck(.city)
        XCTAssertNotNil(gm.eventCardManager.resolve(.city, option: "B"))
        XCTAssertTrue(game.partyAchievements.contains("debt-collection"))
        XCTAssertTrue(open().contains("92"))
    }

    /// #36 takes A Demon's Errand away, and #50 needs Annihilation of Order missing: #49 awards
    /// it (and closes #50 besides).
    func testTheBattlementsAndTheGhostFortressReadTheirAchievements() throws {
        try alreadyWon(["10"])
        XCTAssertTrue(game.partyAchievements.contains("a-demons-errand"))
        try alreadyWon(["36"])
        XCTAssertFalse(game.partyAchievements.contains("a-demons-errand"))

        game.manualScenarios.insert("gh-50")
        game.completedScenarios.insert("gh-35")
        game.gainGlobalAchievement("city-rule-demonic")
        XCTAssertTrue(open().contains("50"))
        game.gainGlobalAchievement("annihilation-of-order")
        XCTAssertFalse(open().contains("50"))
    }

    // MARK: - Reputation and prosperity

    /// Reputation never leaves −20…+20, whatever a scenario or an event gives; the first time
    /// it reaches an end, that end's city and road event join the decks (GH p.49).
    func testReputationStopsAtTwentyAndBringsItsEvents() throws {
        // +10 opens the box with the sun; the Sunkeeper's own events come with the class.
        game.partyReputation = 8
        XCTAssertFalse(game.unlockedCharacters.contains("gh-sun"))
        try alreadyWon(["12"])   // +4
        XCTAssertEqual(game.partyReputation, 12)
        XCTAssertTrue(game.unlockedCharacters.contains("gh-sun"))
        XCTAssertFalse(game.unlockedCharacters.contains("gh-eclipse"))
        XCTAssertFalse(gm.eventCardManager.deck(.city).contains("76"), "not before 20")

        game.partyReputation = 18
        try alreadyWon(["51"])   // +5
        XCTAssertEqual(game.partyReputation, 20)
        XCTAssertTrue(gm.eventCardManager.deck(.city).contains("76"))
        XCTAssertTrue(gm.eventCardManager.deck(.road).contains("67"))
        let cityCards = gm.eventCardManager.deck(.city).count

        // Once the card is resolved and gone, coming back to 20 doesn't bring it again.
        game.events.cityDeck?.removeAll { $0 == "76" }
        game.changeReputation(by: -1, labels: gm.editionStore)
        game.changeReputation(by: 5, labels: gm.editionStore)
        XCTAssertEqual(game.partyReputation, 20)
        XCTAssertEqual(gm.eventCardManager.deck(.city).count, cityCards - 1, "added once")

        game.partyReputation = -17
        try alreadyWon(["35"])   // −5
        XCTAssertEqual(game.partyReputation, -20)
        XCTAssertTrue(game.unlockedCharacters.contains("gh-eclipse"), "−10 was passed on the way: the box with the moon")
        XCTAssertEqual(game.unlockedItems, ["gh-113"], "each box opened once: only #12's own item design")
        XCTAssertTrue(gm.eventCardManager.deck(.city).contains("77"))
        XCTAssertTrue(gm.eventCardManager.deck(.road).contains("68"))
    }

    /// Losing prosperity never undoes a level the city has reached (FAQ): #35 takes two.
    func testLosingProsperityStopsAtTheLevelReached() throws {
        game.partyProsperity = 5   // level 2 from 4
        try alreadyWon(["35"])
        XCTAssertEqual(game.partyProsperity, 4)
        XCTAssertEqual(game.prosperityLevel, 2)

        game.partyProsperity = 12  // level 3 from 9: room to lose two
        try alreadyWon(["50"])
        XCTAssertEqual(game.partyProsperity, 10)
    }

    /// Losing checkmarks never takes back a perk (FAQ): city event 15, cleaning up yourselves.
    func testLosingACheckmarkStopsAtAPerkEarned() throws {
        let cragheart = game.characters[1]
        brute.battleGoalProgress = 3
        cragheart.battleGoalProgress = 5
        for character in game.characters { character.loot = 0 }
        game.events.cityDeck = ["15"] + gm.eventCardManager.deck(.city)
        XCTAssertNotNil(gm.eventCardManager.resolve(.city, option: "B"))
        XCTAssertEqual(brute.battleGoalProgress, 3, "three checkmarks are a perk: nothing to lose")
        XCTAssertEqual(cragheart.battleGoalProgress, 4)
        XCTAssertEqual(gm.characterManager.perksAvailable(for: brute), 1)
    }

    // MARK: - Treasure

    /// A numbered treasure is looted once in a campaign: back in the scenario, the tile gives
    /// nothing more.
    func testANumberedTreasureIsLootedOncePerCampaign() throws {
        let blackBarrow = try scenario("1")
        gm.startScenarioOnBoard(blackBarrow)
        let gold = brute.loot
        let items = brute.items.count
        XCTAssertFalse(scenarios.isTreasureLooted("7"))
        scenarios.lootTreasure("7", by: brute)   // Black Barrow's chest
        XCTAssertTrue(scenarios.isTreasureLooted("7"))
        let gained = (brute.loot - gold, brute.items.count - items)
        XCTAssertTrue(gained.0 > 0 || gained.1 > 0 || !game.manualScenarios.isEmpty || game.unlockedItems.count > 0,
                      "the chest held something")
        gm.completeScenario(success: false)

        gm.startScenarioOnBoard(blackBarrow)
        XCTAssertTrue(scenarios.isTreasureLooted("7"), "still looted on the next attempt")
        let before = (brute.loot, brute.items, game.unlockedItems, game.manualScenarios)
        scenarios.lootTreasure("7", by: brute)
        XCTAssertEqual(brute.loot, before.0)
        XCTAssertEqual(brute.items, before.1)
        XCTAssertEqual(game.unlockedItems, before.2)
        XCTAssertEqual(game.manualScenarios, before.3)
    }

    /// Treasure 49 (in #37 Doom Trench) is a map to #17 Lost Island.
    func testATreasureMapUnlocksItsScenario() throws {
        XCTAssertEqual(gm.editionStore.treasureReward(index: 49, edition: "gh"), "scenario:17")
        gm.startScenarioOnBoard(try scenario("37"))
        XCTAssertFalse(scenarios.isUnlocked(try scenario("17")))
        scenarios.lootTreasure("49", by: brute)
        XCTAssertTrue(scenarios.isUnlocked(try scenario("17")))
        gm.completeScenario(success: false)
        XCTAssertTrue(open().contains("17"))
    }

    /// Looting an item the character already owns pays what it sells for, and the copy goes to
    /// the city's supply (FAQ).
    func testADuplicateTreasureItemPaysItsSalePrice() throws {
        // Treasure 38 is item 123 (in #4 Crypt of the Damned).
        XCTAssertEqual(gm.editionStore.treasureReward(index: 38, edition: "gh"), "item:123")
        let item = try XCTUnwrap(gm.editionStore.itemData(id: 123, edition: "gh"))
        XCTAssertFalse(gm.itemManager.isItemAvailable(item))
        brute.items.append(item.itemKey)
        gm.startScenarioOnBoard(try scenario("4"))
        let gold = brute.loot
        scenarios.lootTreasure("38", by: brute)
        XCTAssertEqual(brute.loot, gold + item.cost / 2)
        XCTAssertEqual(brute.items.filter { $0 == item.itemKey }.count, 1, "never two copies")
        XCTAssertTrue(gm.itemManager.isItemAvailable(item), "the copy is in the shop")
        let cragheart = game.characters[1]
        cragheart.loot = item.cost
        XCTAssertTrue(gm.itemManager.buy(item, for: cragheart))
        XCTAssertFalse(gm.itemManager.isItemAvailable(item), "one copy came back, and it's sold")
    }

    // MARK: - Items and the city's supply

    /// A reward item isn't the city's to sell — until its owner sells it back: then that copy is
    /// on the shelves (p.47), for one buyer.
    func testAUniqueItemSoldBackIsInTheShop() throws {
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let (cragheart, tinkerer) = (game.characters[1], game.characters[2])
        try alreadyWon(["53"])   // item 114 for one character
        let item = try XCTUnwrap(gm.editionStore.itemData(id: 114, edition: "gh"))
        let owner = try XCTUnwrap(game.characters.first { $0.items.contains(item.itemKey) })
        XCTAssertFalse(gm.itemManager.isItemAvailable(item), "owned, not for sale")

        let gold = owner.loot
        XCTAssertTrue(gm.itemManager.sell(item, for: owner))
        XCTAssertEqual(owner.loot, gold + item.cost / 2)
        XCTAssertTrue(gm.itemManager.availableItems().contains(item), "sold back: in the shop")
        XCTAssertTrue(gm.itemManager.inStock(item))

        let buyers: [GameCharacter] = [cragheart, tinkerer, brute].filter { $0 !== owner }
        for buyer in buyers { buyer.loot = item.cost + 5 }
        XCTAssertTrue(gm.itemManager.buy(item, for: buyers[0]))
        XCTAssertEqual(gm.itemManager.purchaseProblem(item, for: buyers[1]), .soldOut, "the one copy is taken")
        XCTAssertFalse(gm.itemManager.availableItems().contains(item))
    }

    /// A character who retires or is dismissed leaves their items to the city (p.48).
    func testALeavingCharactersItemsReturnToTheCity() throws {
        let cragheart = game.characters[1]
        let unique = try XCTUnwrap(gm.editionStore.itemData(id: 114, edition: "gh"))
        let boots = try XCTUnwrap(gm.editionStore.itemData(id: 1, edition: "gh"))
        cragheart.items = [unique.itemKey, boots.itemKey]
        brute.items = [boots.itemKey]
        XCTAssertFalse(gm.itemManager.inStock(boots), "both pairs of boots are owned")
        XCTAssertFalse(gm.itemManager.isItemAvailable(unique))

        gm.characterManager.removeCharacter(cragheart)
        XCTAssertTrue(gm.itemManager.inStock(boots))
        XCTAssertTrue(gm.itemManager.isItemAvailable(unique), "their unique item is the city's now")
        XCTAssertTrue(gm.itemManager.inStock(unique))
    }

    // MARK: - Retirement

    private func fulfil(_ quest: String, for character: GameCharacter) throws {
        let data = try XCTUnwrap(gm.editionStore.personalQuest(cardId: quest, edition: "gh"))
        character.personalQuest = quest
        character.personalQuestProgress = data.requirements.map(\.counterValue)
    }

    /// Only a character whose personal quest is fulfilled retires (p.48).
    func testOnlyAFulfilledQuestRetires() throws {
        brute.personalQuest = "512"   // Greed is Good: 200 gold
        brute.personalQuestProgress = [150]
        let prosperity = game.partyProsperity
        XCTAssertFalse(gm.characterManager.retireCharacter(brute))
        XCTAssertEqual(game.characters.count, 2)
        XCTAssertEqual(game.partyProsperity, prosperity)
        XCTAssertTrue(game.retiredCharacters.isEmpty)

        brute.personalQuestProgress = [200]
        XCTAssertTrue(gm.characterManager.retireCharacter(brute))
        XCTAssertEqual(game.characters.map(\.name), ["cragheart"])
        XCTAssertEqual(game.partyProsperity, prosperity + 1)
    }

    /// Each retirement gives the player's later characters one more perk (p.48). The game has
    /// seats, not players: the next recruit takes the retired character's seat, and a second
    /// retirement from that seat makes it two.
    func testARetirementGivesTheNextCharacterAnExtraPerk() throws {
        let characters = gm.characterManager
        XCTAssertEqual(characters.perksAvailable(for: brute), 0)
        try fulfil("512", for: brute)
        XCTAssertTrue(characters.retireCharacter(brute))
        XCTAssertEqual(characters.perksAvailable(for: game.characters[0]), 0, "not for the others in the party")

        characters.addCharacter(name: "tinkerer", edition: "gh")
        let tinkerer = try XCTUnwrap(game.characters.first { $0.name == "tinkerer" })
        XCTAssertEqual(characters.perksAvailable(for: tinkerer), 1)
        XCTAssertTrue(characters.takePerk(at: 0, for: tinkerer))
        XCTAssertEqual(characters.perksAvailable(for: tinkerer), 0)

        characters.addCharacter(name: "spellweaver", edition: "gh")
        let spellweaver = try XCTUnwrap(game.characters.first { $0.name == "spellweaver" })
        XCTAssertEqual(characters.perksAvailable(for: spellweaver), 0, "one retirement, one character with the perk")

        // It is saved with the character, and the tinkerer's own retirement makes it two.
        let restored = GameState()
        restored.restore(from: game.toSnapshot(), editionStore: gm.editionStore)
        XCTAssertEqual(restored.characters.first { $0.name == "tinkerer" }?.record.extraPerks, 1)
        try fulfil("512", for: tinkerer)
        XCTAssertTrue(characters.retireCharacter(tinkerer))
        characters.addCharacter(name: "scoundrel", edition: "gh")
        let scoundrel = try XCTUnwrap(game.characters.first { $0.name == "scoundrel" })
        XCTAssertEqual(characters.perksAvailable(for: scoundrel), 2)
    }

    /// Retiring with a quest whose class is already unlocked brings a random item design and a
    /// random side scenario instead (p.48, FAQ) — and so does a scenario that would unlock it.
    func testAnAlreadyUnlockedClassBringsADesignAndAScenario() throws {
        try fulfil("515", for: brute)   // Law Bringer: the Sunkeeper
        XCTAssertTrue(gm.characterManager.retireCharacter(brute))
        XCTAssertTrue(game.unlockedCharacters.contains("gh-sun"))
        XCTAssertTrue(game.unlockedItems.isEmpty && game.manualScenarios.isEmpty, "the first time, the class")

        let cragheart = game.characters[0]
        try fulfil("520", for: cragheart)   // Implement of Light: the Sunkeeper again
        XCTAssertTrue(gm.characterManager.retireCharacter(cragheart))
        XCTAssertEqual(game.unlockedItems.count, 1)
        let design = try XCTUnwrap(game.unlockedItems.first.flatMap { gm.editionStore.itemData(key: $0) })
        XCTAssertTrue(design.random, "a random item design")
        XCTAssertEqual(game.manualScenarios.count, 1)
        let side = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { game.manualScenarios.contains($0.id) && $0.solo == nil })
        XCTAssertEqual(side.random, true, "a random side scenario")
        let note = try XCTUnwrap(game.campaignLog.last { $0.message.contains("already unlocked") })
        XCTAssertEqual(note.message, "Sunkeeper was already unlocked: item design \(design.name) and scenario #\(side.index) \(side.name) instead")
        XCTAssertEqual(PlayerTextTests.lint(note.message), [])
    }

    /// A fulfilled quest's card leaves the game (p.48): it is never dealt to a later recruit.
    func testARetiredCharactersQuestIsNeverDealtAgain() throws {
        try fulfil("512", for: brute)
        XCTAssertTrue(gm.characterManager.retireCharacter(brute))
        let cragheart = game.characters[0]
        var dealt: Set<String> = []
        for _ in 0..<200 {
            gm.characterManager.dealQuests(to: cragheart)
            XCTAssertEqual(cragheart.questChoices.count, 2)
            dealt.formUnion(cragheart.questChoices)
        }
        XCTAssertFalse(dealt.contains("512"))
        XCTAssertEqual(dealt.count, gm.editionStore.personalQuests(for: "gh").count - 1, "every other quest comes up")
    }

    // MARK: - Personal quests

    /// Seeker of Xorn (510): the third Crypt puts #52 Noxious Cellar on the map at once (FAQ),
    /// and the quest is done when the chain it starts — #52, #53, #54 — is won to its end.
    func testAQuestUnlocksItsScenarioAndEndsWithTheChain() throws {
        let cragheart = game.characters[1]
        gm.characterManager.chooseQuest("510", for: {
            cragheart.questChoices = ["510", "511"]
            return cragheart
        }())
        XCTAssertEqual(cragheart.personalQuest, "510")

        try win("1"); try win("2"); try win("4"); try win("5")
        XCTAssertFalse(scenarios.isUnlocked(try scenario("52")), "two Crypts so far")
        try win("6")
        XCTAssertEqual(cragheart.personalQuestProgress, [3, 0])
        XCTAssertTrue(open().contains("52"), "unlocked the moment the third Crypt is won")

        try win("52")
        XCTAssertEqual(cragheart.personalQuestProgress, [3, 0], "Noxious Cellar is where the chain starts")
        XCTAssertFalse(gm.characterManager.questComplete(cragheart))
        try win("53")
        XCTAssertFalse(gm.characterManager.questComplete(cragheart))
        XCTAssertTrue(game.characters.contains { $0 === cragheart })

        // #54 Palace of Ice ends it: the Seeker of Xorn retires on the spot.
        try win("54")
        XCTAssertFalse(game.characters.contains { $0 === cragheart })
        XCTAssertEqual(game.retiredCharacters.map(\.name), ["cragheart"])
        XCTAssertTrue(game.unlockedCharacters.contains("gh-squidface"))
        XCTAssertEqual(game.manualScenarios, ["gh-52"], "the box is opened once: no random scenario for a second opening")
        XCTAssertTrue(game.campaignLog.contains { $0.message == "Cragheart\u{2019}s quest leads to #52 Noxious Cellar" })
        for entry in game.campaignLog { XCTAssertEqual(PlayerTextTests.lint(entry.message), [], entry.message) }
        XCTAssertTrue(game.unlockedItems.isEmpty)
    }

    /// A quest counted by hand unlocks its scenario too, as the last mark is made: Take Back
    /// the Trees (521) and #55 Foggy Thicket.
    func testAQuestCountedByHandUnlocksItsScenario() throws {
        brute.questChoices = ["521", "511"]
        gm.characterManager.chooseQuest("521", for: brute)
        gm.characterManager.adjustQuest(0, by: 2, for: brute)
        XCTAssertFalse(scenarios.isUnlocked(try scenario("55")))
        gm.characterManager.adjustQuest(0, by: 1, for: brute)
        XCTAssertTrue(open().contains("55"))
        XCTAssertFalse(gm.characterManager.questComplete(brute))
        try win("55")
        XCTAssertFalse(gm.characterManager.questComplete(brute), "Bandit's Wood is still to come")
        try win("56")
        XCTAssertTrue(gm.characterManager.questComplete(brute))
    }

    /// A Study of Anatomy (514) counts the other characters' exhaustions, not the holder's own
    /// (FAQ).
    func testAStudyOfAnatomyCountsOnlyTheOthers() throws {
        let cragheart = game.characters[1]
        brute.questChoices = ["514", "511"]
        gm.characterManager.chooseQuest("514", for: brute)
        gm.startScenarioOnBoard(try scenario("1"))
        brute.exhausted = true
        gm.completeScenario(success: false)
        XCTAssertEqual(brute.personalQuestProgress, [0], "their own exhaustion doesn't count")
        XCTAssertEqual(brute.record.timesExhausted, 1)

        gm.startScenarioOnBoard(try scenario("1"))
        brute.exhausted = true
        cragheart.exhausted = true
        gm.completeScenario(success: false)
        XCTAssertEqual(brute.personalQuestProgress, [1])
    }

    /// Battle Legend (519) counts checkmarks from battle goals only (FAQ): one from a treasure
    /// or an event isn't progress, and one lost to an event doesn't undo any.
    func testBattleLegendCountsOnlyBattleGoals() throws {
        brute.questChoices = ["519", "511"]
        gm.characterManager.chooseQuest("519", for: brute)
        gm.startScenarioOnBoard(try scenario("1"))
        scenarios.lootTreasure("8", by: brute)   // treasure 8: a checkmark
        brute.battleGoalCardIds = ["460", "470"]   // Workhorse: 13 or more experience
        gm.scenarioManager.chooseBattleGoal(0, for: brute)
        brute.experience += 13
        gm.completeScenario(success: true)
        XCTAssertEqual(brute.battleGoalProgress, 2, "one from the chest, one from the goal")
        XCTAssertEqual(brute.personalQuestProgress, [1], "only the goal counts")

        for character in game.characters { character.loot = 0 }
        game.events.cityDeck = ["15"] + gm.eventCardManager.deck(.city)
        XCTAssertNotNil(gm.eventCardManager.resolve(.city, option: "B"))   // each loses a checkmark
        XCTAssertEqual(brute.battleGoalProgress, 1)
        PersonalQuestEvaluator.updateProgress(character: brute, game: game, editionStore: gm.editionStore)
        XCTAssertEqual(brute.personalQuestProgress, [1], "a lost checkmark isn't lost progress")
    }

    /// A Helping Hand (532) counts retirements the character is in the party for, not those
    /// from before they joined.
    func testAHelpingHandCountsRetirementsWhileInTheParty() throws {
        try fulfil("512", for: brute)
        XCTAssertTrue(gm.characterManager.retireCharacter(brute))

        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let tinkerer = try XCTUnwrap(game.characters.first { $0.name == "tinkerer" })
        tinkerer.questChoices = ["532", "511"]
        gm.characterManager.chooseQuest("532", for: tinkerer)
        PersonalQuestEvaluator.updateProgress(character: tinkerer, game: game, editionStore: gm.editionStore)
        XCTAssertEqual(tinkerer.personalQuestProgress, [0], "the brute retired before the tinkerer came")

        let cragheart = try XCTUnwrap(game.characters.first { $0.name == "cragheart" })
        try fulfil("518", for: cragheart)
        XCTAssertTrue(gm.characterManager.retireCharacter(cragheart))
        XCTAssertEqual(tinkerer.personalQuestProgress, [1])
    }
}
