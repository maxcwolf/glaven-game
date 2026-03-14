import XCTest
@testable import GlavenGameLib

/// Tests for city/road event card system.
/// Rulebook p.37-38: "Before every scenario, characters must draw and resolve
///  a city event. If traveling to a scenario, also draw a road event."
final class EventCardTests: XCTestCase {

    // MARK: - Unit: Event Data Loading

    func testEventDataLoads() {
        let store = EditionDataStore()
        store.loadAllEditions()
        let events = store.events(for: "gh")
        XCTAssertGreaterThan(events.count, 100, "Should load 150 GH events")
    }

    func testEventDataHasCityAndRoad() {
        let store = EditionDataStore()
        store.loadAllEditions()
        let events = store.events(for: "gh")
        let city = events.filter { $0.type == "city" }
        let road = events.filter { $0.type == "road" }
        XCTAssertGreaterThan(city.count, 50, "Should have 80+ city events")
        XCTAssertGreaterThan(road.count, 50, "Should have 60+ road events")
    }

    func testEventDataHasNarrativeAndOptions() {
        let store = EditionDataStore()
        store.loadAllEditions()
        let events = store.events(for: "gh")
        let first = events.first!
        XCTAssertFalse(first.narrative?.isEmpty ?? true, "Event should have narrative text")
        XCTAssertNotNil(first.options, "Event should have options")
        XCTAssertGreaterThanOrEqual(first.options?.count ?? 0, 2, "Event should have at least 2 options")
    }

    // MARK: - Unit: Event Card Manager

    func testDrawEvent_returnsEvent() {
        let t = TestGame()
        let ecm = EventCardManager(game: t.game, editionStore: t.editionStore)

        let event = ecm.drawEvent(type: "city")
        XCTAssertNotNil(event, "Should draw a city event")
        XCTAssertEqual(event?.type, "city")
    }

    func testDrawEvent_marksAsDrawn() {
        let t = TestGame()
        let ecm = EventCardManager(game: t.game, editionStore: t.editionStore)

        let totalBefore = ecm.remainingCount(type: "city")
        _ = ecm.drawEvent(type: "city")
        let totalAfter = ecm.remainingCount(type: "city")

        XCTAssertEqual(totalAfter, totalBefore - 1, "Drawing reduces remaining count by 1")
    }

    func testDrawEvent_noDuplicates() {
        let t = TestGame()
        let ecm = EventCardManager(game: t.game, editionStore: t.editionStore)

        var drawnIds = Set<String>()
        for _ in 0..<10 {
            if let event = ecm.drawEvent(type: "road") {
                XCTAssertFalse(drawnIds.contains(event.cardId), "Should not draw same event twice")
                drawnIds.insert(event.cardId)
            }
        }
        XCTAssertEqual(drawnIds.count, 10, "Should draw 10 unique events")
    }

    func testReturnToDeck_makesEventAvailableAgain() {
        let t = TestGame()
        let ecm = EventCardManager(game: t.game, editionStore: t.editionStore)

        let countBefore = ecm.remainingCount(type: "city")
        let event = ecm.drawEvent(type: "city")!
        XCTAssertEqual(ecm.remainingCount(type: "city"), countBefore - 1)

        ecm.returnToDeck(event)
        XCTAssertEqual(ecm.remainingCount(type: "city"), countBefore, "Return restores count")
    }

    func testRemainingCount_separateForCityAndRoad() {
        let t = TestGame()
        let ecm = EventCardManager(game: t.game, editionStore: t.editionStore)

        let cityBefore = ecm.remainingCount(type: "city")
        let roadBefore = ecm.remainingCount(type: "road")

        _ = ecm.drawEvent(type: "city")

        XCTAssertEqual(ecm.remainingCount(type: "city"), cityBefore - 1)
        XCTAssertEqual(ecm.remainingCount(type: "road"), roadBefore, "Road count unaffected by city draw")
    }

    // MARK: - Unit: Pending Event Type

    func testPendingEventType_roadScenario() {
        let t = TestGame()
        let ecm = EventCardManager(game: t.game, editionStore: t.editionStore)

        // Scenario with eventType "road"
        let scenarios = t.editionStore.scenarios(for: "gh")
        let roadScenario = scenarios.first(where: { $0.eventType == "road" })
        XCTAssertNotNil(roadScenario, "Should have road event scenarios in GH data")

        let eventType = ecm.pendingEventType(for: roadScenario)
        XCTAssertEqual(eventType, "road")
    }

    func testPendingEventType_nonRoadScenario() {
        let t = TestGame()
        let ecm = EventCardManager(game: t.game, editionStore: t.editionStore)

        let scenarios = t.editionStore.scenarios(for: "gh")
        let nonRoadScenario = scenarios.first(where: { $0.eventType == nil && $0.isInitial != true })

        if let scenario = nonRoadScenario {
            let eventType = ecm.pendingEventType(for: scenario)
            XCTAssertEqual(eventType, "city", "Non-road, non-initial scenario should get city event")
        }
    }

    func testPendingEventType_initialScenario() {
        let t = TestGame()
        let ecm = EventCardManager(game: t.game, editionStore: t.editionStore)

        let scenarios = t.editionStore.scenarios(for: "gh")
        let initialScenario = scenarios.first(where: { $0.isInitial })

        if let scenario = initialScenario {
            let eventType = ecm.pendingEventType(for: scenario)
            XCTAssertNil(eventType, "Initial scenario should not trigger an event")
        }
    }

    // MARK: - E2E: Scenario Sets Pending Event

    func testE2E_setScenario_setsPendingEventType() {
        let t = TestGame()
        t.addCharacter()

        let scenarios = t.editionStore.scenarios(for: "gh")
        let roadScenario = scenarios.first(where: { $0.eventType == "road" })!

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.setScenario(roadScenario)

        XCTAssertEqual(t.game.pendingEventType, "road",
                       "Setting road scenario should set pendingEventType to 'road'")
    }

    func testE2E_setInitialScenario_noPendingEvent() {
        let t = TestGame()
        t.addCharacter()

        let scenarios = t.editionStore.scenarios(for: "gh")
        let initialScenario = scenarios.first(where: { $0.isInitial })!

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.setScenario(initialScenario)

        XCTAssertNil(t.game.pendingEventType,
                     "Initial scenario should not have pending event")
    }

    func testE2E_drawAndResolveEvent() {
        let t = TestGame()
        t.addCharacter()
        let ecm = EventCardManager(game: t.game, editionStore: t.editionStore)

        // Set a road scenario
        let scenarios = t.editionStore.scenarios(for: "gh")
        let roadScenario = scenarios.first(where: { $0.eventType == "road" })!

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.setScenario(roadScenario)

        XCTAssertEqual(t.game.pendingEventType, "road")

        // Draw the road event
        let event = ecm.drawEvent(type: "road")
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.type, "road")

        // Clear pending after resolving
        t.game.pendingEventType = nil
        XCTAssertNil(t.game.pendingEventType)
    }

    // MARK: - E2E: Deck State Persistence

    func testE2E_drawnEventsPersistedInGameState() {
        let t = TestGame()
        let ecm = EventCardManager(game: t.game, editionStore: t.editionStore)

        _ = ecm.drawEvent(type: "city")
        _ = ecm.drawEvent(type: "city")
        _ = ecm.drawEvent(type: "road")

        XCTAssertEqual(t.game.drawnCityEvents.count, 2)
        XCTAssertEqual(t.game.drawnRoadEvents.count, 1)
    }
}
