import XCTest
import SwiftUI
@testable import GlavenGameLib

/// Every scenario opens with its goal, how it can be lost and its special rules, and closes with
/// what really happened: why it ended, the experience and gold each character gained, and the
/// rewards — in words a player can read.
@MainActor
final class ScenarioFramingTests: XCTestCase {

    // MARK: - The brief

    private func brief(_ index: String) throws -> ScenarioBrief {
        let gm = try SaveAndContinueTestsSupport.manager()
        let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
        return ScenarioBrief.make(for: data, labels: gm.editionStore)
    }

    /// Every GH scenario's brief has a goal and reads cleanly: no placeholders, no data names,
    /// whole sentences.
    func testEveryBriefReadsCleanly() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        let scenarios = gm.editionStore.scenarios(for: "gh").filter { $0.solo == nil }
        XCTAssertGreaterThan(scenarios.count, 90)
        for data in scenarios {
            let brief = ScenarioBrief.make(for: data, labels: gm.editionStore)
            XCTAssertFalse(brief.goal.isEmpty)
            XCTAssertEqual(brief.defeat.first, "Every character is exhausted.")
            for line in [brief.title, brief.goal] + brief.defeat + brief.rules {
                XCTAssertEqual(PlayerTextTests.lint(line), [], "#\(data.index): \(line)")
                XCTAssertFalse(line.contains("%") || line.contains(" ,") || line.contains(":+"), "#\(data.index): \(line)")
            }
            for line in brief.rewards + [brief.map].compactMap({ $0 }) {
                XCTAssertEqual(PlayerTextTests.lint(line), [], "#\(data.index): \(line)")
                XCTAssertFalse(line.contains("%"), "#\(data.index): \(line)")
            }
            for line in [brief.goal] + brief.defeat + brief.rules {
                XCTAssertTrue(line.hasSuffix(".") || line.hasSuffix("!"), "#\(data.index) reads as a sentence: \(line)")
                XCTAssertGreaterThanOrEqual(line.split(separator: " ").count, 3, "#\(data.index) is a whole rule: \(line)")
            }
        }
    }

    /// Regression: the Brute's solo scenario is also #1 (and the other solos #2–#17), and the
    /// index kept whichever loaded last; on iPad that was the solo, so a saved Black Barrow came
    /// back as "Return to the Black Barrow", with its monsters, its reward and no portraits.
    func testANumberNamesTheCampaignScenario() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        let campaign = gm.editionStore.scenarios(for: "gh").filter { $0.group == nil && $0.parent == nil }
        XCTAssertGreaterThan(campaign.count, 90)
        for data in campaign {
            let found = gm.editionStore.scenarioData(index: data.index, edition: "gh")
            XCTAssertNil(found?.solo, "#\(data.index)")
            XCTAssertEqual(found?.name, data.name, "#\(data.index)")
        }
        let barrow = try XCTUnwrap(campaign.first { $0.index == "1" })
        gm.scenarioManager.setScenario(barrow)
        let restored = try XCTUnwrap(gm.game.scenario?.toSnapshot().toRuntime(editionStore: gm.editionStore))
        XCTAssertEqual(restored.data.name, barrow.name, "a saved Black Barrow comes back as itself")
    }

    /// The brief names each monster type once, by its key: a level spec ("living-corpse:+2") is
    /// not part of the name, and the key finds the portrait.
    func testBriefMonstersAreKeys() throws {
        XCTAssertEqual(try brief("28").monsters.filter { $0.contains(":") }, [])
        XCTAssertTrue(try brief("28").monsters.contains("living-corpse"))
        let keys = ScenarioBrief.make(for: ScenarioData(index: "x", name: "x", edition: "gh",
                                                        monsters: ["living-bones:-1", "living-bones", "bandit-guard:2"]))
            .monsters
        XCTAssertEqual(keys, ["living-bones", "bandit-guard"])
    }

    func testBriefsSayWhatTheScenarioAsks() throws {
        XCTAssertEqual(try brief("1"), ScenarioBrief(title: "#1 Black Barrow", goal: "Kill every enemy.",
                                                     defeat: ["Every character is exhausted."], rules: [],
                                                     monsters: ["bandit-archer", "bandit-guard", "living-bones"],
                                                     map: "3 rooms · start in L1a",
                                                     rewards: ["Party achievement: First Steps", "Unlocks #2 Barrow Lair"]))
        XCTAssertEqual(try brief("2").rules, ["Each character adds 3 Curses to their attack modifier deck."])
        XCTAssertEqual(try brief("14").rules.first, "Each character adds 3 \u{2212}1 cards to their attack modifier deck.")
        XCTAssertEqual(try brief("27").goal, "Survive until the end of round 10.")
        XCTAssertEqual(try brief("3").rules, ["More Inox Guards arrive every odd round."])
        XCTAssertTrue(try brief("31").rules.contains("More Night Demons arrive every round."))
        XCTAssertEqual(try brief("56").defeat.last, "Captive Orchid is destroyed.")
        XCTAssertEqual(try brief("60").defeat.last, "Round 12 ends before the goal is met.")
        XCTAssertTrue(try brief("42").rules.contains("All monsters gain Advantage on all their attacks."),
                      "the scenario's printed rules")
        XCTAssertFalse(try brief("19").rules.contains { $0.lowercased().hasPrefix("towards") },
                       "an escort's move instruction isn't a rule")
    }

    // MARK: - When the brief shows

    func testTheBriefOpensANewScenarioButNotAResumedOne() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        XCTAssertEqual(sim.coord.briefPresentation, .intro, "a new scenario opens on its brief")
        XCTAssertEqual(sim.coord.scenarioBrief?.goal, "Kill every enemy.")
        await sim.play(rounds: 1)
        sim.gm.saveAndQuitScenario()
        sim.gm.continueGame()
        XCTAssertNil(sim.gm.boardCoordinator.briefPresentation, "Continue goes straight back to the board")
    }

    /// The brief is made once per scenario (views read it on every render), and is the new
    /// scenario's once another starts.
    func testTheBriefFollowsTheScenario() throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        let first = try XCTUnwrap(sim.coord.scenarioBrief)
        XCTAssertEqual(sim.coord.scenarioBrief, first)
        sim.gm.scenarioManager.setScenario(try XCTUnwrap(sim.gm.editionStore.scenarios(for: "gh").first { $0.index == "2" && $0.solo == nil }))
        XCTAssertNotEqual(sim.coord.scenarioBrief?.title, first.title)
    }

    // MARK: - The results

    private func scenarioOne() throws -> (GameManager, BoardCoordinator) {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        return (gm, gm.boardCoordinator)
    }

    /// The results show what was gained in this scenario, not lifetime totals.
    func testAVictoryShowsWhatEachCharacterGained() throws {
        let (gm, coord) = try scenarioOne()
        let brute = gm.game.characters[0]
        brute.experience += 7
        brute.loot += 3
        coord.endReason = .enemiesDefeated
        coord.scenarioResult = .victory

        let outcome = try XCTUnwrap(coord.scenarioOutcome())
        XCTAssertTrue(outcome.victory)
        XCTAssertEqual(outcome.title, "#1 Black Barrow")
        XCTAssertEqual(outcome.reason, "Every enemy is dead.")
        let hero = try XCTUnwrap(outcome.heroes.first { $0.id == brute.id })
        XCTAssertEqual(hero.name, "Brute")
        XCTAssertEqual(hero.xpGained, 7)
        XCTAssertEqual(hero.bonusXP, gm.levelManager.experience())
        XCTAssertEqual(hero.goldGained, 3)
        XCTAssertEqual(outcome.heroes.first { $0.id != brute.id }?.xpGained, 0)
        XCTAssertTrue(outcome.rewards.contains("Party achievement: First Steps"), "\(outcome.rewards)")
        XCTAssertTrue(outcome.rewards.contains("New scenario: #2 Barrow Lair"), "\(outcome.rewards)")
        for line in [outcome.reason, outcome.note] + outcome.rewards {
            XCTAssertEqual(PlayerTextTests.lint(line), [], line)
        }
    }

    /// Regression: the defeat screen said gold collected in the scenario is lost; under the
    /// rules (p.47) a failed scenario keeps experience and gold, it just gives no rewards.
    func testADefeatKeepsWhatWasGainedAndGivesNoRewards() throws {
        let (gm, coord) = try scenarioOne()
        gm.game.characters[0].loot += 4
        for character in gm.game.characters { character.exhausted = true }
        coord.checkVictoryDefeat()

        let outcome = try XCTUnwrap(coord.scenarioOutcome())
        XCTAssertFalse(outcome.victory)
        XCTAssertEqual(outcome.reason, "Every character is exhausted.")
        XCTAssertEqual(outcome.rewards, [])
        XCTAssertEqual(outcome.heroes.map(\.bonusXP), [0, 0])
        XCTAssertEqual(outcome.heroes.first?.goldGained, 4)
        XCTAssertTrue(outcome.note.contains("keeps the experience and gold"), outcome.note)
        XCTAssertFalse(outcome.note.lowercased().contains("lost"))
    }

    /// A scenario won by its own goal says which goal.
    func testAGoalWinSaysWhichGoal() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "27" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        gm.game.scenario?.pendingFinish = "won"
        gm.boardCoordinator.checkVictoryDefeat()
        XCTAssertEqual(gm.boardCoordinator.endReason?.text, "Goal met: Survive until the end of round 10.")
    }

    /// What was gained is measured from the start of the scenario, which survives a save; so do
    /// the kill counts scenario rules count on.
    func testScenarioTalliesAreSaved() throws {
        let (gm, _) = try scenarioOne()
        let scenario = try XCTUnwrap(gm.game.scenario)
        let brute = gm.game.characters[0]
        XCTAssertEqual(scenario.startingExperience[brute.id], brute.experience)
        scenario.killCounts["bandit-guard"] = 2
        let restored = try XCTUnwrap(scenario.toSnapshot().toRuntime(editionStore: gm.editionStore))
        XCTAssertEqual(restored.startingExperience, scenario.startingExperience)
        XCTAssertEqual(restored.startingGold, scenario.startingGold)
        XCTAssertEqual(restored.killCounts, ["bandit-guard": 2])
    }

    // MARK: - Renders for review

    /// `FRAMING_RENDER_OUT=/tmp/framing swift test --filter testRenderBriefAndResults` writes
    /// brief-<n>.png and results-victory/defeat.png at iPad size.
    func testRenderBriefAndResults() throws {
        guard let out = ProcessInfo.processInfo.environment["FRAMING_RENDER_OUT"] else {
            throw XCTSkip("set FRAMING_RENDER_OUT to render the screens")
        }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        GlavenFont.registerFonts()
        func render<V: View>(_ view: V, _ name: String) throws {
            let renderer = ImageRenderer(content: view.frame(width: 1376, height: 1032).background(Color(white: 0.2)))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }
        for index in ["1", "21", "27", "42"] {
            try render(ScenarioBriefCard(brief: try brief(index), buttonTitle: "Begin") {}, "brief-\(index)")
        }
        let (gm, coord) = try scenarioOne()
        gm.game.characters[0].experience += 7
        gm.game.characters[0].loot += 3
        coord.endReason = .enemiesDefeated
        coord.scenarioResult = .victory
        try render(ScenarioResultsView(outcome: try XCTUnwrap(coord.scenarioOutcome())) { _ in }.environment(gm), "results-victory")
        coord.scenarioResult = .defeat
        coord.endReason = .partyExhausted
        gm.game.characters[1].exhausted = true
        try render(ScenarioResultsView(outcome: try XCTUnwrap(coord.scenarioOutcome())) { _ in }.environment(gm), "results-defeat")
    }
}
