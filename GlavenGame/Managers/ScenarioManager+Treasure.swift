import Foundation

/// Looting numbered treasure tiles (GH p.28 / p.43).
extension ScenarioManager {

    /// Campaign key for a numbered treasure of the current scenario.
    func treasureKey(_ index: String) -> String? {
        guard let scenario = game.scenario else { return nil }
        return "\(scenario.data.edition)-\(scenario.data.index)-\(index)"
    }

    func isTreasureLooted(_ index: String) -> Bool {
        treasureKey(index).map { game.lootedTreasures.contains($0) } ?? false
    }

    /// Loot a numbered treasure tile for `character`: the reward from the treasure index goes to
    /// the looting character. A numbered treasure can only be looted once per campaign; a
    /// non-numbered (goal) treasure has no index reward. Returns a description of the reward.
    @discardableResult
    func lootTreasure(_ index: String, by character: GameCharacter?) -> String? {
        guard let scenario = game.scenario, let key = treasureKey(index) else { return nil }
        guard let number = Int(index) else { return "Goal treasure" }
        guard !game.lootedTreasures.contains(key) else { return "Treasure #\(index) was already looted" }

        onBeforeMutate?()
        let edition = scenario.data.edition
        game.lootedTreasures.insert(key)
        if let character { scenarioStatsManager?.recordTreasure(by: character.name) }
        game.campaignLog.append(CampaignLogEntry(
            type: .treasureLooted,
            message: "Looted treasure \(index) in #\(scenario.data.index) \(scenario.data.name)"
        ))

        guard let reward = editionStore.treasureReward(index: number, edition: edition) else { return nil }
        let recipient = character ?? game.activeCharacters.first
        var drawn: [String] = []
        for part in reward.split(separator: "|").map(String.init) {
            if let name = applyTreasureReward(part, edition: edition, to: recipient) { drawn.append(name) }
        }
        let label = editionStore.treasureLabel(rewardString: reward, edition: edition)
        return drawn.isEmpty ? label : "\(label) (\(drawn.joined(separator: ", ")))"
    }

    /// Apply one part of a treasure's reward; returns what a random draw turned up, to name it.
    @discardableResult
    private func applyTreasureReward(_ reward: String, edition: String, to character: GameCharacter?) -> String? {
        let components = reward.split(separator: ":", maxSplits: 1).map(String.init)
        let type = components[0]
        let value = components.count > 1 ? components[1] : nil
        let amount = value.flatMap { Int($0) }

        switch type {
        case "gold", "goldFh":
            if let amount { character?.loot += amount }
        case "experience", "experienceFh":
            if let amount { character?.experience += amount }
        case "item", "itemFh":
            // A specific item is taken from the unique items and goes to the looting character
            // (p.43); if they already own it, it is sold to the city's supply instead.
            for id in (value ?? "").split(separator: "+").compactMap({ Int($0) }) {
                let itemKey = "\(edition)-\(id)"
                if let character, !character.items.contains(itemKey) {
                    character.items.append(itemKey)
                    editionStore.fitLoadout(character, unlimited: game.tableRules.bringEveryItem)
                } else {
                    game.unlockedItems.insert(itemKey)
                }
            }
        case "itemDesign":
            if let amount { game.unlockedItems.insert("\(edition)-\(amount)") }
        case "battleGoal":
            if let amount { character?.battleGoalProgress += amount }
        case "damage":
            if let amount, let character {
                character.health = max(0, character.health - amount)
            }
        case "heal":
            if let amount, let character {
                character.health = min(character.maxHealth, character.health + amount)
            }
        case "condition":
            for name in (value ?? "").split(separator: "+") {
                if let condition = ConditionName(rawValue: String(name)),
                   let character, !character.immunities.contains(condition),
                   !character.entityConditions.contains(where: { $0.name == condition }) {
                    character.entityConditions.append(EntityCondition(name: condition))
                }
            }
        case "partyAchievement":
            if let value { game.partyAchievements.insert(value) }
        case "randomItemDesign":
            // A random item design joins the city's supply (p.43).
            guard let item = ItemManager.drawRandomItem(game: game, editionStore: editionStore) else { return nil }
            game.unlockedItems.insert("\(item.edition)-\(item.id)")
            return item.name
        case "randomScenario":
            // A random side scenario is unlocked (p.43).
            guard let scenario = drawRandomScenario() else { return nil }
            game.manualScenarios.insert(scenario.id)
            return "#\(scenario.index) \(scenario.name)"
        default:
            break
        }
        return nil
    }
}
