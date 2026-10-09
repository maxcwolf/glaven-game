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

    func testDrawnRandomItemDesignIsForSale() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        let drawn = try XCTUnwrap(gm.itemManager.drawAndUnlockRandomItem())
        XCTAssertTrue(gm.itemManager.isItemAvailable(drawn), "a random item design joins the supply")
    }

    func testProsperityLevelThresholds() {
        let game = GameState()
        for (checks, level) in [(-2, 1), (0, 1), (3, 1), (4, 2), (8, 2), (9, 3), (38, 6), (39, 7), (49, 7), (50, 8), (63, 8), (64, 9), (80, 9)] {
            game.partyProsperity = checks
            XCTAssertEqual(game.prosperityLevel, level, "\(checks) prosperity")
        }
    }
}
