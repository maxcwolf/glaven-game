import XCTest
@testable import GlavenGameLib

// MARK: - Persistent Ability Tracking Tests

/// Verifies that persistent ability cards are routed to the active area
/// instead of discard/lost, and returned to hand between scenarios.
/// Rulebook p.25: "Some abilities have the persistent icon... These cards
/// are placed in the active area and remain there until the card is consumed."
final class PersistentAbilityTests: XCTestCase {

    // A card going to the active area when its persistent half is performed, and staying out of
    // it otherwise, is played for real in TurnFlowTests.testAPerformedPersistentHalfStaysActive and
    // ActionPerformedTests.testACardInPlayGivesOnlyTheBonusOfItsHalf.

    // MARK: - E2E: Scenario Cleanup Returns Active Cards

    func testScenarioFinish_returnsActiveCardsToHand() {
        let t = TestGame()
        let char = t.addCharacter()
        char.handCards = [1, 2, 3]
        char.discardedCards = [4, 5]
        char.activeCards = [6, 7]  // Two persistent cards in active area
        char.lostCards = [8]

        let scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: true)

        // Active cards should be returned to hand (like discard)
        XCTAssertTrue(char.activeCards.isEmpty, "Active area cleared after scenario")
        XCTAssertTrue(char.handCards.contains(6), "Active card 6 returned to hand")
        XCTAssertTrue(char.handCards.contains(7), "Active card 7 returned to hand")
        // Discard also returned
        XCTAssertTrue(char.handCards.contains(4), "Discarded card returned to hand")
        XCTAssertTrue(char.handCards.contains(5), "Discarded card returned to hand")
        // GH p.47: lost cards are recovered too
        XCTAssertTrue(char.lostCards.isEmpty, "Lost pile emptied after scenario")
        XCTAssertTrue(char.handCards.contains(8), "Lost card recovered to hand")
    }

    func testScenarioDefeat_returnsActiveCardsToHand() {
        let t = TestGame()
        let char = t.addCharacter()
        char.handCards = [1, 2]
        char.activeCards = [10, 11]

        let scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: false)

        XCTAssertTrue(char.activeCards.isEmpty, "Active area cleared after defeat too")
        XCTAssertTrue(char.handCards.contains(10))
        XCTAssertTrue(char.handCards.contains(11))
    }

    // Cards in the active area counting neither as hand nor as discard when cards are chosen:
    // RoundRuleTests.testACharacterWithOnlyActiveCardsIsExhaustedAtCardSelection.

    // MARK: - Snapshot Tests

    func testSnapshot_preservesActiveCards() throws {
        // Create a character, set active cards, snapshot, and verify
        let char = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: nil)
        char.handCards = [1, 2, 3]
        char.activeCards = [6, 7]

        let snapshot = char.toSnapshot()
        XCTAssertEqual(snapshot.activeCards, [6, 7], "Snapshot should preserve active cards")
        // …and through a save: encoded and read back, they are still in play.
        let reloaded = try JSONDecoder().decode(CharacterSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(reloaded.activeCards, [6, 7])
        XCTAssertEqual(reloaded.handCards, [1, 2, 3])
    }

    func testSnapshot_decodesWithoutActiveCards_defaultsEmpty() throws {
        // Backward compatibility: old snapshots won't have activeCards
        let json = """
        {
            "name": "brute", "edition": "gh", "level": 1,
            "off": false, "active": false, "number": 1,
            "health": 10, "maxHealth": 10,
            "entityConditions": [], "immunities": [],
            "markers": [], "tags": [],
            "retaliate": [], "retaliatePersistent": [],
            "handCards": [1, 2], "discardedCards": [3], "lostCards": [4],
            "resources": {}, "enhancements": [],
            "initiative": 0, "experience": 0, "loot": 0,
            "lootCards": [], "exhausted": false, "absent": false,
            "longRest": false, "identity": 0, "token": 0,
            "tokenValues": [], "selectedPerks": [],
            "battleGoalCardIds": [], "items": [],
            "notes": "", "battleGoalProgress": 0,
            "personalQuestProgress": [], "retired": false,
            "title": "",
            "attackModifierDeck": {
                "attackModifiers": [], "cards": [], "current": -1,
                "discards": [], "active": true
            },
            "summons": []
        }
        """
        let data = json.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(CharacterSnapshot.self, from: data)
        XCTAssertEqual(snapshot.activeCards, [], "Missing activeCards defaults to empty")
        XCTAssertEqual(snapshot.handCards, [1, 2])
    }
}
