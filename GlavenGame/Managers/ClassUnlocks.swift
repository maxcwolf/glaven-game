import Foundation

/// New classes and the events that come with them (GH p.44–45): unlocking a class shuffles its
/// city and road event into the decks, and so does retiring a character of a class (its
/// retirement event).
extension GameState {

    /// Unlock a class, logging how; its unlock events join the decks. Returns false when the
    /// class was already unlocked.
    @discardableResult
    func unlockClass(_ name: String, edition: String, how: String, labels: EditionDataStore) -> Bool {
        let key = "\(edition)-\(name)"
        guard !unlockedCharacters.contains(key) else { return false }
        unlockedCharacters.insert(key)
        campaignLog.append(CampaignLogEntry(
            type: .characterUnlocked,
            message: "\(GameText.className(name, edition: edition, labels: labels)) unlocked",
            details: how))
        if let event = labels.characterData(name: name, edition: edition)?.unlockEvent {
            addClassEvent(event)
        }
        return true
    }

    /// A retiring character's class adds its retirement events to the decks.
    func addRetirementEvents(of className: String, edition: String, labels: EditionDataStore) {
        if let event = labels.characterData(name: className, edition: edition)?.retireEvent {
            addClassEvent(event)
        }
    }

    private func addClassEvent(_ id: String) {
        events.add(id, to: "city")
        events.add(id, to: "road")
    }
}
