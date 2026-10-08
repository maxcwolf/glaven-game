import XCTest
import SwiftUI
@testable import GlavenGameLib

/// Between scenarios the party is in town: levels are earned, perks are limited to those
/// earned, and the shop sells only what it has.
@MainActor
final class TownTests: XCTestCase {

    private func party(_ names: [String]) throws -> GameManager {
        let gm = try SaveAndContinueTestsSupport.manager()
        for name in names { gm.characterManager.addCharacter(name: name, edition: "gh") }
        return gm
    }

    // MARK: - Levels

    func testALevelIsTakenOnlyWithTheExperienceForIt() throws {
        let gm = try party(["brute"])
        let brute = gm.game.characters[0]
        let manager = gm.characterManager
        XCTAssertFalse(manager.canLevelUp(brute))
        XCTAssertFalse(manager.levelUp(brute))

        brute.experience = 45
        let hpBefore = brute.maxHealth
        XCTAssertTrue(manager.canLevelUp(brute))
        XCTAssertTrue(manager.levelUp(brute))
        XCTAssertEqual(brute.level, 2)
        XCTAssertGreaterThan(brute.maxHealth, hpBefore, "more hit points")
        XCTAssertEqual(brute.health, brute.maxHealth)
        XCTAssertFalse(manager.canLevelUp(brute), "one level per threshold")
    }

    // MARK: - Perks

    /// One perk per level after the first and one per three battle-goal checkmarks (p.44, 46).
    func testPerksAreLimitedToThoseEarned() throws {
        let gm = try party(["brute"])
        let brute = gm.game.characters[0]
        let manager = gm.characterManager
        XCTAssertEqual(manager.perksAvailable(for: brute), 0)
        manager.togglePerk(at: 0, for: brute)
        XCTAssertEqual(brute.selectedPerks.reduce(0, +), 0, "a level 1 character with no checkmarks has no perk to take")

        brute.experience = 45
        manager.levelUp(brute)
        brute.battleGoalProgress = 3
        XCTAssertEqual(manager.perksAvailable(for: brute), 2)
        manager.togglePerk(at: 0, for: brute)
        manager.togglePerk(at: 1, for: brute)
        XCTAssertEqual(manager.perksAvailable(for: brute), 0)
        let taken = brute.selectedPerks
        manager.togglePerk(at: 2, for: brute)
        XCTAssertEqual(brute.selectedPerks.reduce(0, +), 2, "no third perk: \(taken) → \(brute.selectedPerks)")
    }

    // MARK: - Shop

    func testTheShopSellsWhatItHasForWhatItCosts() throws {
        let gm = try party(["brute", "tinkerer", "spellweaver"])
        let shop = gm.itemManager
        let item = try XCTUnwrap(shop.availableItems().filter { $0.count == 2 && $0.cost > 1 }.min { $0.cost < $1.cost })
        let (a, b, c) = (gm.game.characters[0], gm.game.characters[1], gm.game.characters[2])
        for character in [a, b, c] { character.loot = item.cost }

        XCTAssertTrue(shop.buy(item, for: a))
        XCTAssertEqual(a.loot, 0)
        XCTAssertEqual(shop.purchaseProblem(item, for: a), .alreadyOwned)
        a.loot = item.cost
        XCTAssertFalse(shop.buy(item, for: a), "one copy each")

        XCTAssertTrue(shop.buy(item, for: b))
        XCTAssertEqual(shop.purchaseProblem(item, for: c), .soldOut, "both copies are owned")
        XCTAssertFalse(shop.buy(item, for: c))

        XCTAssertTrue(shop.sell(item, for: b))
        XCTAssertEqual(b.loot, item.cost / 2, "half price, rounded down")
        c.loot = item.cost - 1
        XCTAssertEqual(shop.purchaseProblem(item, for: c), .tooExpensive)
    }
}

extension TownTests {
    /// `TOWN_RENDER_OUT=/tmp/town.png swift test --filter testRenderTown` renders the town.
    func testRenderTown() throws {
        guard let out = ProcessInfo.processInfo.environment["TOWN_RENDER_OUT"] else {
            throw XCTSkip("set TOWN_RENDER_OUT to render the town")
        }
        GlavenFont.registerFonts()
        let gm = try party(["brute", "tinkerer"])
        gm.game.completedScenarios.insert("gh-1")
        gm.game.characters[0].experience = 52
        gm.game.characters[0].loot = 23
        gm.game.characters[1].experience = 18
        gm.game.characters[1].loot = 9
        let renderer = ImageRenderer(content: GameSetupView().environment(gm).frame(width: 1376, height: 1032))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }
}
