import XCTest
@testable import GlavenGameLib

/// The city's supply holds prosperity items up to the prosperity level plus unlocked items;
/// scenario-reward and treasure items (no prosperity level) are not for sale from the start.
@MainActor
final class ItemSupplyTests: XCTestCase {

    func testRewardItemsAreNotInTheStartingSupply() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        let available = Set(gm.itemManager.availableItems().map(\.id))

        XCTAssertEqual(available, Set(1...14), "prosperity 1 offers items 1–14 only")
        XCTAssertFalse(gm.editionStore.availableItems(for: "gh", prosperity: 9).contains { $0.id >= 71 },
                       "no reward, treasure or random item is bought by prosperity alone")
    }

    func testProsperityLevelUnlocksItems() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.game.partyProsperity = 9  // level 3
        XCTAssertEqual(gm.game.prosperityLevel, 3)
        let available = Set(gm.itemManager.availableItems().map(\.id))
        XCTAssertTrue(available.isSuperset(of: Set(1...28)))
        XCTAssertFalse(available.contains(29), "prosperity 4 items stay locked")
    }

    /// A random item design puts every copy of the item in the shop (p.43), and is never
    /// drawn again; a treasure draws one for real.
    func testDrawnRandomItemDesignIsForSale() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarioData(index: "2", edition: "gh"))
        gm.startScenarioOnBoard(scenario)
        XCTAssertEqual(gm.editionStore.treasureReward(index: 1, edition: "gh"), "randomItemDesign")
        gm.scenarioManager.lootTreasure("1", by: gm.game.characters[0])
        let key = try XCTUnwrap(gm.game.unlockedItems.first)
        let drawn = try XCTUnwrap(gm.editionStore.itemData(key: key))
        XCTAssertTrue(drawn.random, "from the random item designs")
        XCTAssertTrue(gm.itemManager.availableItems().contains(drawn), "a random item design joins the supply")
        XCTAssertTrue(gm.game.characters.allSatisfy { !$0.items.contains(key) }, "a design, not an item in hand")

        // Every copy is for sale, at its price.
        for character in gm.game.characters.prefix(drawn.count) {
            character.loot = gm.itemManager.price(drawn)
            XCTAssertTrue(gm.itemManager.buy(drawn, for: character))
        }
        XCTAssertFalse(gm.itemManager.inStock(drawn) && drawn.count <= 2)

        // The design is out of the deck: every other draw is a different one.
        var seen: Set<Int> = [drawn.id]
        while let next = gm.itemManager.drawAndUnlockRandomItem() {
            XCTAssertTrue(seen.insert(next.id).inserted, "\(next.name) drawn twice")
        }
        XCTAssertEqual(seen.count, gm.editionStore.items(for: "gh").filter(\.random).count, "until the deck is empty")
    }

    func testProsperityLevelThresholds() {
        let game = GameState()
        for (checks, level) in [(-2, 1), (0, 1), (3, 1), (4, 2), (8, 2), (9, 3), (38, 6), (39, 7), (49, 7), (50, 8), (63, 8), (64, 9), (80, 9)] {
            game.partyProsperity = checks
            XCTAssertEqual(game.prosperityLevel, level, "\(checks) prosperity")
        }
    }
}
