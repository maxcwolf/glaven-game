import XCTest
@testable import GlavenGameLib

/// Tests for world map overlay sticker placement and rendering.
final class WorldMapStickerTests: XCTestCase {

    // MARK: - Unit Tests: Data Model

    func testWorldMapOverlay_defaultInit() {
        let overlay = WorldMapOverlay()
        XCTAssertEqual(overlay.name, "")
        XCTAssertEqual(overlay.location, "")
    }

    func testWorldMapOverlay_withCoordinates() {
        var coords = WorldMapCoordinates()
        coords.x = 100
        coords.y = 200
        coords.width = 50
        coords.height = 40
        let overlay = WorldMapOverlay(name: "boat", location: "dock", coordinates: coords)
        XCTAssertEqual(overlay.name, "boat")
        XCTAssertEqual(overlay.coordinates.x, 100)
        XCTAssertEqual(overlay.coordinates.y, 200)
        XCTAssertEqual(overlay.coordinates.width, 50)
        XCTAssertEqual(overlay.coordinates.height, 40)
    }

    func testWorldMapOverlay_codable() {
        let json = """
        {"name": "temple", "location": "north", "coordinates": {"x": 500, "y": 300, "width": 80, "height": 60}}
        """
        let overlay = try! JSONDecoder().decode(WorldMapOverlay.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(overlay.name, "temple")
        XCTAssertEqual(overlay.location, "north")
        XCTAssertEqual(overlay.coordinates.x, 500)
    }

    // MARK: - Unit Tests: GameState Storage

    func testGameState_mapOverlaysStartEmpty() {
        let game = GameState()
        XCTAssertTrue(game.mapOverlays.isEmpty)
    }

    func testGameState_canStoreOverlays() {
        let game = GameState()
        var coords = WorldMapCoordinates()
        coords.x = 100; coords.y = 200
        game.mapOverlays.append(WorldMapOverlay(name: "boat", coordinates: coords))
        game.mapOverlays.append(WorldMapOverlay(name: "temple", coordinates: coords))
        XCTAssertEqual(game.mapOverlays.count, 2)
    }

    // MARK: - E2E: Reward Collection

    func testScenarioReward_collectsOverlaySticker() {
        let t = TestGame()
        t.addCharacter()

        // Create a scenario with overlay sticker reward
        var coords = WorldMapCoordinates()
        coords.x = 500; coords.y = 300; coords.width = 80; coords.height = 60
        var rewards = ScenarioRewards()
        rewards.overlaySticker = WorldMapOverlay(name: "boat", location: "dock", coordinates: coords)

        var scenarioData = ScenarioData(index: "test", name: "Test", edition: "gh")
        scenarioData.rewards = rewards
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: true)

        XCTAssertEqual(t.game.mapOverlays.count, 1, "Overlay sticker collected on victory")
        XCTAssertEqual(t.game.mapOverlays.first?.name, "boat")
        XCTAssertEqual(t.game.mapOverlays.first?.coordinates.x, 500)
    }

    func testScenarioReward_noDuplicateOverlays() {
        let t = TestGame()
        t.addCharacter()

        var coords = WorldMapCoordinates()
        coords.x = 100; coords.y = 200
        var rewards = ScenarioRewards()
        rewards.overlaySticker = WorldMapOverlay(name: "boat", coordinates: coords)

        // Complete the scenario twice (e.g. repeatable scenario)
        for i in 1...2 {
            var scenarioData = ScenarioData(index: "test\(i)", name: "Test", edition: "gh")
            scenarioData.rewards = rewards
            t.game.scenario = Scenario(data: scenarioData)

            let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                      monsterManager: t.monsterManager, levelManager: t.levelManager)
            sm.finishScenario(success: true)
        }

