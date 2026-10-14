import Foundation

/// New classes and the events that come with them (GH p.44–45): unlocking a class shuffles its
/// city and road event into the decks, and so does retiring a character of a class (its
/// retirement event).
extension GameState {

    /// Unlock a class, logging how; its unlock events join the decks. Returns false when the
    /// class was already unlocked: the party then gets a random item design and a random side
    /// scenario instead, however the box would have been opened (p.48, FAQ).
    @discardableResult
    func unlockClass(_ name: String, edition: String, how: String, labels: EditionDataStore) -> Bool {
        let key = "\(edition)-\(name)"
        guard !unlockedCharacters.contains(key) else {
            var gained: [String] = []
            if let item = ItemManager.drawRandomItem(game: self, editionStore: labels) {
                unlockedItems.insert("\(item.edition)-\(item.id)")
                gained.append("item design \(item.name)")
            }
            if let scenario = ScenarioManager.drawRandomScenario(game: self, editionStore: labels) {
                manualScenarios.insert(scenario.id)
                gained.append("scenario #\(scenario.index) \(scenario.name)")
            }
            if !gained.isEmpty {
                campaignLog.append(CampaignLogEntry(
                    type: .itemAcquired,
                    message: "\(GameText.className(name, edition: edition, labels: labels)) was already unlocked: \(gained.joined(separator: " and ")) instead",
                    details: how))
            }
            return false
        }
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

extension GameState {
    /// Open a sealed envelope of the game box (once): it is recorded and logged. Envelope X
    /// holds the Bladeswarm, a class not in the game's data, so nothing more is unlocked.
    func openEnvelope(_ envelope: String, how: String) {
        guard events.openedEnvelopes.insert(envelope).inserted else { return }
        campaignLog.append(CampaignLogEntry(type: .envelopeOpened, message: "Opened Envelope \(envelope)",
                                            details: "By \(how). Its contents are not in this game's data: open the envelope in the box."))
    }
}
