import Foundation

/// What a character did in the scenario, for battle goals and the results.
struct ScenarioCharacterStats: Codable, Equatable {
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
    // For battle goals
    var trapsTriggered: Int = 0
    var treasuresLooted: Int = 0
    var doorsOpened: Int = 0
    var eliteKills: Int = 0
    var itemUses: Int = 0
    /// The most damage beyond what was needed to kill a monster.
    var largestOverkill: Int = 0
    /// Monsters killed from full health by a single attack.
    var executions: Int = 0
    var droppedBelowHalf: Bool = false
    var shortRests: Int = 0
    var longRests: Int = 0
    /// Kills by base monster name, for personal quests.
    var killsByMonster: [String: Int] = [:]
}

/// What the party did together, for battle goals.
struct ScenarioPartyStats: Codable, Equatable {
    /// The first character to kill a monster.
    var firstKiller: String?
    /// A round began with no monsters on the map.
    var roundStartedWithoutMonsters = false
}

/// Records what happens in a scenario. The tallies live on the scenario, so they start fresh
/// with each one and are saved with it.
@Observable
final class ScenarioStatsManager {
    private let game: GameState

    init(game: GameState) {
        self.game = game
    }

    /// Keyed by character name (one character per class).
    var characterStats: [String: ScenarioCharacterStats] {
        get { game.scenario?.stats ?? [:] }
        set { game.scenario?.stats = newValue }
    }

    var partyStats: ScenarioPartyStats {
        get { game.scenario?.partyStats ?? ScenarioPartyStats() }
        set { game.scenario?.partyStats = newValue }
    }

    func reset() {
        characterStats = [:]
        partyStats = ScenarioPartyStats()
    }

    private func update(_ name: String, _ change: (inout ScenarioCharacterStats) -> Void) {
        var stats = characterStats[name] ?? ScenarioCharacterStats()
        change(&stats)
        characterStats[name] = stats
    }

    func recordDamageDealt(by characterName: String, amount: Int) { update(characterName) { $0.damageDealt += amount } }
    func recordDamageTaken(by characterName: String, amount: Int) { update(characterName) { $0.damageTaken += amount } }
    func recordHeal(by characterName: String, amount: Int) { update(characterName) { $0.healsGiven += amount } }
    func recordCoinsLooted(by characterName: String, amount: Int) { update(characterName) { $0.coinsLooted += amount } }
    func recordConditionApplied(by characterName: String) { update(characterName) { $0.conditionsApplied += 1 } }
    func recordConditionReceived(by characterName: String) { update(characterName) { $0.conditionsReceived += 1 } }
    func recordExhausted(_ characterName: String) { update(characterName) { $0.exhausted = true } }
    func recordTrap(by characterName: String) { update(characterName) { $0.trapsTriggered += 1 } }
    func recordTreasure(by characterName: String) { update(characterName) { $0.treasuresLooted += 1 } }
    func recordDoor(by characterName: String) { update(characterName) { $0.doorsOpened += 1 } }
    func recordItemUse(by characterName: String) { update(characterName) { $0.itemUses += 1 } }
    func recordRest(by characterName: String, long: Bool) {
        update(characterName) { if long { $0.longRests += 1 } else { $0.shortRests += 1 } }
    }

    /// Health after a change: below half (rounded up) breaks Diehard.
    func recordHealth(of characterName: String, health: Int, maxHealth: Int) {
        if health < (maxHealth + 1) / 2 { update(characterName) { $0.droppedBelowHalf = true } }
    }

    /// A kill: whether the monster was elite, how much damage was spare, and whether a single
    /// attack took it from full health.
    func recordKill(by characterName: String, monster: String? = nil, elite: Bool = false, overkill: Int = 0,
                    fromFullHealth: Bool = false) {
        update(characterName) {
            $0.kills += 1
            if let monster { $0.killsByMonster[CharacterRecord.baseMonsterName(monster), default: 0] += 1 }
            if elite { $0.eliteKills += 1 }
            $0.largestOverkill = max($0.largestOverkill, overkill)
            if fromFullHealth { $0.executions += 1 }
        }
        if partyStats.firstKiller == nil { partyStats.firstKiller = characterName }
    }

    /// At the start of each round: whether any monster is on the map (Aggressor).
    func advanceRound(monstersPresent: Bool = true) {
        for character in game.activeCharacters { update(character.name) { $0.roundsSurvived += 1 } }
        if !monstersPresent { partyStats.roundStartedWithoutMonsters = true }
    }

    func stats(for characterName: String) -> ScenarioCharacterStats {
        characterStats[characterName] ?? ScenarioCharacterStats()
    }
}
