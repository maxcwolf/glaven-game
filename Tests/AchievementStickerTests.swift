import XCTest
@testable import GlavenGameLib

/// Tests for achievement sticker rendering on the world map.
final class AchievementStickerTests: XCTestCase {

    // MARK: - Unit Tests: Sticker Building

    func testBuild_noAchievements_noStickers() {
        let stickers = AchievementSticker.build(
            globalAchievements: [],
            partyAchievements: [],
            scenarios: [],
            completedScenarios: [],
            edition: "gh"
        )
        XCTAssertTrue(stickers.isEmpty)
    }

    func testBuild_earnedGlobalAchievement_placedNearScenario() {
        var coords = WorldMapCoordinates()
        coords.x = 1000; coords.y = 500; coords.width = 180; coords.height = 140
        var rewards = ScenarioRewards()
        rewards.globalAchievements = ["the-drake-slain"]
        let scenario = makeScenarioData(index: "34", name: "Test", edition: "gh",
                                     rewards: rewards, coordinates: coords)

        let stickers = AchievementSticker.build(
            globalAchievements: ["the-drake-slain"],
            partyAchievements: [],
            scenarios: [scenario],
            completedScenarios: ["gh-34"],
            edition: "gh"
        )

        XCTAssertEqual(stickers.count, 1)
        let sticker = stickers[0]
        XCTAssertEqual(sticker.name, "the-drake-slain")
        XCTAssertTrue(sticker.isGlobal)
        XCTAssertEqual(sticker.displayName, "The Drake Slain")
        // Should be centered horizontally on the scenario
        XCTAssertEqual(sticker.x, 1090, "Centered on scenario: 1000 + 180/2")
        // Should be below the scenario tile
        XCTAssertEqual(sticker.y, 655, "Below scenario: 500 + 140 + 15")
    }

    func testBuild_earnedPartyAchievement() {
        var coords = WorldMapCoordinates()
        coords.x = 500; coords.y = 300; coords.width = 100; coords.height = 80
        var rewards = ScenarioRewards()
        rewards.partyAchievements = ["first-steps"]
        let scenario = makeScenarioData(index: "1", name: "Test", edition: "gh",
                                     rewards: rewards, coordinates: coords)

        let stickers = AchievementSticker.build(
            globalAchievements: [],
            partyAchievements: ["first-steps"],
            scenarios: [scenario],
            completedScenarios: ["gh-1"],
            edition: "gh"
        )

        XCTAssertEqual(stickers.count, 1)
        XCTAssertFalse(stickers[0].isGlobal)
        XCTAssertEqual(stickers[0].displayName, "First Steps")
    }

    func testBuild_unearnedAchievement_noSticker() {
        var coords = WorldMapCoordinates()
        coords.x = 500; coords.y = 300; coords.width = 100; coords.height = 80
        var rewards = ScenarioRewards()
        rewards.globalAchievements = ["the-drake-slain"]
        let scenario = makeScenarioData(index: "34", name: "Test", edition: "gh",
                                     rewards: rewards, coordinates: coords)

        let stickers = AchievementSticker.build(
            globalAchievements: [],  // Not earned
            partyAchievements: [],
            scenarios: [scenario],
            completedScenarios: ["gh-34"],
            edition: "gh"
        )

        XCTAssertTrue(stickers.isEmpty, "Unearned achievement should not produce a sticker")
    }

    func testBuild_scenarioNotCompleted_noSticker() {
        var coords = WorldMapCoordinates()
        coords.x = 500; coords.y = 300; coords.width = 100; coords.height = 80
        var rewards = ScenarioRewards()
        rewards.globalAchievements = ["the-drake-slain"]
        let scenario = makeScenarioData(index: "34", name: "Test", edition: "gh",
                                     rewards: rewards, coordinates: coords)

        let stickers = AchievementSticker.build(
            globalAchievements: ["the-drake-slain"],
            partyAchievements: [],
            scenarios: [scenario],
            completedScenarios: [],  // Not completed
            edition: "gh"
        )

        XCTAssertTrue(stickers.isEmpty, "Achievement from uncompleted scenario should not show")
    }

