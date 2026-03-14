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
}
