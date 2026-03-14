import Foundation

/// Auto-tracks personal quest progress and checks for completion.
/// Called after each scenario completion to update progress counters
/// for requirements that have `autotrack` fields.
enum PersonalQuestEvaluator {

    /// Update a character's personal quest progress based on current game state.
    /// Returns true if the quest is now complete (all requirements met).
    @discardableResult
    static func updateProgress(
        character: GameCharacter,
        game: GameState,
        editionStore: EditionDataStore
    ) -> Bool {
        guard let questId = character.personalQuest,
              let quest = editionStore.personalQuest(cardId: questId, edition: character.edition) else {
            return false
        }

        let requirements = quest.requirements
        if requirements.isEmpty { return false }

        // Ensure progress array matches requirements count
        while character.personalQuestProgress.count < requirements.count {
            character.personalQuestProgress.append(0)
        }

        // Update each auto-trackable requirement
        for (i, req) in requirements.enumerated() {
            guard let autotrack = req.autotrack else { continue }

            // Check if this requirement has prerequisites
            if let prereqs = req.requires {
                let allPrereqsMet = prereqs.allSatisfy { prereqIdx in
                    let idx = prereqIdx - 1  // 1-based index
                    guard idx >= 0, idx < requirements.count, idx < character.personalQuestProgress.count else { return false }
                    return character.personalQuestProgress[idx] >= requirements[idx].counterValue
                }
                if !allPrereqsMet { continue }
            }

            let value = evaluateAutotrack(autotrack, character: character, game: game, editionStore: editionStore)
            character.personalQuestProgress[i] = min(value, req.counterValue)
        }

        // Check if all requirements are met
        return isComplete(character: character, quest: quest)
    }

    /// Check if a personal quest is fully complete.
    static func isComplete(character: GameCharacter, quest: PersonalQuestData) -> Bool {
        let requirements = quest.requirements
        if requirements.isEmpty { return false }

        for (i, req) in requirements.enumerated() {
            let progress = i < character.personalQuestProgress.count ? character.personalQuestProgress[i] : 0
            if progress < req.counterValue { return false }
        }
        return true
    }

    // MARK: - Auto-track Evaluation

    private static func evaluateAutotrack(_ autotrack: String, character: GameCharacter, game: GameState, editionStore: EditionDataStore) -> Int {
        let parts = autotrack.split(separator: ":", maxSplits: 1).map(String.init)
        let trackType = parts[0]
        let trackValue = parts.count > 1 ? parts[1] : ""

        switch trackType {
        case "gold":
            return character.loot

        case "scenariosCompleted":
            return game.completedScenarios.count

        case "battleGoals":
            return character.battleGoalProgress

        case "exhaustedSelf":
            // Count times this character has been exhausted — tracked in stats
            // For now, approximate from scenario stats if available
            return 0  // Needs cumulative tracking across scenarios

        case "exhaustedChars":
            // Count total exhaustions of OTHER characters
            return 0  // Needs cumulative tracking

        case "scenario":
            // Check if any of the specified scenarios are completed
            let scenarioIndices = trackValue.split(separator: "|").map(String.init)
            let completed = scenarioIndices.filter { idx in
                game.completedScenarios.contains("\(character.edition)-\(idx)")
            }
            return completed.count

        case "itemType":
            // Count items owned in specific slot type(s)
            let slots = trackValue.split(separator: "|").map(String.init)
            var count = 0
            for itemKey in character.items {
                // itemKey format: "edition-id"
                let parts = itemKey.split(separator: "-", maxSplits: 1)
                guard parts.count == 2, let id = Int(parts[1]) else { continue }
                let edition = String(parts[0])
                if let item = editionStore.itemData(id: id, edition: edition) {
                    if slots.contains(item.slot.rawValue) {
                        count += 1
                    }
                }
            }
            return count

        case "item":
            // Check if character owns a specific item
            let itemId = trackValue
            let hasItem = character.items.contains(where: { $0.hasSuffix("-\(itemId)") })
            return hasItem ? 1 : 0

        case "sideScenarios":
            // Count completed side scenarios (non-main, non-conclusion)
            // Approximate: count all completed scenarios
            return game.completedScenarios.count

        case "bossScenarios":
            // Needs scenario data to identify which are boss scenarios
            return 0  // Needs cross-reference with scenario data

        case "donatedGold":
            // Needs tracking of gold donated to sanctuary
            return 0  // Needs cumulative tracking

        case "retiredChars":
            return game.retiredCharacters.count

        default:
            return 0
        }
    }
}
