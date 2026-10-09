import XCTest
import SwiftUI
@testable import GlavenGameLib

/// The town's dialogs in the board's look: the campaign, the world map, a character's hand,
/// table rules, campaigns and credits.
@MainActor
final class TownDialogTests: XCTestCase {

    private func party() throws -> GameManager {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        return gm
    }

    // MARK: - Campaign

    /// Regression: campaign progress read "0/113" for Gloomhaven, counting the 17 solo
    /// scenarios and the random dungeon among its 95.
    func testCampaignProgressCountsTheCampaignsScenarios() throws {
        let gm = try party()
        XCTAssertEqual(PartySheetView.campaignScenarios(gm.editionStore.scenarios(for: "gh")).count, 95)
    }

    func testCampaignSaysWhereTheTownStands() {
        XCTAssertEqual(PartySheetView.prosperityToNext(checkmarks: 6, level: 2), "3 to level 3")
        XCTAssertEqual(PartySheetView.prosperityToNext(checkmarks: 0, level: 1), "4 to level 2")
        XCTAssertEqual(PartySheetView.prosperityToNext(checkmarks: 64, level: 9), "Highest level")
        XCTAssertEqual(PartySheetView.prosperityWindow(level: 2), 5...15, "this level's checkmarks and the next level's")
        XCTAssertEqual(PartySheetView.prosperityWindow(level: 9), 65...65)
        XCTAssertEqual(PartySheetView.reputationNote(0), "prices as printed")
        XCTAssertEqual(PartySheetView.reputationNote(3), "prices 1 lower")
        XCTAssertEqual(PartySheetView.reputationNote(-7), "prices 2 higher")
        XCTAssertEqual(PartySheetView.wonLine(0), "no scenarios won yet")
        XCTAssertEqual(PartySheetView.wonLine(2), "2 scenarios won")
    }

    // MARK: - World map

    /// Regression: the map showed every scenario's sticker from the start, spoiling the
    /// campaign. A sticker appears once its scenario is unlocked, and stays once won.
    func testTheMapShowsOnlyTheScenariosFound() throws {
        let gm = try party()
        let all = gm.editionStore.scenarios(for: "gh")
        XCTAssertEqual(WorldMapView.found(all, gm.scenarioManager).map(\.index), ["1"], "a new campaign has found Black Barrow")
        gm.game.completedScenarios.insert("gh-1")
        XCTAssertEqual(Set(WorldMapView.found(all, gm.scenarioManager).map(\.index)), ["1", "2"], "Black Barrow unlocks Barrow Lair")

        let lair = try XCTUnwrap(gm.editionStore.scenarioData(index: "2", edition: "gh"))
        XCTAssertFalse(gm.scenarioManager.isAvailable(lair), "found, but it needs First Steps to be played")
        XCTAssertEqual(WorldMapView.needs(lair, labels: gm.editionStore), "Party achievement First Steps")
        let rift = try XCTUnwrap(gm.editionStore.scenarioData(index: "21", edition: "gh"))
        XCTAssertTrue(WorldMapView.needs(rift, labels: gm.editionStore).hasSuffix("not yet gained"))
        XCTAssertEqual(WorldMapView.unlockedBy(lair, among: all, won: gm.game.completedScenarios).map(\.index), ["1"])
        XCTAssertEqual(WorldMapView.foundLine(1), "1 scenario found")
    }

    // MARK: - Hand

    /// The whole pool shows at once when it can, as large as it fits; a big pool scrolls.
    func testTheHandShowsEveryCardAtOnce() {
        let space = CGSize(width: 1110, height: 600)
        let brute = HandSheet.layout(count: 13, in: space)
        XCTAssertTrue(brute.fits)
        let rows = (13 + brute.columns - 1) / brute.columns
        XCTAssertLessThanOrEqual(CGFloat(rows) * brute.width * 1.4 + CGFloat(rows - 1) * HandSheet.gap, space.height)
        XCTAssertGreaterThan(brute.width, 120, "large enough to read")
        let big = HandSheet.layout(count: 60, in: CGSize(width: 1110, height: 300))
        XCTAssertFalse(big.fits)
        XCTAssertEqual(big.columns, 8)
    }

    // MARK: - Size

    /// Every dialog opens inside the screen, on the 11-inch and the 13-inch.
    func testTheDialogsFitTheScreen() throws {
        let gm = try party()
        gm.game.completedScenarios = ["gh-1", "gh-2"]
        let brute = gm.game.characters[0]
        let views: [(String, AnyView)] = [
            ("campaign", AnyView(PartySheetView())), ("world map", AnyView(WorldMapView())),
            ("hand", AnyView(HandSheet(character: brute))), ("table rules", AnyView(TableRulesSheet())),
            ("campaigns", AnyView(CampaignsSheet())), ("credits", AnyView(CreditsSheet())),
            ("items", AnyView(ItemLoadoutSheet(character: brute))), ("enhancer", AnyView(EnhancementSheet(character: brute))),
            ("level up", AnyView(LevelUpCardSheet(character: brute))), ("statistics", AnyView(PartyStatisticsSheet())),
            ("quest", AnyView(QuestPicker(character: brute, onDone: {}))), ("battle goals", AnyView(BattleGoalPicker(onDone: {}))),
            ("sanctuary", AnyView(SanctuarySheet(onDone: {}))),
        ]
        for screen in [CGSize(width: 1210, height: 834), CGSize(width: 1376, height: 1032)] {
            for (name, view) in views {
                let size = NSHostingController(rootView: view.environment(gm)).sizeThatFits(in: screen)
                XCTAssertLessThanOrEqual(size.width, screen.width + 0.5, "\(name) \(screen)")
                XCTAssertLessThanOrEqual(size.height, screen.height + 0.5, "\(name) \(screen)")
            }
        }
    }

