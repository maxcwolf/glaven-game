import Foundation

/// The choices players make while a scenario's rewards are applied (GH p.47). Anything left
/// unchosen falls back to the defaults below, so the rewards can also be applied without a UI.
struct ScenarioRewardChoices {
    /// Item key ("gh-114") → the characters (by id) who take the copies, in order.
    var itemRecipients: [String: [String]] = [:]
    /// Character id → their share of the collective gold. Ignored unless it adds up to the total.
    var collectiveGold: [String: Int] = [:]
    /// The scenario picked from a "choose one location" reward.
    var location: String?
}

/// Copies of an item given by a scenario reward.
struct RewardItemGrant: Hashable {
    let id: Int
    let count: Int
}

/// Scenario rewards beyond achievements, prosperity, reputation and per-character gold and XP.
extension ScenarioManager {

    /// Characters who take part in the scenario and so can receive its rewards.
    var rewardParty: [GameCharacter] {
        game.characters.filter { !$0.absent }
    }

    func applyRewardChoices(_ rewards: ScenarioRewards, edition: String, choices: ScenarioRewardChoices) {
        grantRewardItems(rewards, edition: edition, recipients: choices.itemRecipients)
        if let designs = rewards.itemDesigns {
            // An item design puts every copy of the item into the city's supply.
            for id in designs { game.unlockedItems.insert("\(edition)-\(id)") }
        }
        if let gold = rewards.collectiveGold {
            let shares = collectiveGoldShares(total: resolveRewardInt(gold), chosen: choices.collectiveGold)
            for character in rewardParty {
                character.loot += shares[character.id] ?? 0
            }
        }
        if let checks = rewards.battleGoals {
            for character in rewardParty { character.battleGoalProgress += checks }
        }
        if let name = rewards.unlockCharacter {
            unlockRewardCharacter(name, edition: edition)
        }
        // "city:78": shuffle that event into its deck.
        for entry in rewards.events ?? [] {
            let parts = entry.split(separator: ":").map(String.init)
            guard parts.count == 2, ["city", "road"].contains(parts[0]) else { continue }
            game.events.add(parts[1], to: parts[0])
        }
        if let locations = rewards.chooseLocation, !locations.isEmpty {
            let pick = choices.location.flatMap { locations.contains($0) ? $0 : nil } ?? locations[0]
            game.manualScenarios.insert("\(edition)-\(pick)")
        }
    }

    // MARK: - Items

    /// The items a reward gives: "114" is one copy of item 114, "27:2" two copies of item 27.
    static func rewardItemGrants(_ rewards: ScenarioRewards) -> [RewardItemGrant] {
        (rewards.items ?? []).compactMap { entry in
            let parts = entry.split(separator: ":").map(String.init)
            guard let id = parts.first.flatMap({ Int($0) }) else { return nil }
            let count = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            return RewardItemGrant(id: id, count: max(1, count))
        }
    }

    /// Characters who can take a copy of the item: in the scenario and not already owning one,
    /// since a character can never own two copies of the same item.
    func eligibleItemRecipients(_ itemKey: String) -> [GameCharacter] {
        rewardParty.filter { !$0.items.contains(itemKey) }
    }

    /// Each copy of a reward item goes to one character of the players' choice (GH p.47); several
    /// copies go to different characters. A copy no one can take goes to the city's supply.
    private func grantRewardItems(_ rewards: ScenarioRewards, edition: String, recipients: [String: [String]]) {
        for grant in Self.rewardItemGrants(rewards) {
            let key = "\(edition)-\(grant.id)"
            let eligible = eligibleItemRecipients(key)
            var takers: [GameCharacter] = []
            for id in recipients[key] ?? [] {
                if let character = eligible.first(where: { $0.id == id }),
                   !takers.contains(where: { $0 === character }) {
                    takers.append(character)
                }
            }
            for character in eligible where takers.count < grant.count && !takers.contains(where: { $0 === character }) {
                takers.append(character)
            }
            let itemName = editionStore.itemData(id: grant.id, edition: edition)?.name ?? "Item \(grant.id)"
            for copy in 0..<grant.count {
                if copy < takers.count {
                    takers[copy].items.append(key)
                    game.campaignLog.append(CampaignLogEntry(
                        type: .itemAcquired,
                        message: "\(GameText.characterName(takers[copy], labels: editionStore)) gained \(itemName)"
                    ))
                } else {
                    game.unlockedItems.insert(key)
                }
            }
        }
    }

    // MARK: - Collective Gold

    /// Collective gold is split among the characters however the players choose (GH p.47).
    /// Without a valid choice it is split evenly, the remainder going one coin each in party order.
    func collectiveGoldShares(total: Int, chosen: [String: Int] = [:]) -> [String: Int] {
        let party = rewardParty
        guard !party.isEmpty, total > 0 else { return [:] }
        let ids = Set(party.map(\.id))
        let valid = chosen.allSatisfy { ids.contains($0.key) && $0.value >= 0 }
        if valid && chosen.values.reduce(0, +) == total { return chosen }
        var shares: [String: Int] = [:]
        for (index, character) in party.enumerated() {
            shares[character.id] = total / party.count + (index < total % party.count ? 1 : 0)
        }
        return shares
    }

    // MARK: - Characters

    private func unlockRewardCharacter(_ name: String, edition: String) {
        game.unlockClass(name, edition: edition, how: "Scenario reward", labels: editionStore)
    }
}
