import Foundation

/// Personal quest progress (GH p.12, 44), counted from each character's campaign record after
/// every scenario. Requirements the game can't see — scenarios in a map region, enhancements,
/// kills with a particular item — are counted by hand on the character sheet.
enum PersonalQuestEvaluator {

    /// How a requirement is counted.
    enum Tracking: Equatable {
        /// From the data's `autotrack` field.
        case auto(String)
        /// Kills of these monsters (base names).
        case kills(Set<String>)
        case eliteKills
        case monsterTypes
        /// Won scenarios with "Crypt" in their name.
        case cryptScenarios
        /// Counted by hand.
        case manual
    }

    /// Requirements without `autotrack` that the campaign record can still count, by quest card
    /// and requirement (0-based).
    private static let trackedByRecord: [String: [Int: Tracking]] = [
        "510": [0: .cryptScenarios],
        "513": [0: .kills(["forest-imp"])],
        "515": [0: .kills(["bandit-guard", "bandit-archer", "cultist"])],
        "516": [0: .kills(["vermling-scout", "vermling-shaman"])],
        "517": [0: .monsterTypes],
        "523": [0: .kills(["flame-demon"]), 1: .kills(["frost-demon"]), 2: .kills(["wind-demon"]),
                3: .kills(["earth-demon"]), 4: .kills(["night-demon"]), 5: .kills(["sun-demon"])],
        "524": [0: .eliteKills],
        "533": [0: .kills(["ooze"]), 1: .kills(["lurker"]), 2: .kills(["spitting-drake"])],
    ]

    static func tracking(questId: String, index: Int, requirement: PersonalQuestRequirement) -> Tracking {
        if let auto = requirement.autotrack { return .auto(auto) }
        return trackedByRecord[questId]?[index] ?? .manual
    }

    /// Update a character's progress; returns whether the quest is complete.
    @discardableResult
    static func updateProgress(character: GameCharacter, game: GameState, editionStore: EditionDataStore) -> Bool {
        guard let questId = character.personalQuest,
              let quest = editionStore.personalQuest(cardId: questId, edition: character.edition) else { return false }
        let requirements = quest.requirements
        guard !requirements.isEmpty else { return false }
        while character.personalQuestProgress.count < requirements.count { character.personalQuestProgress.append(0) }

        for (i, req) in requirements.enumerated() {
            let how = tracking(questId: questId, index: i, requirement: req)
            guard how != .manual else { continue }
            // A requirement that follows another only counts once that one is met.
            if let prereqs = req.requires, !prereqs.allSatisfy({ index in
                let idx = index - 1
                return idx >= 0 && idx < requirements.count
                    && character.personalQuestProgress[idx] >= requirements[idx].counterValue
            }) { continue }
            let value = count(how, character: character, game: game, editionStore: editionStore)
            character.personalQuestProgress[i] = min(value, req.counterValue)
        }
        return isComplete(character: character, quest: quest)
    }

    static func isComplete(character: GameCharacter, quest: PersonalQuestData) -> Bool {
        let requirements = quest.requirements
        guard !requirements.isEmpty else { return false }
        return requirements.enumerated().allSatisfy { i, req in
            (i < character.personalQuestProgress.count ? character.personalQuestProgress[i] : 0) >= req.counterValue
        }
    }

    static func isComplete(character: GameCharacter, editionStore: EditionDataStore) -> Bool {
        guard let id = character.personalQuest,
              let quest = editionStore.personalQuest(cardId: id, edition: character.edition) else { return false }
        return isComplete(character: character, quest: quest)
    }

    // MARK: - Counting

    private static func count(_ how: Tracking, character: GameCharacter, game: GameState,
                              editionStore: EditionDataStore) -> Int {
        let record = character.record
        switch how {
        case .manual: return 0
        case .kills(let names): return names.reduce(0) { $0 + (record.kills[$1] ?? 0) }
        case .eliteKills: return record.eliteKills
        case .monsterTypes: return record.kills.filter { $0.value > 0 }.count
        case .cryptScenarios:
            return completed(record, editionStore).filter { $0.name.contains("Crypt") }.count
        case .auto(let autotrack):
            return countAuto(autotrack, character: character, game: game, editionStore: editionStore)
        }
    }

    /// The scenarios a character has won.
    private static func completed(_ record: CharacterRecord, _ store: EditionDataStore) -> [ScenarioData] {
        record.scenariosCompleted.compactMap { id in
            let parts = id.split(separator: "-", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            // Solo scenarios reuse the main scenarios' numbers; the main one is meant.
            return store.scenarios(for: parts[0]).first { $0.index == parts[1] && $0.solo == nil }
        }
    }

    private static func countAuto(_ autotrack: String, character: GameCharacter, game: GameState,
                                  editionStore: EditionDataStore) -> Int {
        let parts = autotrack.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        let record = character.record
        switch parts[0] {
        case "gold": return character.loot
        case "scenariosCompleted": return record.scenariosCompleted.count
        case "battleGoals": return character.battleGoalProgress
        case "exhaustedSelf": return record.timesExhausted
        case "exhaustedChars": return record.partyExhaustions
        case "scenario":
            let indices = value.split(separator: "|").map { "\(character.edition)-\($0)" }
            return indices.filter(game.completedScenarios.contains).count
        case "itemType":
            let slots = value.split(separator: "|").map(String.init)
            return character.items.filter { key in
                let parts = key.split(separator: "-", maxSplits: 1)
                guard parts.count == 2, let id = Int(parts[1]),
                      let item = editionStore.itemData(id: id, edition: String(parts[0])) else { return false }
                return slots.contains(item.slot.rawValue)
            }.count
        case "item":
            return character.items.contains { $0.hasSuffix("-\(value)") } ? 1 : 0
        case "sideScenarios":
            // Side scenarios are those numbered above 51 (the quest card says so).
            return completed(record, editionStore).filter { (Int($0.index) ?? 0) > 51 }.count
        case "bossScenarios":
            return completed(record, editionStore).filter { scenario in
                (scenario.monsters ?? []).contains { editionStore.monsterData(name: $0, edition: scenario.edition)?.isBoss == true }
            }.count
        case "donatedGold": return record.donatedGold
        case "retiredChars": return game.retiredCharacters.count
        default: return 0
        }
    }
}
