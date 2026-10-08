import Foundation

/// Evaluates whether a character achieved their selected battle goal at the end of a scenario.
/// Every Gloomhaven goal is judged from the scenario's stats; nil only for an unknown card.
enum BattleGoalEvaluator {

    /// Evaluate a battle goal for a character.
    /// - Parameters:
    ///   - cardId: The battle goal card ID (e.g., "470" for Pacifist)
    ///   - character: The character to evaluate
    ///   - stats: The character's scenario stats (kills, damage, coins, etc.)
    ///   - scenarioXP: XP gained during this scenario (not including bonus)
    ///   - alliesExhausted: Whether any ally characters were exhausted
    /// - Returns: `true` if achieved, `false` if failed, `nil` for an unknown card
    static func evaluate(
        cardId: String,
        character: GameCharacter,
        stats: ScenarioCharacterStats,
        scenarioXP: Int,
        alliesExhausted: Bool,
        party: ScenarioPartyStats = ScenarioPartyStats()
    ) -> Bool? {
        switch cardId {
        // Streamliner: "Have five or more total cards in your hand and discard at the end"
        case "458":
            return character.handCards.count + character.discardedCards.count >= 5

        // Layabout: "Gain 7 or fewer experience points during the scenario"
        case "459":
            return scenarioXP <= 7

        // Workhorse: "Gain 13 or more experience points during the scenario"
        case "460":
            return scenarioXP >= 13

        // Zealot: "Have three or fewer total cards in your hand and discard at the end"
        case "461":
            return character.handCards.count + character.discardedCards.count <= 3

        // Masochist: "Current HP <= 2 at end of scenario"
        case "462":
            return character.health <= 2

        // Fast Healer: "Current HP == max HP at end of scenario"
        case "463":
            return character.health == character.maxHealth

        // Neutralizer: "Cause a trap to be sprung or disarmed"
        case "464":
            return stats.trapsTriggered > 0

        // Plunderer: "Loot a treasure overlay tile"
        case "465":
            return stats.treasuresLooted > 0

        // Protector: "No character allies became exhausted"
        case "466":
            return !alliesExhausted

        // Explorer: "Reveal a room tile by opening a door"
        case "467":
            return stats.doorsOpened > 0

        // Hoarder: "Loot five or more money tokens"
        case "468":
            return stats.coinsLooted >= 5

        // Indigent: "Loot no money tokens or treasure overlay tiles"
        case "469":
            return stats.coinsLooted == 0 && stats.treasuresLooted == 0

        // Pacifist: "Kill three or fewer monsters"
        case "470":
            return stats.kills <= 3

        // Sadist: "Kill five or more monsters"
        case "471":
            return stats.kills >= 5

        // Hunter: "Kill one or more elite monsters"
        case "472":
            return stats.eliteKills > 0

        // Professional: "Use items >= level + 2 times"
        case "473":
            return stats.itemUses >= character.level + 2

        // Aggressor: "Monsters present at beginning of every round"
        case "474":
            return !party.roundStartedWithoutMonsters

        // Dynamo: "Overkill a monster by 4+"
        case "475":
            return stats.largestOverkill >= 4

        // Purist: "Use no items during the scenario"
        case "476":
            return character.spentItems.isEmpty && character.consumedItems.isEmpty

        // Opener: "Be the first to kill a monster"
        case "477":
            return party.firstKiller == character.name

        // Diehard: "Never drop below half max HP"
        case "478":
            return !stats.droppedBelowHalf

        // Executioner: "Kill an undamaged monster with a single attack"
        case "479":
            return stats.executions > 0

        // Straggler: "Take only long rests"
        case "480":
            return stats.longRests > 0 && stats.shortRests == 0

        // Scrambler: "Take only short rests"
        case "481":
            return stats.shortRests > 0 && stats.longRests == 0

        default:
            return nil
        }
    }

    /// Result of battle goal evaluation for display.
    struct Result {
        let cardId: String
        let goalName: String
        let achieved: Bool?  // nil = an unknown card
        let checksAwarded: Int
    }

    /// Evaluate battle goals for all characters after scenario completion.
    static func evaluateAll(
        game: GameState,
        statsManager: ScenarioStatsManager,
        scenarioXPGained: [String: Int],  // characterID → XP gained this scenario
        battleGoalData: [BattleGoalData]
    ) -> [String: Result] {  // characterID → result
        var results: [String: Result] = [:]

        let anyExhausted = game.characters.contains { $0.exhausted }

        // Exhausted characters can still complete their battle goal on a success (GH p.47).
        for character in game.characters where !character.absent {
            guard let selectedIndex = character.selectedBattleGoal,
                  selectedIndex < character.battleGoalCardIds.count else { continue }

            let cardId = character.battleGoalCardIds[selectedIndex]
            let stats = statsManager.stats(for: character.name)
            let xp = scenarioXPGained[character.id] ?? 0

            // Check if any OTHER character is exhausted (not this one)
            let alliesExhausted = game.characters.contains {
                $0.id != character.id && !$0.absent && $0.exhausted
            }

            let achieved = evaluate(
                cardId: cardId,
                character: character,
                stats: stats,
                scenarioXP: xp,
                alliesExhausted: alliesExhausted,
                party: statsManager.partyStats
            )

            let goalData = battleGoalData.first { $0.cardId == cardId }
            let checks = achieved == true ? (goalData?.checks ?? 1) : 0

            results[character.id] = Result(
                cardId: cardId,
                goalName: goalData?.name ?? "Unknown",
                achieved: achieved,
                checksAwarded: checks
            )
        }

        return results
    }
}
