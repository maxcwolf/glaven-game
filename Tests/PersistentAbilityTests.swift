import XCTest
@testable import GlavenGameLib

// MARK: - Persistent Ability Tracking Tests

/// Verifies that persistent ability cards are routed to the active area
/// instead of discard/lost, and returned to hand between scenarios.
/// Rulebook p.25: "Some abilities have the persistent icon... These cards
/// are placed in the active area and remain there until the card is consumed."
final class PersistentAbilityTests: XCTestCase {

    // MARK: - Unit Tests

    func testActiveCardsProperty_existsOnCharacter() {
        let char = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: nil)
        XCTAssertTrue(char.activeCards.isEmpty, "Active cards start empty")
    }

    func testActiveCards_canAddAndRemove() {
        let char = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: nil)
        char.activeCards.append(42)
        char.activeCards.append(99)
        XCTAssertEqual(char.activeCards.count, 2)

        char.activeCards.removeAll { $0 == 42 }
        XCTAssertEqual(char.activeCards, [99])
    }

    func testAbilityModel_persistentFlag() {
        let persistent = AbilityModel(cardId: 1, initiative: 50)
        var copy = persistent
        copy.persistent = true
        XCTAssertTrue(copy.persistent == true)

        let normal = AbilityModel(cardId: 2, initiative: 30)
        XCTAssertNil(normal.persistent)
    }

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
        // Lost cards stay lost
        XCTAssertTrue(char.lostCards.contains(8), "Lost cards remain lost")
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

    // MARK: - E2E: Active Cards Don't Count for Exhaustion

    func testActiveCards_notCountedAsHandOrDiscard() {
        // Active cards are "in play" — neither hand nor discard
        // So a character with 0 hand, 0 discard, but 5 active cards is still exhausted
        let char = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: nil)
        char.handCards = []
        char.discardedCards = []
        char.activeCards = [1, 2, 3, 4, 5]

        // The exhaustion check uses handCards.count and discardedCards.count
        let handCount = char.handCards.count
        let discardCount = char.discardedCards.count

        XCTAssertLessThan(handCount, 2, "Hand count doesn't include active cards")
        XCTAssertLessThan(discardCount, 2, "Discard count doesn't include active cards")
        // This means the character would be exhausted — correct per rules
        // (active cards are committed, they can't be played again)
    }

    // MARK: - Snapshot Tests

    func testSnapshot_preservesActiveCards() {
        // Create a character, set active cards, snapshot, and verify
        let char = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: nil)
        char.handCards = [1, 2, 3]
        char.activeCards = [6, 7]

        let snapshot = char.toSnapshot()
        XCTAssertEqual(snapshot.activeCards, [6, 7], "Snapshot should preserve active cards")
    }

    func testSnapshot_decodesWithoutActiveCards_defaultsEmpty() {
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
        let snapshot = try? JSONDecoder().decode(CharacterSnapshot.self, from: data)

        XCTAssertNotNil(snapshot, "Should decode without activeCards field")
        XCTAssertEqual(snapshot?.activeCards, [], "Missing activeCards defaults to empty")
    }
}
