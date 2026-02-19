import Foundation

struct ScenarioCharacterStats {
    var damageDealt: Int = 0
    var damageTaken: Int = 0
    var healsGiven: Int = 0
    var kills: Int = 0
    var coinsLooted: Int = 0
    var roundsSurvived: Int = 0
    var exhausted: Bool = false
    var conditionsApplied: Int = 0
    var conditionsReceived: Int = 0
    var cardsLost: Int = 0
}

@Observable
final class ScenarioStatsManager {
    private let game: GameState

    var characterStats: [String: ScenarioCharacterStats] = [:]  // keyed by character id

    init(game: GameState) {
        self.game = game
    }

    func reset() {
        characterStats.removeAll()
        for character in game.characters {
            characterStats[character.name] = ScenarioCharacterStats()
        }
    }

    func recordDamageDealt(by characterName: String, amount: Int) {
        characterStats[characterName, default: ScenarioCharacterStats()].damageDealt += amount
    }

    func recordDamageTaken(by characterName: String, amount: Int) {
        characterStats[characterName, default: ScenarioCharacterStats()].damageTaken += amount
    }

    func recordHeal(by characterName: String, amount: Int) {
        characterStats[characterName, default: ScenarioCharacterStats()].healsGiven += amount
    }

    func recordKill(by characterName: String) {
        characterStats[characterName, default: ScenarioCharacterStats()].kills += 1
    }

    func recordCoinsLooted(by characterName: String, amount: Int) {
        characterStats[characterName, default: ScenarioCharacterStats()].coinsLooted += amount
    }

    func recordConditionApplied(by characterName: String) {
        characterStats[characterName, default: ScenarioCharacterStats()].conditionsApplied += 1
    }

    func recordConditionReceived(by characterName: String) {
        characterStats[characterName, default: ScenarioCharacterStats()].conditionsReceived += 1
    }

    func recordExhausted(_ characterName: String) {
        characterStats[characterName, default: ScenarioCharacterStats()].exhausted = true
    }

    func advanceRound() {
        for character in game.activeCharacters {
            characterStats[character.name, default: ScenarioCharacterStats()].roundsSurvived += 1
        }
    }

    func stats(for characterName: String) -> ScenarioCharacterStats {
        characterStats[characterName] ?? ScenarioCharacterStats()
    }
}
