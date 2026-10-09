import XCTest
import SwiftData
import SwiftUI
@testable import GlavenGameLib

/// Several campaigns side by side, each saved to its own file: a new campaign never replaces
/// another, any of them can be played, renamed, duplicated, exported or deleted, and saves from
/// before campaigns were files carry over.
@MainActor
final class CampaignTests: XCTestCase {

    private func container() throws -> ModelContainer {
        try ModelContainer(for: Schema([SettingsModel.self, SavedGameModel.self]),
                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    private func manager(_ container: ModelContainer) -> GameManager {
        let gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        return gm
    }

    /// A recruit who has kept a quest is saved at once (iPad playthrough 2026-10-09: a new
    /// party lived only in memory until something else saved it).
    func testARecruitsKeptQuestSavesTheCampaign() throws {
        let gm = manager(try container())
        gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
        let character = gm.game.characters[0]
        gm.characterManager.dealQuests(to: character)
        gm.characterManager.chooseQuest(try XCTUnwrap(character.questChoices.first), for: character)
        XCTAssertEqual(gm.campaigns, [])
        GameSetupView.questKept(gm)
        XCTAssertEqual(gm.campaigns.count, 1)
    }

    /// A store kept in memory (tests, previews) never writes to the player's own campaigns.
    func testATestStoreKeepsItsCampaignsInATemporaryFolder() throws {
        let gm = manager(try container())
        XCTAssertTrue(gm.campaignStore.directory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertEqual(gm.campaigns, [])
    }

    /// New Campaign keeps the first party; each plays back as it was left.
    func testANewCampaignKeepsTheOneBeforeIt() throws {
        let store = try container()
        let gm = manager(store)
        gm.beginNewGame()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.game.completedScenarios.insert("gh-1")
        gm.returnToMainMenu()
        let first = try XCTUnwrap(gm.currentCampaignID)

        gm.beginNewGame()
        XCTAssertNil(gm.currentCampaignID, "a new campaign, not the old one")
        XCTAssertTrue(gm.game.characters.isEmpty)
        gm.saveGame()
        XCTAssertEqual(gm.campaigns.count, 1, "no file for a campaign without a party")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        gm.returnToMainMenu()
        let second = try XCTUnwrap(gm.currentCampaignID)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(gm.campaigns.map(\.id), [second, first], "most recently played first")
        XCTAssertEqual(gm.autosaveSummary?.characterNames, ["Tinkerer"], "Continue offers the latest")

        gm.continueCampaign(first)
        XCTAssertEqual(gm.game.characters.map(\.name), ["brute"])
        XCTAssertEqual(gm.game.completedScenarios, ["gh-1"])
        XCTAssertEqual(gm.campaigns.first?.id, first, "now the latest")

        // A relaunch finds both.
        let relaunched = manager(store)
        XCTAssertEqual(Set(relaunched.campaigns.map(\.id)), [first, second])
        relaunched.continueGame()
        XCTAssertEqual(relaunched.currentCampaignID, first)
        XCTAssertEqual(relaunched.game.characters.map(\.name), ["brute"])
    }

    /// New Campaign from the app menu saves the campaign being played, then starts another.
    func testNewCampaignFromTheMenuSavesTheCurrentOne() throws {
        let gm = manager(try container())
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.requestNewGame()
        XCTAssertEqual(gm.appPhase, .gameSetup)
        XCTAssertTrue(gm.game.characters.isEmpty)
        XCTAssertEqual(gm.campaigns.count, 1)
        XCTAssertEqual(gm.campaigns.first?.summary?.characterNames, ["Brute"])
    }

    func testRenameDuplicateAndDelete() throws {
        let gm = manager(try container())
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.saveGame()
        let id = try XCTUnwrap(gm.currentCampaignID)
        XCTAssertEqual(gm.campaigns.first?.title, "Brute", "named after the party until renamed")

        gm.renameCampaign(id, to: "  The Ravens ")
        XCTAssertEqual(gm.campaigns.first?.title, "The Ravens")
        XCTAssertEqual(CampaignsSheet.detail(try XCTUnwrap(gm.campaigns.first)), "Brute")

        let copy = try XCTUnwrap(gm.duplicateCampaign(id))
        XCTAssertEqual(gm.campaigns.map(\.id), [id, copy], "the copy below the original")
        XCTAssertEqual(gm.campaigns.last?.title, "The Ravens (copy)")
        XCTAssertEqual(gm.currentCampaignID, id, "play carries on in the original")

        gm.deleteCampaign(id)
        XCTAssertEqual(gm.campaigns.map(\.id), [copy])
        XCTAssertFalse(gm.campaignStore.exists(id))
        XCTAssertNil(gm.currentCampaignID)
        XCTAssertEqual(gm.game.characters.map(\.name), ["brute"], "the game on screen stays until it's saved anew")
    }

    /// An exported campaign imports as a new one beside it; an export from before campaigns
    /// (a bare game) imports too; anything else is refused.
    func testExportAndImport() throws {
        let gm = manager(try container())
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let data = try XCTUnwrap(gm.exportGameData())
        let original = try XCTUnwrap(gm.currentCampaignID)

        XCTAssertTrue(gm.importGameData(data))
        XCTAssertEqual(gm.campaigns.count, 2, "an import never replaces a campaign")
        XCTAssertTrue(gm.campaigns.allSatisfy { $0.summary?.characterNames == ["Brute"] })

        let bare = try JSONEncoder().encode(gm.game.toSnapshot())
        XCTAssertTrue(gm.importGameData(bare))
        XCTAssertEqual(gm.campaigns.count, 3)
        XCTAssertFalse(gm.importGameData(Data("not a campaign".utf8)))
        XCTAssertEqual(gm.campaigns.count, 3)
        XCTAssertEqual(gm.currentCampaignID, original)
    }

    /// The autosave and named saves kept in SwiftData before campaigns were files become
    /// campaigns on the next launch, once.
    func testSavesFromBeforeCampaignsCarryOver() throws {
        let store = try container()
        let old = manager(store)
        old.characterManager.addCharacter(name: "brute", edition: "gh")
        let context = ModelContext(store)
        for name in ["autosave", "Before the boss"] {
            let model = SavedGameModel(name: name)
            model.snapshotData = try JSONEncoder().encode(old.game.toSnapshot())
            context.insert(model)
        }
        try context.save()

        let gm = manager(store)
        XCTAssertEqual(gm.campaigns.count, 2)
        XCTAssertEqual(Set(gm.campaigns.map(\.title)), ["Brute", "Before the boss"])
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<SavedGameModel>()).count, 0, "moved, not copied")
        XCTAssertEqual(manager(store).campaigns.count, 2, "only once")
        gm.continueGame()
        XCTAssertEqual(gm.game.characters.map(\.name), ["brute"])
    }

    /// A city event drawn is saved with its deck: quitting before resolving it and coming back
    /// shows the same card, not a fresh shuffle.
    func testADrawnEventIsTheSameAfterARelaunch() throws {
        let store = try container()
        let gm = manager(store)
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.saveGame()
        gm.prepareEvents([.city, .road])
        let city = try XCTUnwrap(gm.eventCardManager.topCard(.city)?.cardId)
        let road = try XCTUnwrap(gm.eventCardManager.topCard(.road)?.cardId)

        let relaunched = manager(store)
        relaunched.continueGame()
        XCTAssertEqual(relaunched.eventCardManager.topCard(.city)?.cardId, city)
        XCTAssertEqual(relaunched.eventCardManager.topCard(.road)?.cardId, road)
    }

    /// Battle goals dealt before setting out are kept through a relaunch: setting out again
    /// mustn't deal a fresh pair (a free redraw). A finished scenario clears them for the next.
    func testDealtBattleGoalsSurviveARelaunch() throws {
        let store = try container()
        let gm = manager(store)
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        gm.scenarioManager.dealBattleGoals()
        gm.saveGame()
        let dealt = gm.game.characters.map(\.battleGoalCardIds)
        XCTAssertTrue(dealt.allSatisfy { $0.count == 2 })
        XCTAssertEqual(Set(dealt.joined()).count, 4, "no card dealt twice")

        let relaunched = manager(store)
        relaunched.continueGame()
        relaunched.scenarioManager.dealBattleGoals()
        XCTAssertEqual(relaunched.game.characters.map(\.battleGoalCardIds), dealt)
    }

    /// `CAMPAIGNS_RENDER_OUT=/tmp/c.png swift test --filter testRenderCampaigns` renders the list.
    func testRenderCampaigns() throws {
        guard let out = ProcessInfo.processInfo.environment["CAMPAIGNS_RENDER_OUT"] else {
            throw XCTSkip("set CAMPAIGNS_RENDER_OUT to render the campaigns")
        }
        GlavenFont.registerFonts()
        let gm = manager(try container())
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        gm.saveGame()
        gm.renameCampaign(try XCTUnwrap(gm.currentCampaignID), to: "The Ravens")
        gm.beginNewGame()
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        gm.saveGame()
        let view = CampaignsSheet(scrolls: false).environment(gm).frame(width: 700, height: 400)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }

    /// New Campaign starts from nothing: no prosperity, reputation, unlocks, looted treasures,
    /// retirements, log or event decks carried over from the campaign before (every stored
    /// field of the game compared with a fresh one, so a field added later can't be missed).
    func testANewCampaignCarriesNothingOver() throws {
        let gm = manager(try container())
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let game = gm.game
        game.partyProsperity = 30
        game.partyReputation = 10
        game.partyName = "The Old Guard"
        game.difficulty = .hard
        game.unlockedItems.insert("gh-100")
        game.unlockedCharacters.insert("gh-sun")
        game.lootedTreasures.insert("gh-1-7")
        game.manualScenarios.insert("gh-52")
        game.completedScenarios.insert("gh-1")
        game.campaignLog.append(CampaignLogEntry(type: .scenarioCompleted, message: "a scenario"))
        game.events.sanctuaryGold = 30
        game.playSeconds = 500
        game.totalSeconds = 900

        gm.newGame()

        // Generated ids differ between any two decks and shuffled decks differ in order: decks are
        // compared by their cards' makeup.
        func describe(_ value: Any) -> String {
            if let deck = value as? AttackModifierDeck {
                return "\(deck.current) " + deck.cards.map { "\($0.type) \($0.value)" }.sorted().joined(separator: ",")
            }
            return String(describing: value).replacingOccurrences(
                of: "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", with: "<id>",
                options: .regularExpression)
        }
        let fresh = GameState()
        let after = Dictionary(uniqueKeysWithValues: Mirror(reflecting: game).children.compactMap { child in
            child.label.map { ($0, describe(child.value)) }
        })
        for child in Mirror(reflecting: fresh).children {
            guard let label = child.label, !label.contains("observationRegistrar") else { continue }
            XCTAssertEqual(after[label], describe(child.value), "\(label) starts over")
        }
    }

    /// A save that can't be written is reported, not lost silently; the next save that works
    /// clears the report.
    func testAFailedSaveIsReported() throws {
        let gm = manager(try container())
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let folder = gm.campaignStore.directory
        try? FileManager.default.removeItem(at: folder)
        // A file where the folder should be: nothing can be written there.
        try Data("x".utf8).write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }

        gm.saveGame()
        XCTAssertNotNil(gm.saveFailure)

        try FileManager.default.removeItem(at: folder)
        gm.saveGame()
        XCTAssertNil(gm.saveFailure)
    }

    /// A save missing fields (an older version, or edited by hand) still loads, with those
    /// fields at their starting values, instead of disappearing from the list.
    func testASaveMissingFieldsStillLoads() throws {
        let gm = manager(try container())
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.game.partyReputation = 4
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(gm.game.toSnapshot())) as? [String: Any])
        for key in ["lootDeck", "conditions", "elementBoard", "playSeconds", "campaignStickers", "partyName"] {
            XCTAssertNotNil(json.removeValue(forKey: key), key)
        }
        let snapshot = try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(snapshot.partyReputation, 4)
        XCTAssertEqual(snapshot.figures.count, 1)
        XCTAssertEqual(snapshot.elementBoard.count, ElementModel.defaultBoard().count)
    }
}