    func testCampaignsSayWhereAndWhen() {
        XCTAssertTrue(CampaignsSheet.subtitle(count: 2).hasSuffix("\u{00B7} 2 campaigns"))
        XCTAssertFalse(CampaignsSheet.subtitle(count: 0).contains("\u{00B7}"))
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(CampaignsSheet.line(detail: "Brute, Tinkerer", played: date).hasPrefix("Brute, Tinkerer \u{00B7} played "))
        XCTAssertTrue(CampaignsSheet.line(detail: nil, played: date).hasPrefix("played "))
    }

    // MARK: - Recruiting

    /// A recruit can be taken back from the quest picker: they leave, and so does the log's
    /// "joined the party", while the rest of the log stays.
    func testCancellingTheQuestUndoesTheRecruit() throws {
        let gm = try party()
        let before = gm.game.campaignLog.count
        gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
        let recruit = try XCTUnwrap(gm.game.characters.first { $0.name == "cragheart" })
        gm.characterManager.dealQuests(to: recruit)
        XCTAssertEqual(gm.game.campaignLog.count, before + 1)
        gm.characterManager.undoRecruit(recruit)
        XCTAssertFalse(gm.game.characters.contains { $0.name == "cragheart" })
        XCTAssertEqual(gm.game.campaignLog.count, before, "no trace of the recruit")
        XCTAssertTrue(gm.game.campaignLog.contains { $0.message == "Brute joined the party" })
    }

    // MARK: - Holding to learn

    /// Holding Prosperity, Reputation, City Event or Sanctuary in town says what it is, with this
    /// campaign's numbers, and links to its page in How to Play.
    func testHoldingTheTownsButtonsExplainsThem() throws {
        let gm = try party()
        gm.game.partyProsperity = 6
        gm.game.partyReputation = 7
        gm.game.events.sanctuaryGold = 130
        gm.game.events.cityEventDue = true
        let explain = { BoardCoordinator.townExplanation($0, game: gm.game) }
        let prosperity = explain(.prosperity)
        XCTAssertEqual(prosperity.title, "Prosperity 2")
        XCTAssertEqual(prosperity.rows.first?.value, "6 of 9 to level 3")
        XCTAssertEqual(prosperity.topic, .prosperity)
        let reputation = explain(.reputation)
        XCTAssertEqual(reputation.title, "Reputation +7")
        XCTAssertEqual(reputation.rows.first?.value, "2 gold lower")
        XCTAssertEqual(explain(.cityEvent).rows.first?.value, "Due now, before setting out")
        XCTAssertEqual(explain(.sanctuary).rows.last?.value, "30 of 100 gold to the next prosperity")
        for subject in [LearnSubject.prosperity, .reputation, .cityEvent, .sanctuary] {
            let topic = try XCTUnwrap(explain(subject).topic)
            XCTAssertEqual(LearnTopic.topic(topic).chapter, .town)
        }
        gm.game.partyReputation = -5
        XCTAssertEqual(explain(.reputation).rows.first?.value, "1 gold higher")
    }

    // MARK: - Words

    func testTheDialogsSayWhatTheyShow() throws {
        XCTAssertEqual(BattleGoalPicker.subtitle(name: "Brute", index: 0, of: 2), "Brute, 1 of 2 \u{00B7} keep one, secretly")
        XCTAssertEqual(SanctuarySheet.progress(30), "30 of 100 gold")
        XCTAssertEqual(SanctuarySheet.progress(130), "30 of 100 gold, 100 given before")
        XCTAssertEqual(ItemLoadoutSheet.atHome("Already bringing 1 small item"), "At home \u{00B7} already bringing 1 small item")
        XCTAssertEqual(ItemLoadoutSheet.atHome(nil), "At home")
        XCTAssertTrue(LevelUpCardSheet.note(name: "Brute", level: 2, handSize: 10).hasPrefix("Choose one card of level 2 or lower."))
        XCTAssertEqual(LevelUpCardSheet.cardWidth(count: 2, in: CGSize(width: 1100, height: 600)), 300)
        XCTAssertLessThan(LevelUpCardSheet.cardWidth(count: 5, in: CGSize(width: 1100, height: 600)), 220)

        let gm = try party()
        let brute = gm.game.characters[0]
        brute.record.kills = ["bandit-guard": 4, "living-bones": 2]
        brute.record.eliteKills = 1
        brute.record.timesExhausted = 1
        brute.record.scenariosCompleted = ["gh-1"]
        gm.game.characters[1].record.kills = ["bandit-guard": 3]
        gm.game.completedScenarios = ["gh-1"]
        gm.game.campaignLog.append(CampaignLogEntry(type: .scenarioFailed, message: "Lost #2"))
        let totals = PartyStatisticsSheet.totals(gm.game)
        XCTAssertEqual(totals.won, 1)
        XCTAssertEqual(totals.lost, 1)
        XCTAssertEqual(totals.kills, 9)
        XCTAssertEqual(totals.exhaustions, 1)
        XCTAssertEqual(totals.mostKilled?.name, "bandit-guard")
        XCTAssertEqual(totals.mostKilled?.count, 7)
        XCTAssertEqual(PartyStatisticsSheet.numbers(brute), [1, 6, 1, 1, brute.experience, brute.loot])
    }
}