    func testBuild_noDuplicateStickers() {
        // Same achievement granted by multiple scenarios — only one sticker
        var coords1 = WorldMapCoordinates()
        coords1.x = 100; coords1.y = 100; coords1.width = 100; coords1.height = 80
        var rewards1 = ScenarioRewards()
        rewards1.globalAchievements = ["ancient-technology"]
        let s1 = makeScenarioData(index: "23", name: "S23", edition: "gh",
                               rewards: rewards1, coordinates: coords1)

        var coords2 = WorldMapCoordinates()
        coords2.x = 500; coords2.y = 500; coords2.width = 100; coords2.height = 80
        var rewards2 = ScenarioRewards()
        rewards2.globalAchievements = ["ancient-technology"]
        let s2 = makeScenarioData(index: "40", name: "S40", edition: "gh",
                               rewards: rewards2, coordinates: coords2)

        let stickers = AchievementSticker.build(
            globalAchievements: ["ancient-technology"],
            partyAchievements: [],
            scenarios: [s1, s2],
            completedScenarios: ["gh-23", "gh-40"],
            edition: "gh"
        )

        XCTAssertEqual(stickers.count, 1, "Same achievement should only produce one sticker")
    }

    // MARK: - E2E: Real GH Data

    func testBuild_withRealGHScenarios() {
        let editionStore = EditionDataStore()
        editionStore.loadAllEditions()
        let scenarios = editionStore.scenarios(for: "gh")

        // Simulate completing scenario 1 which grants "first-steps" party achievement
        let stickers = AchievementSticker.build(
            globalAchievements: [],
            partyAchievements: ["first-steps"],
            scenarios: scenarios,
            completedScenarios: ["gh-1"],
            edition: "gh"
        )

        XCTAssertEqual(stickers.count, 1)
        XCTAssertEqual(stickers[0].name, "first-steps")
        XCTAssertFalse(stickers[0].isGlobal)
        // Verify position is near scenario 1 (around 1525, 1045)
        XCTAssertGreaterThan(stickers[0].x, 1400)
        XCTAssertLessThan(stickers[0].x, 1650)
    }

    func testBuild_multipleAchievements_withRealData() {
        let editionStore = EditionDataStore()
        editionStore.loadAllEditions()
        let scenarios = editionStore.scenarios(for: "gh")

        let stickers = AchievementSticker.build(
            globalAchievements: ["the-power-of-enhancement", "the-drake-slain"],
            partyAchievements: ["first-steps", "dark-bounty"],
            scenarios: scenarios,
            completedScenarios: ["gh-1", "gh-6", "gh-14", "gh-34"],
            edition: "gh"
        )

        XCTAssertEqual(stickers.count, 4, "Should have 4 achievement stickers")
        let names = Set(stickers.map(\.name))
        XCTAssertTrue(names.contains("the-power-of-enhancement"))
        XCTAssertTrue(names.contains("the-drake-slain"))
        XCTAssertTrue(names.contains("first-steps"))
        XCTAssertTrue(names.contains("dark-bounty"))
    }

    // MARK: - Unit Tests: Display Name Formatting

    func testDisplayName_formatting() {
        var coords = WorldMapCoordinates()
        coords.x = 100; coords.y = 100; coords.width = 100; coords.height = 80
        var rewards = ScenarioRewards()
        rewards.globalAchievements = ["the-edge-of-darkness"]
        let scenario = makeScenarioData(index: "29", name: "Test", edition: "gh",
                                     rewards: rewards, coordinates: coords)

        let stickers = AchievementSticker.build(
            globalAchievements: ["the-edge-of-darkness"],
            partyAchievements: [],
            scenarios: [scenario],
            completedScenarios: ["gh-29"],
            edition: "gh"
        )

        XCTAssertEqual(stickers[0].displayName, "The Edge Of Darkness")
    }
}

// Helper to create test ScenarioData
func makeScenarioData(index: String, name: String, edition: String,
                               rewards: ScenarioRewards? = nil,
                               coordinates: WorldMapCoordinates? = nil) -> ScenarioData {
    let json: [String: Any] = [
        "index": index,
        "name": name,
        "edition": edition
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)
    var scenario = try! JSONDecoder().decode(ScenarioData.self, from: data)
    scenario.rewards = rewards
    scenario.coordinates = coordinates
    return scenario
}