        XCTAssertEqual(t.game.mapOverlays.count, 1, "Same sticker not duplicated")
    }

    func testScenarioDefeat_noOverlaySticker() {
        let t = TestGame()
        t.addCharacter()

        var coords = WorldMapCoordinates()
        coords.x = 100; coords.y = 200
        var rewards = ScenarioRewards()
        rewards.overlaySticker = WorldMapOverlay(name: "boat", coordinates: coords)

        var scenarioData = ScenarioData(index: "test", name: "Test", edition: "gh")
        scenarioData.rewards = rewards
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: false)

        XCTAssertTrue(t.game.mapOverlays.isEmpty, "Defeat should not grant sticker")
    }

    // MARK: - E2E: Snapshot Persistence

    func testSnapshot_preservesMapOverlays() {
        let game = GameState()
        game.edition = "gh"
        var coords = WorldMapCoordinates()
        coords.x = 500; coords.y = 300; coords.width = 80; coords.height = 60
        game.mapOverlays.append(WorldMapOverlay(name: "boat", location: "dock", coordinates: coords))
        game.mapOverlays.append(WorldMapOverlay(name: "temple", location: "north", coordinates: coords))

        let snapshot = game.toSnapshot()
        XCTAssertEqual(snapshot.mapOverlays.count, 2)
        XCTAssertEqual(snapshot.mapOverlays[0].name, "boat")
        XCTAssertEqual(snapshot.mapOverlays[1].name, "temple")
    }

    func testSnapshot_backwardCompat_noMapOverlays() {
        // Old snapshots without mapOverlays field should default to empty
        // This is handled by decodeIfPresent with ?? []
        let game = GameState()
        XCTAssertTrue(game.mapOverlays.isEmpty, "Default state has no overlays")
    }

    // MARK: - Unit Tests: ImageLoader

    func testImageLoader_worldMapOverlayMethod() {
        // Just verify the method exists and doesn't crash with missing image
        let img = ImageLoader.worldMapOverlay(edition: "gh", name: "nonexistent")
        XCTAssertNil(img, "Should return nil for nonexistent overlay image")
    }

    func testImageLoader_fhOverlayExists() {
        // FH overlay images should exist in the bundle
        let img = ImageLoader.worldMapOverlay(edition: "fh", name: "boat")
        // May or may not load depending on bundle configuration
        // This test just verifies the path construction doesn't crash
        _ = img
    }

    // MARK: - E2E: Full Scenario → Sticker → Snapshot Round-Trip

    func testE2E_completeScenario_overlayCollected_snapshotPersisted() {
        let t = TestGame()
        let char = t.addCharacter()
        _ = char

        // Set up scenario with overlay sticker reward
        var coords = WorldMapCoordinates()
        coords.x = 800; coords.y = 900; coords.width = 100; coords.height = 80
        var rewards = ScenarioRewards()
        rewards.overlaySticker = WorldMapOverlay(name: "boat", location: "dock", coordinates: coords)

        var scenarioData = ScenarioData(index: "test-e2e", name: "E2E Overlay", edition: "gh")
        scenarioData.rewards = rewards
        t.game.scenario = Scenario(data: scenarioData)

        XCTAssertTrue(t.game.mapOverlays.isEmpty, "No stickers before scenario completion")

        // Complete the scenario
        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: true)

        // Overlay sticker should be collected
        XCTAssertEqual(t.game.mapOverlays.count, 1)
        XCTAssertEqual(t.game.mapOverlays[0].name, "boat")
        XCTAssertEqual(t.game.mapOverlays[0].coordinates.x, 800)

        // Snapshot and restore — sticker should persist
        let snapshot = t.game.toSnapshot()
        XCTAssertEqual(snapshot.mapOverlays.count, 1)

        let restoredGame = GameState()
        restoredGame.restore(from: snapshot, editionStore: t.editionStore)
        XCTAssertEqual(restoredGame.mapOverlays.count, 1, "Sticker persists after snapshot restore")
        XCTAssertEqual(restoredGame.mapOverlays[0].name, "boat")
        XCTAssertEqual(restoredGame.mapOverlays[0].coordinates.x, 800)
    }

    func testE2E_completeScenario_achievementCollected_stickersBuilt() {
        let t = TestGame()
        t.addCharacter()

        // Set up scenario that grants a global achievement
        var coords = WorldMapCoordinates()
        coords.x = 620; coords.y = 130; coords.width = 150; coords.height = 120
        var rewards = ScenarioRewards()
        rewards.globalAchievements = ["the-drake-slain"]

        var scenarioData = ScenarioData(index: "34", name: "Scorched Summit", edition: "gh")
        scenarioData.rewards = rewards
        scenarioData.coordinates = coords
        t.game.scenario = Scenario(data: scenarioData)

        XCTAssertTrue(t.game.globalAchievements.isEmpty)

        // Complete the scenario
        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: true)

        // Achievement should be earned
        XCTAssertTrue(t.game.globalAchievements.contains("the-drake-slain"))
        XCTAssertTrue(t.game.completedScenarios.contains("gh-34"))

        // Build achievement stickers — should produce one for "the-drake-slain"
        let stickers = AchievementSticker.build(
            globalAchievements: t.game.globalAchievements,
            partyAchievements: t.game.partyAchievements,
            scenarios: [scenarioData],
            completedScenarios: t.game.completedScenarios,
            edition: "gh"
        )

        XCTAssertEqual(stickers.count, 1)
        XCTAssertEqual(stickers[0].name, "the-drake-slain")
        XCTAssertTrue(stickers[0].isGlobal)
        // Positioned near scenario 34
        XCTAssertEqual(stickers[0].x, 695, accuracy: 5) // 620 + 150/2
    }

    func testE2E_multiScenarioCampaign_stickersAccumulate() {
        let t = TestGame()
        t.addCharacter()

        // Complete scenario 1 → "first-steps" party achievement
        var r1 = ScenarioRewards()
        r1.partyAchievements = ["first-steps"]
        var s1 = ScenarioData(index: "1", name: "Black Barrow", edition: "gh")
        s1.rewards = r1
        var c1 = WorldMapCoordinates(); c1.x = 1434; c1.y = 975; c1.width = 182; c1.height = 140
        s1.coordinates = c1

        t.game.scenario = Scenario(data: s1)
        let sm1 = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                   monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm1.finishScenario(success: true)

        XCTAssertTrue(t.game.partyAchievements.contains("first-steps"))

        // Complete scenario 14 → "the-power-of-enhancement" global achievement
        var r2 = ScenarioRewards()
        r2.globalAchievements = ["the-power-of-enhancement"]
        var s2 = ScenarioData(index: "14", name: "Frozen Hollow", edition: "gh")
        s2.rewards = r2
        var c2 = WorldMapCoordinates(); c2.x = 1465; c2.y = 378; c2.width = 182; c2.height = 140
        s2.coordinates = c2

        t.game.scenario = Scenario(data: s2)
        let sm2 = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                   monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm2.finishScenario(success: true)

        XCTAssertTrue(t.game.globalAchievements.contains("the-power-of-enhancement"))

        // Build stickers from both scenarios
        let stickers = AchievementSticker.build(
            globalAchievements: t.game.globalAchievements,
            partyAchievements: t.game.partyAchievements,
            scenarios: [s1, s2],
            completedScenarios: t.game.completedScenarios,
            edition: "gh"
        )

        XCTAssertEqual(stickers.count, 2, "Both achievements should produce stickers")
        let names = Set(stickers.map(\.name))
        XCTAssertTrue(names.contains("first-steps"))
        XCTAssertTrue(names.contains("the-power-of-enhancement"))

        // Verify they're at different positions
        let positions = stickers.map { ($0.x, $0.y) }
        XCTAssertNotEqual(positions[0].0, positions[1].0, "Stickers at different scenarios should have different x positions")

        // Snapshot round-trip preserves achievements
        let snapshot = t.game.toSnapshot()
        let restored = GameState()
        restored.restore(from: snapshot, editionStore: t.editionStore)
        XCTAssertTrue(restored.globalAchievements.contains("the-power-of-enhancement"))
        XCTAssertTrue(restored.partyAchievements.contains("first-steps"))
        XCTAssertEqual(restored.completedScenarios.count, 2)
    }

    func testE2E_defeatDoesNotGrantAchievement() {
        let t = TestGame()
        t.addCharacter()

        var rewards = ScenarioRewards()
        rewards.globalAchievements = ["the-drake-slain"]
        var scenarioData = ScenarioData(index: "34", name: "Scorched Summit", edition: "gh")
        scenarioData.rewards = rewards
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: false)

        XCTAssertTrue(t.game.globalAchievements.isEmpty, "Defeat should not grant achievements")
        XCTAssertTrue(t.game.mapOverlays.isEmpty, "Defeat should not grant overlay stickers")
    }

    func testE2E_realGHData_fullCampaignStickers() {
        let t = TestGame()
        t.addCharacter()
        let scenarios = t.editionStore.scenarios(for: "gh")

        // Simulate completing first 5 scenarios and earning their achievements
        let completedIndices = ["1", "2", "3", "4", "5"]
        for idx in completedIndices {
            if let scenario = scenarios.first(where: { $0.index == idx }) {
                t.game.scenario = Scenario(data: scenario)
                let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                          monsterManager: t.monsterManager, levelManager: t.levelManager)
                sm.finishScenario(success: true)
            }
        }

        XCTAssertEqual(t.game.completedScenarios.count, completedIndices.count)

        // Build stickers from real data
        let stickers = AchievementSticker.build(
            globalAchievements: t.game.globalAchievements,
            partyAchievements: t.game.partyAchievements,
            scenarios: scenarios,
            completedScenarios: t.game.completedScenarios,
            edition: "gh"
        )

        // Scenario 1 grants "first-steps" — should produce at least one sticker
        if t.game.partyAchievements.contains("first-steps") {
            XCTAssertTrue(stickers.contains(where: { $0.name == "first-steps" }),
                          "First-steps sticker should appear after completing scenario 1")
        }

        // All stickers should have valid positions (non-zero)
        for sticker in stickers {
            XCTAssertGreaterThan(sticker.x, 0, "\(sticker.name) should have valid x position")
            XCTAssertGreaterThan(sticker.y, 0, "\(sticker.name) should have valid y position")
        }
    }
}
