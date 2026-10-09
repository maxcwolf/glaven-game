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

    // MARK: - Open scenarios

    /// The town's scenario list (iPad playthrough 2026-10-09): a scenario an event unlocked
    /// (road event 24: #82 Burning Mountain) is open, and a won #1 Black Barrow isn't, though
    /// it's where the campaign starts.
    func testTheOpenScenariosFollowTheCampaign() throws {
        let gm = try party(["cragheart"])
        func open() -> [String] { gm.scenarioManager.availableScenarios(for: "gh").map(\.index) }
        XCTAssertEqual(open(), ["1"])
        gm.game.completedScenarios.insert("gh-1")
        gm.game.partyAchievements.insert("first-steps")
        gm.game.manualScenarios.insert("gh-82")
        XCTAssertFalse(open().contains("1"), "a won scenario isn't open again")
        XCTAssertTrue(open().contains("2"))
        XCTAssertTrue(open().contains("82"), "an event's scenario is open")
    }

    /// A new party stays a "New Campaign" while it recruits and shops; it's in town once a
    /// scenario has been played, won or lost.
    func testANewPartyIsInTownOnlyAfterAScenario() throws {
        let gm = try party(["cragheart", "spellweaver"])
        XCTAssertFalse(gm.game.campaignLog.isEmpty, "joining is logged")
        XCTAssertFalse(GameSetupView.isInTown(gm.game))
        gm.game.campaignLog.append(CampaignLogEntry(type: .scenarioFailed, message: "Failed #1 Black Barrow"))
        XCTAssertTrue(GameSetupView.isInTown(gm.game))
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

    /// Regression: in the narrower party panel (11-inch iPad), "No personal quest" wrapped onto
    /// two lines beside Choose Quest. The line fits the row's 290 points with room to spare
    /// (iPad sets text a little wider than the Mac).
    func testTheQuestLineFitsTheNarrowPanel() throws {
        let gm = try party(["spellweaver"])
        let character = gm.game.characters[0]
        XCTAssertNil(character.personalQuest)
        let line = TownQuestLine(character: character, onChooseQuest: {}, onRetire: {})
        let ideal = NSHostingController(rootView: line.environment(gm).fixedSize()).view.fittingSize
        XCTAssertLessThanOrEqual(ideal.width, 290 - 24)
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
        XCTAssertEqual(GameSetupView.townSubtitle(scenariosPlayed: 0, inTown: false), "Recruit your party and set out")
        XCTAssertEqual(GameSetupView.townSubtitle(scenariosPlayed: 0, inTown: true), "In town",
                       "regression: back from an abandoned scenario, the party isn't still being recruited")
        XCTAssertEqual(GameSetupView.townSubtitle(scenariosPlayed: 1, inTown: true), "In town \u{00B7} 1 scenario played")
        XCTAssertEqual(GameSetupView.townSubtitle(scenariosPlayed: 3, inTown: true), "In town \u{00B7} 3 scenarios played")
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

    /// Each shop tile says what it offers the buyer: Buy, Sell for half, how much more gold is
    /// needed, or Sold out; and the header says how reputation moves the prices.
    func testShopTilesSayWhatTheyOffer() throws {
        let gm = try party(["brute", "tinkerer", "spellweaver"])
        let shop = gm.itemManager
        let item = try XCTUnwrap(shop.availableItems().filter { $0.count == 2 && $0.cost >= 10 }.min { $0.cost < $1.cost })
        let (a, b, c) = (gm.game.characters[0], gm.game.characters[1], gm.game.characters[2])
        a.loot = item.cost
        XCTAssertEqual(ItemShopSheet.offer(item, for: a, items: shop), .buy)
        a.loot = item.cost - 3
        XCTAssertEqual(ItemShopSheet.offer(item, for: a, items: shop), .short(3))
        a.loot = item.cost
        XCTAssertTrue(shop.buy(item, for: a))
        XCTAssertEqual(ItemShopSheet.offer(item, for: a, items: shop), .sell(item.cost / 2))
        b.loot = item.cost
        XCTAssertTrue(shop.buy(item, for: b))
        c.loot = 100
        XCTAssertEqual(ItemShopSheet.offer(item, for: c, items: shop), .soldOut)

        XCTAssertEqual(ItemShopSheet.subtitle(prosperity: 1, reputation: 0), "Prosperity 1 \u{00B7} reputation 0, prices as printed")
        XCTAssertEqual(ItemShopSheet.subtitle(prosperity: 2, reputation: 7), "Prosperity 2 \u{00B7} reputation 7, prices 2 gold lower")
        XCTAssertEqual(ItemShopSheet.subtitle(prosperity: 2, reputation: -3), "Prosperity 2 \u{00B7} reputation -3, prices 1 gold higher")
    }

    /// Regression: item text lost its icons' words and left gaps ("consider any  attack modifier
    /// card … to be a  instead", "Refresh  one of your consumed  items"). Every item says what it
    /// does in whole words.
    func testEveryItemSaysWhatItDoes() throws {
        let gm = try party(["brute"])
        let store = gm.editionStore
        for item in store.items(for: "gh") {
            let rule = GameText.itemRule(item, labels: store)
            XCTAssertFalse(rule.isEmpty, "#\(item.id) \(item.name)")
            XCTAssertNil(rule.range(of: #"%|  | [.,]|\bConsume\.|\b[a-z]+[A-Z]"#, options: .regularExpression),
                         "#\(item.id) \(item.name): \(rule)")
        }
        func rule(_ id: Int) throws -> String { GameText.itemRule(try XCTUnwrap(store.itemData(id: id, edition: "gh")), labels: store) }
        XCTAssertEqual(try rule(7), "When attacked, consider any \u{00D7}2 attack modifier card the enemy draws to be a +0 instead.")
        XCTAssertEqual(try rule(17), "During your turn, Refresh one of your consumed small items.")
        XCTAssertEqual(try rule(77), "During your melee attack, consume Ice to add +2 Attack to a single attack.")
        XCTAssertEqual(try rule(75), "During your turn, consume any element to create any element.")
        XCTAssertTrue(try rule(139).hasPrefix("Any time you perform an Augment action"))
        XCTAssertEqual(try rule(1), "During your movement, add +2 Move to the movement.")
        XCTAssertEqual(try rule(35), "During your turn, summon a Jade Falcon: 2 health, Move 3, Attack 2, flying.")
        // Heavy armor says what it costs (iPad playthrough 2026-10-09: Hide Armor's two −1 cards).
        let hide = try rule(3), hood = try rule(76)
        XCTAssertTrue(hide.hasSuffix("Adds two \u{2212}1 cards to your attack modifier deck."), hide)
        XCTAssertTrue(hood.hasSuffix("Shield 1. Adds one \u{2212}1 card to your attack modifier deck."), hood)
        XCTAssertFalse(try rule(7).contains("\u{2212}1 card"))
    }

    // MARK: - Character sheet

    /// The sheet's level line: how far through the level, what's left, and the next threshold.
    func testTheSheetSaysHowFarToTheNextLevel() {
        let mid = CharacterSheetView.levelProgress(level: 3, experience: 120)
        XCTAssertEqual(mid.fraction, 25.0 / 55.0, accuracy: 0.001)
        XCTAssertEqual(mid.toNext, "30 XP to level 4")
        XCTAssertEqual(mid.next, "Level 4 at 150")
        XCTAssertEqual(CharacterSheetView.levelProgress(level: 1, experience: 0).toNext, "45 XP to level 2")
        XCTAssertEqual(CharacterSheetView.levelProgress(level: 1, experience: 50).toNext, "Ready to level up")
        XCTAssertEqual(CharacterSheetView.levelProgress(level: 1, experience: 50).fraction, 1)
        XCTAssertEqual(CharacterSheetView.levelProgress(level: 9, experience: 600).toNext, "Highest level")

        XCTAssertEqual(CharacterSheetView.subtitle(className: "Brute", named: false, level: 1, won: 0),
                       "Level 1 \u{00B7} no scenarios won yet")
        XCTAssertEqual(CharacterSheetView.subtitle(className: "Brute", named: true, level: 3, won: 6),
                       "Brute \u{00B7} Level 3 \u{00B7} 6 scenarios won")
        XCTAssertEqual(CharacterSheetView.battleGoalNote(checkmarks: 4), "Every three checkmarks earn a perk. One earned.")
        XCTAssertEqual(CharacterSheetView.battleGoalNote(checkmarks: 2), "Every three checkmarks earn a perk. None earned.")
    }

    /// The sheet and the shop open over the town at its full size, as large dialogs.
    func testTheSheetAndShopFitTheScreen() throws {
        let gm = try party(["brute", "spellweaver"])
        let brute = gm.game.characters[0]
        for screen in [CGSize(width: 1210, height: 834), CGSize(width: 1376, height: 1032)] {
            for view in [AnyView(CharacterSheetView(character: brute, onDone: {})), AnyView(ItemShopSheet(character: brute))] {
                let size = NSHostingController(rootView: view.environment(gm)).sizeThatFits(in: screen)
                XCTAssertLessThanOrEqual(size.width, screen.width + 0.5, "\(screen)")
                XCTAssertLessThanOrEqual(size.height, screen.height + 0.5, "\(screen)")
            }
        }
    }
}
