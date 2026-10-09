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
}
