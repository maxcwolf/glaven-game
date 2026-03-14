import Foundation

/// Evaluates whether a character achieved their selected battle goal at the end of a scenario.
/// Returns nil if the goal cannot be auto-evaluated (requires manual tracking).
enum BattleGoalEvaluator {

    /// Evaluate a battle goal for a character.
    /// - Parameters:
    ///   - cardId: The battle goal card ID (e.g., "470" for Pacifist)
    ///   - character: The character to evaluate
    ///   - stats: The character's scenario stats (kills, damage, coins, etc.)
    ///   - scenarioXP: XP gained during this scenario (not including bonus)
    ///   - alliesExhausted: Whether any ally characters were exhausted
    /// - Returns: `true` if achieved, `false` if failed, `nil` if cannot auto-evaluate
    static func evaluate(
        cardId: String,
        character: GameCharacter,
        stats: ScenarioCharacterStats,
        scenarioXP: Int,
        alliesExhausted: Bool
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

        // Neutralizer: "Cause a trap to be sprung or disarmed" — needs event tracking
        case "464":
            return nil

        // Plunderer: "Loot a treasure overlay tile" — needs event tracking
        case "465":
            return nil

        // Protector: "No character allies became exhausted"
        case "466":
            return !alliesExhausted

        // Explorer: "Reveal a room tile by opening a door" — needs event tracking
        case "467":
            return nil

        // Hoarder: "Loot five or more money tokens"
        case "468":
            return stats.coinsLooted >= 5

        // Indigent: "Loot no money tokens or treasure overlay tiles"
        case "469":
            return stats.coinsLooted == 0

        // Pacifist: "Kill three or fewer monsters"
        case "470":
            return stats.kills <= 3

        // Sadist: "Kill five or more monsters"
        case "471":
            return stats.kills >= 5

        // Hunter: "Kill one or more elite monsters" — needs elite kill tracking
        case "472":
            return nil

        // Professional: "Use items >= level + 2 times" — needs item use count
        case "473":
            return nil

        // Aggressor: "Monsters present at beginning of every round" — needs round tracking
        case "474":
            return nil

        // Dynamo: "Overkill a monster by 4+" — needs event tracking
        case "475":
            return nil

        // Purist: "Use no items during the scenario"
        case "476":
            return character.spentItems.isEmpty && character.consumedItems.isEmpty

        // Opener: "Be the first to kill a monster" — needs event tracking
        case "477":
            return nil

        // Diehard: "Never drop below half max HP" — needs continuous tracking
        case "478":
            return nil

        // Executioner: "Kill an undamaged monster with a single attack" — needs event tracking
        case "479":
            return nil

        // Straggler: "Take only long rests" — needs rest type tracking
        case "480":
            return nil

        // Scrambler: "Take only short rests" — needs rest type tracking
        case "481":
            return nil

        default:
            return nil
        }
    }

    /// Result of battle goal evaluation for display.
    struct Result {
        let cardId: String
        let goalName: String
        let achieved: Bool?  // nil = manual check required
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

        for character in game.activeCharacters {
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
                alliesExhausted: alliesExhausted
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
