import XCTest
import SwiftUI
@testable import GlavenGameLib

/// A scenario won on the board applies the rewards the players chose on the results screen, and
/// the results screen lists every kind of reward.
@MainActor
final class BoardRewardChoiceTests: XCTestCase {

    private func winOnTheBoard(_ index: String, party: [String] = ["brute", "tinkerer"]) throws -> GameManager {
        let gm = try SaveAndContinueTestsSupport.manager()
        for name in party { gm.characterManager.addCharacter(name: name, edition: "gh") }
        let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
        gm.startScenarioOnBoard(data)
        gm.boardCoordinator.endReason = .enemiesDefeated
        gm.boardCoordinator.scenarioResult = .victory
        return gm
    }

    // MARK: - Choices reach the rewards

    func testTheChosenCharacterTakesTheItem() throws {
        let gm = try winOnTheBoard("53")
        let second = gm.game.characters[1]
        var choices = ScenarioRewardChoices()
        choices.itemRecipients["gh-114"] = [second.id]
        gm.boardCoordinator.confirmScenarioEnd(choices: choices)
        XCTAssertTrue(second.items.contains("gh-114"), "the second character took it")
        XCTAssertFalse(gm.game.characters[0].items.contains("gh-114"))
    }

    func testTheCollectiveGoldIsSplitAsChosen() throws {
        let gm = try winOnTheBoard("55")
        let (a, b) = (gm.game.characters[0], gm.game.characters[1])
        let (goldA, goldB) = (a.loot, b.loot)
        var choices = ScenarioRewardChoices()
        choices.collectiveGold = [a.id: 10, b.id: 0]
        gm.boardCoordinator.confirmScenarioEnd(choices: choices)
        XCTAssertEqual(a.loot - goldA, 10)
        XCTAssertEqual(b.loot - goldB, 0)
    }

    func testTheChosenLocationOpens() throws {
        let gm = try winOnTheBoard("13")
        var choices = ScenarioRewardChoices()
        choices.location = "17"
        gm.boardCoordinator.confirmScenarioEnd(choices: choices)
        XCTAssertTrue(gm.game.manualScenarios.contains("gh-17"))
        XCTAssertFalse(gm.game.manualScenarios.contains("gh-15"), "not the default")
    }

    /// The results screen starts from the same defaults as the old conclusion sheet, and won't
    /// finish until every coin of the collective gold is handed out.
    func testDefaultsAndTheGoldSplitRule() throws {
        let gm = try winOnTheBoard("55")
        let rewards = try XCTUnwrap(gm.game.scenario?.data.rewards)
        var choices = RewardChoicesView.defaultChoices(for: rewards, edition: "gh", manager: gm.scenarioManager)
        XCTAssertEqual(choices.collectiveGold.values.reduce(0, +), 10, "split evenly to start")
        XCTAssertTrue(RewardChoicesView.goldAssigned(choices, rewards: rewards, manager: gm.scenarioManager))
        choices.collectiveGold[gm.game.characters[0].id] = 0
        XCTAssertFalse(RewardChoicesView.goldAssigned(choices, rewards: rewards, manager: gm.scenarioManager))
    }

    // MARK: - The results screen says what they are

    func testTheResultsListEveryKindOfReward() throws {
        let checks: [(String, String)] = [
            ("53", "Item: "), ("55", "10 gold to share"), ("13", "Choose a location: #15"),
        ]
        for (index, expected) in checks {
            let gm = try winOnTheBoard(index)
            let rewards = try XCTUnwrap(gm.boardCoordinator.scenarioOutcome()).rewards
            XCTAssertTrue(rewards.contains { $0.hasPrefix(expected) }, "#\(index): \(rewards)")
            for line in rewards { XCTAssertEqual(PlayerTextTests.lint(line), [], line) }
        }
        // Item designs, checkmarks and class unlocks, wherever the data has them.
        let gm = try SaveAndContinueTestsSupport.manager()
        let scenarios = gm.editionStore.scenarios(for: "gh").filter { $0.solo == nil }
        let finders: [(String, (ScenarioRewards) -> Bool)] = [
            ("Item design: ", { !($0.itemDesigns ?? []).isEmpty }),
            ("battle goal checkmark", { $0.battleGoals != nil }),
            ("New class: ", { $0.unlockCharacter != nil }),
        ]
        for (expected, has) in finders {
            let data = try XCTUnwrap(scenarios.first { $0.rewards.map(has) ?? false }, "a scenario with \(expected)")
            let won = try winOnTheBoard(data.index)
            let rewards = try XCTUnwrap(won.boardCoordinator.scenarioOutcome()).rewards
            XCTAssertTrue(rewards.contains { $0.contains(expected) }, "#\(data.index): \(rewards)")
            for line in rewards { XCTAssertEqual(PlayerTextTests.lint(line), [], line) }
        }
    }

    /// `REWARD_RENDER_OUT=/tmp/r swift test --filter testRenderRewardChoices` renders the results
    /// screen with choices for #53 (an item) and #55 (gold to share).
    func testRenderRewardChoices() throws {
        guard let out = ProcessInfo.processInfo.environment["REWARD_RENDER_OUT"] else {
            throw XCTSkip("set REWARD_RENDER_OUT to render the screens")
        }
        GlavenFont.registerFonts()
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        for index in ["53", "55", "13"] {
            let gm = try winOnTheBoard(index)
            let view = ScenarioResultsView(outcome: try XCTUnwrap(gm.boardCoordinator.scenarioOutcome())) { _ in }
                .environment(gm).frame(width: 1376, height: 1032).background(Color(white: 0.2))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "\(out)/results-\(index).png"))
        }
    }
}
