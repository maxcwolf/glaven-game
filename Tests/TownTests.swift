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

    // MARK: - Layout

    /// Regression: the parchment background sized the town wider than the screen, pushing the
    /// Campaign button off the edge, and the header floated over the panels.
    func testTheTownFitsTheScreen() throws {
        let gm = try party(["brute", "tinkerer", "spellweaver", "cragheart"])
        gm.game.completedScenarios.insert("gh-1")
        gm.game.events.cityEventDue = true   // every header button showing
        for screen in [CGSize(width: 1376, height: 988), CGSize(width: 1133, height: 700)] {
            let size = NSHostingController(rootView: GameSetupView().environment(gm)).sizeThatFits(in: screen)
            XCTAssertLessThanOrEqual(size.width, screen.width + 0.5, "\(screen)")
            XCTAssertLessThanOrEqual(size.height, screen.height + 0.5, "\(screen)")
        }
    }

    // MARK: - Sanctuary

    func testADonationBlessesTheNextScenarioOncePerVisit() throws {
        let gm = try party(["brute", "tinkerer"])
        let (brute, manager) = (gm.game.characters[0], gm.characterManager)
        brute.loot = 25
        XCTAssertTrue(manager.donate(brute))
        XCTAssertEqual(brute.loot, 15)
        XCTAssertFalse(manager.donate(brute), "once per visit")
        gm.game.characters[1].loot = 9
        XCTAssertFalse(manager.donate(gm.game.characters[1]), "10 gold needed")

        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        let blessings = brute.attackModifierDeck.undrawnCount(of: .bless)
        gm.startScenarioOnBoard(scenario)
        XCTAssertEqual(brute.attackModifierDeck.undrawnCount(of: .bless), blessings + 2)
        XCTAssertTrue(gm.game.events.donatedThisVisit.isEmpty, "a new visit after the scenario")
        XCTAssertTrue(gm.game.events.nextScenario.isEmpty)
    }

    func testEveryHundredGoldRaisesProsperityAndCountsForPiety() throws {
        let gm = try party(["brute"])
        let brute = gm.game.characters[0]
        brute.personalQuest = "525"   // Piety in All Things: 120 gold donated
        brute.loot = 1000
        let prosperity = gm.game.partyProsperity
        for _ in 0..<10 {
            XCTAssertTrue(gm.characterManager.donate(brute))
            gm.game.events.donatedThisVisit = []   // as if back in town again
        }
        XCTAssertEqual(gm.game.partyProsperity, prosperity + 1)
        PersonalQuestEvaluator.updateProgress(character: brute, game: gm.game, editionStore: gm.editionStore)
        XCTAssertEqual(brute.personalQuestProgress.first, 100)
    }

    /// Saves from before a field existed must still load: a missing field takes its default.
    func testSavedTownStateLoadsWithMissingFields() throws {
        let empty = Data("{}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(EventState.self, from: empty), EventState())
        XCTAssertEqual(try JSONDecoder().decode(ScenarioStartEffects.self, from: empty), ScenarioStartEffects())
        XCTAssertEqual(try JSONDecoder().decode(CharacterRecord.self, from: empty), CharacterRecord())
        XCTAssertEqual(try JSONDecoder().decode(ScenarioCharacterStats.self, from: empty), ScenarioCharacterStats())
        XCTAssertEqual(try JSONDecoder().decode(ScenarioPartyStats.self, from: empty), ScenarioPartyStats())
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

    /// Reputation changes every shop price (p.48): −1 at +3 … −5 at +19, and the reverse below
    /// −3. Selling still pays half the printed price.
    func testReputationChangesShopPrices() throws {
        let table: [(Int, Int)] = [(0, 0), (2, 0), (3, -1), (6, -1), (7, -2), (10, -2), (11, -3), (14, -3),
                                   (15, -4), (18, -4), (19, -5), (20, -5), (-2, 0), (-3, 1), (-6, 1),
                                   (-7, 2), (-11, 3), (-15, 4), (-19, 5), (-20, 5)]
        for (reputation, modifier) in table {
            XCTAssertEqual(ItemManager.reputationPriceModifier(reputation), modifier, "reputation \(reputation)")
        }

        let gm = try party(["brute"])
        let shop = gm.itemManager
        let brute = gm.game.characters[0]
        let item = try XCTUnwrap(shop.availableItems().filter { $0.cost >= 20 }.min { $0.cost < $1.cost })

        gm.game.partyReputation = 20
        XCTAssertEqual(shop.price(item), item.cost - 5)
        brute.loot = item.cost - 5
        XCTAssertTrue(shop.buy(item, for: brute), "affordable with the discount")
        XCTAssertEqual(brute.loot, 0)
        XCTAssertTrue(shop.sell(item, for: brute))
        XCTAssertEqual(brute.loot, item.cost / 2, "selling pays half the printed price")

        gm.game.partyReputation = -20
        brute.loot = item.cost
        XCTAssertEqual(shop.purchaseProblem(item, for: brute), .tooExpensive, "5 gold more at −20")
        brute.loot = item.cost + 5
        XCTAssertTrue(shop.buy(item, for: brute))
        XCTAssertEqual(brute.loot, 0)
    }
}

extension TownTests {
    /// A new character starts with their level's experience and 15 × (level + 1) gold, at a level
    /// no higher than the prosperity level (p.45).
    func testARecruitStartsWithGoldAndExperience() throws {
        let gm = try party(["brute"])
        let brute = gm.game.characters[0]
        XCTAssertEqual(brute.loot, 30)
        XCTAssertEqual(brute.experience, 0)

        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh", level: 3)
        let tinkerer = try XCTUnwrap(gm.game.characters.first { $0.name == "tinkerer" })
        XCTAssertEqual(tinkerer.loot, 60)
        XCTAssertEqual(tinkerer.experience, 95)
        XCTAssertEqual(tinkerer.level, 3)

        XCTAssertEqual(gm.characterManager.highestStartingLevel, 1, "a new city: level 1 only")
        gm.game.partyProsperity = 9
        XCTAssertEqual(gm.characterManager.highestStartingLevel, 3)
    }

    /// In town, tapping a party member in the recruit list asks before they leave for good.
    func testDismissingAVeteranAsksFirst() {
        XCTAssertEqual(GameSetupView.recruitTap(isAdded: false, inTown: true), .add)
        XCTAssertEqual(GameSetupView.recruitTap(isAdded: true, inTown: false), .remove)
        XCTAssertEqual(GameSetupView.recruitTap(isAdded: true, inTown: true), .confirmDismissal)
    }

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

    /// Set Out says what it leads to, or what's missing first.
    func testSetOutSaysWhatComesNext() {
        XCTAssertEqual(GameSetupView.setOutDetail(hasParty: false, scenario: true, cityEvent: false, roadEvent: false),
                       "Recruit your party first")
        XCTAssertEqual(GameSetupView.setOutDetail(hasParty: true, scenario: false, cityEvent: false, roadEvent: false),
                       "Choose a scenario first")
        XCTAssertEqual(GameSetupView.setOutDetail(hasParty: true, scenario: true, cityEvent: false, roadEvent: false),
                       "Battle goals, then the board")
        XCTAssertEqual(GameSetupView.setOutDetail(hasParty: true, scenario: true, cityEvent: false, roadEvent: true),
                       "Road event, then battle goals")
        XCTAssertEqual(GameSetupView.setOutDetail(hasParty: true, scenario: true, cityEvent: true, roadEvent: true),
                       "City event, road event, then battle goals")
        XCTAssertEqual(GameSetupView.townSubtitle(scenariosPlayed: 0), "Recruit your party and set out")
        XCTAssertEqual(GameSetupView.townSubtitle(scenariosPlayed: 1), "In town \u{00B7} 1 scenario played")
        XCTAssertEqual(GameSetupView.townSubtitle(scenariosPlayed: 3), "In town \u{00B7} 3 scenarios played")
    }

    /// The banner crops the world map around the scenario, kept inside the map at its edges.
    func testTheScenarioBannerShowsTheMapAroundTheScenario() throws {
        let rect = CGRect(x: 1572, y: 967, width: 187, height: 131)
        let crop = try XCTUnwrap(ImageLoader.worldMapCrop(edition: "gh", around: rect, size: ScenarioBanner.cropSize))
        XCTAssertEqual(crop.size.width, ScenarioBanner.cropSize.width, accuracy: 1)
        XCTAssertEqual(crop.size.height, ScenarioBanner.cropSize.height, accuracy: 1)
        let corner = try XCTUnwrap(ImageLoader.worldMapCrop(edition: "gh", around: CGRect(x: 0, y: 0, width: 10, height: 10),
                                                             size: ScenarioBanner.cropSize))
        XCTAssertEqual(corner.size.width, ScenarioBanner.cropSize.width, accuracy: 1, "slid back inside at the edge")
    }
}
