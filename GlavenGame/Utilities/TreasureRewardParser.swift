import Foundation

/// Parses Angular-format treasure reward strings into human-readable labels.
///
/// Format: "type:value" or "type" — multiple rewards separated by "|"
/// Examples: "gold:15", "item:32", "randomItemDesign", "damage:5|condition:poison+wound"
enum TreasureRewardParser {

    static func parse(_ rewardString: String, edition: String, store: EditionDataStore) -> String {
        if rewardString == "G" { return "Goal" }

        let parts = rewardString.split(separator: "|").map(String.init)
        let labels = parts.map { parseSingle($0, edition: edition, store: store) }
        return labels.joined(separator: ", ")
    }

    private static func parseSingle(_ reward: String, edition: String, store: EditionDataStore) -> String {
        let components = reward.split(separator: ":", maxSplits: 1).map(String.init)
        let type = components[0]
        let value = components.count > 1 ? components[1] : nil

        switch type {
        case "gold", "goldFh":
            return "Gain \(value ?? "?") gold"
        case "experience", "experienceFh":
            return "Gain \(value ?? "?") XP"
        case "item", "itemFh":
            if let value = value {
                let itemIds = value.split(separator: "+").map(String.init)
                let names = itemIds.compactMap { idStr -> String? in
                    guard let id = Int(idStr) else { return nil }
                    if let item = store.itemData(id: id, edition: edition) {
                        return item.name
                    }
                    return "Item \(id)"
                }
                return "Gain \(names.joined(separator: " and "))"
            }
            return "Gain item"
        case "itemDesign":
            if let value = value, let id = Int(value) {
                if let item = store.itemData(id: id, edition: edition) {
                    return "Gain \(item.name) design"
                }
                return "Gain Item \(id) design"
            }
            return "Gain item design"
        case "randomItem":
            return "Gain one random item"
        case "randomItemDesign":
            return "Random item design"
        case "randomItemBlueprint":
            return "Random item blueprint"
        case "itemBlueprint":
            if let value = value, let id = Int(value) {
                if let item = store.itemData(id: id, edition: edition) {
                    return "Gain \(item.name) blueprint"
                }
                return "Gain Item \(id) blueprint"
            }
            return "Gain item blueprint"
        case "scenario":
            if let value = value {
                return "Unlock Scenario #\(value)"
            }
            return "Unlock new scenario"
        case "randomScenario", "randomScenarioFh":
            return "Random side scenario"
        case "battleGoal":
            if let value = value {
                return "Gain \(value) battle goal check(s)"
            }
            return "Gain battle goal check"
        case "damage":
            return "Suffer \(value ?? "?") damage"
        case "condition":
            if let value = value {
                let conditions = value.split(separator: "+").map { cond in
                    cond.replacingOccurrences(of: "_", with: " ").capitalized
                }
                return "Gain \(conditions.joined(separator: " and "))"
            }
            return "Gain condition"
        case "heal":
            return "Heal \(value ?? "?"), Self"
        case "loot":
            return "Gain \(value ?? "?") money tokens"
        case "lootCards":
            return "Gain \(value ?? "?") loot cards"
        case "partyAchievement":
            return "Party Achievement: \(value ?? "?")"
        case "event":
            return "Add event card \(value ?? "")"
        case "resource":
            return "Gain \(value ?? "?") resources"
        case "campaignSticker":
            return "Gain campaign sticker"
        case "calendarSection":
            return "Calendar section \(value ?? "")"
        case "custom":
            // Custom labels like "%data.treasures.gh.75%" — strip formatting
            if let value = value {
                let clean = value.replacingOccurrences(of: "%", with: "")
                    .replacingOccurrences(of: "data.treasures.", with: "")
                return "Special: \(clean)"
            }
            return "Special treasure"
        default:
            return reward
        }
    }
}
