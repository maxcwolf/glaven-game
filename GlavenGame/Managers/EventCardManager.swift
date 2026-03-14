import Foundation

/// Manages city and road event card decks.
/// Tracks which events have been drawn and provides random draws from remaining cards.
@Observable
final class EventCardManager {
    private let game: GameState
    private let editionStore: EditionDataStore

    init(game: GameState, editionStore: EditionDataStore) {
        self.game = game
        self.editionStore = editionStore
    }

    /// All events for the current edition, filtered by type.
    func events(type: String) -> [EventCardData] {
        let edition = game.edition ?? "gh"
        return editionStore.events(for: edition).filter { $0.type == type }
    }

    /// Draw a random undrawn event of the specified type.
    /// Returns nil if all events of that type have been drawn.
    func drawEvent(type: String) -> EventCardData? {
        let available = events(type: type).filter { event in
            let key = event.cardId
            switch type {
            case "city": return !game.drawnCityEvents.contains(key)
            case "road": return !game.drawnRoadEvents.contains(key)
            default: return true
            }
        }

        guard let event = available.randomElement() else { return nil }

        // Mark as drawn
        switch type {
        case "city": game.drawnCityEvents.insert(event.cardId)
        case "road": game.drawnRoadEvents.insert(event.cardId)
        default: break
        }

        return event
    }

    /// Return an event card to the deck (some options say "return to deck").
    func returnToDeck(_ event: EventCardData) {
        switch event.type {
        case "city": game.drawnCityEvents.remove(event.cardId)
        case "road": game.drawnRoadEvents.remove(event.cardId)
        default: break
        }
    }

    /// Number of remaining undrawn events of a type.
    func remainingCount(type: String) -> Int {
        let total = events(type: type).count
        switch type {
        case "city": return total - game.drawnCityEvents.count
        case "road": return total - game.drawnRoadEvents.count
        default: return total
        }
    }

    /// Determine what event type (if any) should be drawn before the current scenario.
    /// Per GH rules: city event every time, road event if scenario has eventType "road".
    func pendingEventType(for scenario: ScenarioData?) -> String? {
        guard let scenario = scenario else { return nil }
        // Road events: drawn when traveling to a scenario with eventType "road"
        if scenario.eventType == "road" {
            return "road"
        }
        // City events: drawn at the start of each scenario (unless first scenario)
        if !scenario.isInitial {
            return "city"
        }
        return nil
    }
}
