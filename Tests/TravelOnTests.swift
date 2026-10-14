import XCTest
@testable import GlavenGameLib

/// CMP-8: after a scenario the party may travel on without returning to Gloomhaven. On the road
/// the town isn't visited — no city event — and the scenario the last one links to, or the same
/// one tried again, is reached without a road event (FAQ); anywhere else is reached by road.
@MainActor
final class TravelOnTests: XCTestCase {

    private func scenario(_ gm: GameManager, _ index: String) throws -> ScenarioData {
        try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
    }

    func testTravellingOnFromBlackBarrow() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        let gm = sim.gm
        gm.completeScenario(success: true, returning: false)
        XCTAssertEqual(gm.game.events.onTheRoadFrom, "gh-1")
        XCTAssertFalse(gm.game.events.cityEventDue, "no visit to town: no city event")
        let events = gm.eventCardManager
        XCTAssertFalse(events.needsRoadEvent(for: try scenario(gm, "2")), "Black Barrow links to Barrow Lair")
        XCTAssertFalse(events.needsRoadEvent(for: try scenario(gm, "1")), "the same scenario again")
        XCTAssertTrue(events.needsRoadEvent(for: try scenario(gm, "3")), "anywhere else is by road")
        XCTAssertTrue(GameSetupView.onTheRoadText(from: try scenario(gm, "1")).contains("#2"))

        // Back to Gloomhaven after all: the town's city event, and the road to Barrow Lair.
        gm.returnToGloomhaven()
        XCTAssertNil(gm.game.events.onTheRoadFrom)
        XCTAssertTrue(gm.game.events.cityEventDue)
        XCTAssertTrue(events.needsRoadEvent(for: try scenario(gm, "2")), "from town, Barrow Lair is by road")
    }

    /// Setting out for the next scenario ends the journey: after it, the party chooses again.
    func testTheNextScenarioEndsTheJourney() throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        let gm = sim.gm
        gm.completeScenario(success: false, returning: false)
        XCTAssertEqual(gm.game.events.onTheRoadFrom, "gh-1", "a lost scenario may be tried again straight away")
        gm.startScenarioOnBoard(try scenario(gm, "1"))
        XCTAssertNil(gm.game.events.onTheRoadFrom)
        gm.completeScenario(success: true)
        XCTAssertNil(gm.game.events.onTheRoadFrom, "returning, the party is in Gloomhaven")
        XCTAssertTrue(gm.game.events.cityEventDue)
    }

    /// The state is kept in a save.
    func testTheRoadIsSaved() throws {
        var state = EventState()
        state.onTheRoadFrom = "gh-4"
        let decoded = try JSONDecoder().decode(EventState.self, from: try JSONEncoder().encode(state))
        XCTAssertEqual(decoded.onTheRoadFrom, "gh-4")
        let old = try JSONDecoder().decode(EventState.self, from: Data("{}".utf8))
        XCTAssertNil(old.onTheRoadFrom)
    }
}

/// Envelope X (GH 58, 60, and the quests that end in them): a sealed envelope of the box. Its
/// class isn't in the game's data; opening it is recorded once and said.
@MainActor
final class EnvelopeTests: XCTestCase {

    func testAScenarioRewardOpensEnvelopeX() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let rewards = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "58" && $0.solo == nil }?.rewards)
        XCTAssertEqual(rewards.envelopes, ["X"])
        gm.scenarioManager.applyRewardChoices(rewards, edition: "gh", choices: ScenarioRewardChoices())
        XCTAssertEqual(gm.game.events.openedEnvelopes, ["X"])
        gm.scenarioManager.applyRewardChoices(rewards, edition: "gh", choices: ScenarioRewardChoices())
        XCTAssertEqual(gm.game.campaignLog.filter { $0.type == .envelopeOpened }.count, 1, "opened once")
        XCTAssertEqual(gm.game.campaignLog.last { $0.type == .envelopeOpened }?.message, "Opened Envelope X")
        let saved = try JSONDecoder().decode(EventState.self, from: try JSONEncoder().encode(gm.game.events))
        XCTAssertEqual(saved.openedEnvelopes, ["X"], "kept in a save")
    }

    /// A Helping Hand's sequel, quest 526: fulfilled, its retirement opens Envelope X.
    func testRetiringWithItsQuestOpensEnvelopeX() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = gm.game.characters[0]
        brute.personalQuest = "526"
        brute.personalQuestProgress = [4, 1]
        gm.game.completedScenarios.insert("gh-58")
        XCTAssertTrue(gm.characterManager.retireCharacter(brute))
        XCTAssertEqual(gm.game.events.openedEnvelopes, ["X"])
    }
}
