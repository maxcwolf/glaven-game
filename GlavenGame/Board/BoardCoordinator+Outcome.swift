import Foundation

/// Why a scenario ended.
enum ScenarioEndReason: Equatable {
    case enemiesDefeated
    /// The scenario's own goal, as the brief words it ("Survive until the end of round 10.").
    case goalMet(String)
    case partyExhausted
    /// The scenario's own loss condition, as the brief words it.
    case ruleLost(String)

    var text: String {
        switch self {
        case .enemiesDefeated: return "Every enemy is dead."
        case .goalMet(let goal): return "Goal met: \(goal)"
        case .partyExhausted: return "Every character is exhausted."
        case .ruleLost(let rule): return "Lost: \(rule)"
        }
    }
}

/// What the results screen shows: how the scenario ended and what each character takes away.
struct ScenarioOutcome: Equatable {
    struct Hero: Equatable, Identifiable {
        let id: String
        let name: String
        let edition: String
        let className: String
        /// Experience gained during the scenario (ability cards, kills…).
        let xpGained: Int
        /// The scenario-level bonus for a success (4 + 2 × level).
        let bonusXP: Int
        let goldGained: Int
        let exhausted: Bool
        /// The level the character can now reach, when they have enough experience for it.
        let levelUpTo: Int?
    }

    let victory: Bool
    let title: String
    let reason: String
    let rounds: Int
    let heroes: [Hero]
    /// The scenario's rewards, as the game applies them on Finish.
    let rewards: [String]
    /// What a result means under the rules.
    let note: String
}

extension BoardCoordinator {

    /// The results of the scenario that just ended, before Finish applies them.
    func scenarioOutcome() -> ScenarioOutcome? {
        guard let gameManager, let result = scenarioResult, let scenario = gameManager.game.scenario else { return nil }
        let victory = result == .victory
        let game = gameManager.game
        let labels = gameManager.editionStore
        let bonus = victory ? gameManager.levelManager.experience() : 0
        let rewards = victory ? scenario.data.rewards : nil
        let rewardXP = rewards?.experience.map(gameManager.scenarioManager.resolveRewardInt) ?? 0
        let rewardGold = rewards?.gold.map(gameManager.scenarioManager.resolveRewardInt) ?? 0

        let heroes = game.characters.filter { !$0.absent }.map { character in
            let xpGained = character.experience - (scenario.startingExperience[character.id] ?? character.experience)
            let xpAfter = character.experience + bonus + rewardXP
            let reachable = GameCharacter.levelForXP(xpAfter)
            return ScenarioOutcome.Hero(
                id: character.id,
                name: GameText.characterName(character, labels: labels),
                edition: character.edition,
                className: character.name,
                xpGained: xpGained,
                bonusXP: bonus,
                goldGained: character.loot - (scenario.startingGold[character.id] ?? character.loot),
                exhausted: character.exhausted,
                levelUpTo: reachable > character.level ? reachable : nil)
        }

        var lines: [String] = []
        if let rewards {
            if rewardGold != 0 { lines.append("\(rewardGold) gold each") }
            if rewardXP != 0 { lines.append("\(rewardXP) experience each") }
            if let value = rewards.prosperity {
                lines.append("Prosperity \(signed(gameManager.scenarioManager.resolveRewardInt(value)))")
            }
            if let value = rewards.reputation {
                lines.append("Reputation \(signed(gameManager.scenarioManager.resolveRewardInt(value)))")
            }
            for id in rewards.partyAchievements ?? [] {
                lines.append("Party achievement: \(achievement(id, kind: "partyAchievements", labels: labels, edition: scenario.data.edition))")
            }
            for id in rewards.globalAchievements ?? [] {
                lines.append("Global achievement: \(achievement(id, kind: "globalAchievements", labels: labels, edition: scenario.data.edition))")
            }
            let edition = scenario.data.edition
            for grant in ScenarioManager.rewardItemGrants(rewards) {
                let name = labels.itemData(id: grant.id, edition: edition)?.name ?? "Item \(grant.id)"
                lines.append(grant.count > 1 ? "Item: \(grant.count) \u{00D7} \(name)" : "Item: \(name)")
            }
            for id in rewards.itemDesigns ?? [] {
                let name = Int(id).flatMap { labels.itemData(id: $0, edition: edition)?.name } ?? "Item \(id)"
                lines.append("Item design: \(name), now in the shop")
            }
            if let value = rewards.collectiveGold {
                lines.append("\(gameManager.scenarioManager.resolveRewardInt(value)) gold to share")
            }
            if let checks = rewards.battleGoals {
                lines.append(checks == 1 ? "1 battle goal checkmark each" : "\(checks) battle goal checkmarks each")
            }
            if let name = rewards.unlockCharacter {
                lines.append("New class: \(GameText.className(name, edition: edition, labels: labels))")
            }
            for entry in rewards.events ?? [] {
                let parts = entry.split(separator: ":")
                if parts.count == 2 { lines.append("A new \(parts[0]) event joins the deck") }
            }
            if let locations = rewards.chooseLocation, !locations.isEmpty {
                let names = locations.compactMap { labels.scenarioData(index: $0, edition: edition) }
                    .map { ScenarioBrief.make(for: $0, labels: labels).title }
                lines.append("Choose a location: \(GameText.list(names).replacingOccurrences(of: " and ", with: " or "))")
            }
            for id in rewards.lostPartyAchievements ?? [] {
                lines.append("Party achievement lost: \(achievement(id, kind: "partyAchievements", labels: labels, edition: scenario.data.edition))")
            }
        }
        if victory {
            for index in scenario.data.unlocks ?? [] {
                guard let unlocked = labels.scenarioData(index: index, edition: scenario.data.edition) else { continue }
                lines.append("New scenario: \(ScenarioBrief.make(for: unlocked, labels: labels).title)")
            }
        }

        let reason = (endReason ?? (victory ? .enemiesDefeated : .partyExhausted)).text
        return ScenarioOutcome(
            victory: victory,
            title: ScenarioBrief.make(for: scenario.data, labels: labels).title,
            reason: reason,
            rounds: game.round,
            heroes: heroes,
            rewards: lines,
            note: victory
                ? "Every character gains the bonus experience, exhausted or not."
                : "No rewards, but everyone keeps the experience and gold they gained.")
    }

    private func signed(_ value: Int) -> String {
        value < 0 ? "\u{2212}\(-value)" : "+\(value)"
    }

    private func achievement(_ id: String, kind: String, labels: EditionDataStore, edition: String) -> String {
        labels.resolveLabel(key: "\(kind).\(id)", edition: edition) ?? GameText.titleCased(id)
    }
}
