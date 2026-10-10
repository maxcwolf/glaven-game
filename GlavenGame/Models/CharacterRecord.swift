import Foundation

/// What a character has done over the campaign, for personal quests: the scenarios they took
/// part in and won, the monsters they killed, how often they and their party were exhausted,
/// the gold they gave the sanctuary, the battle goals they met and the retirements they saw.
struct CharacterRecord: Codable, Equatable {
    /// Scenario ids ("gh-12") won with this character in the party.
    var scenariosCompleted: Set<String> = []
    /// Monster kills by base monster name ("bandit-guard"; scenario variants count as their base).
    var kills: [String: Int] = [:]
    var eliteKills = 0
    var timesExhausted = 0
    /// Exhaustions of the other characters in the party in scenarios they played: their own
    /// don't count for A Study of Anatomy (FAQ).
    var partyExhaustions = 0
    var donatedGold = 0
    /// Checkmarks earned from battle goals alone, never lowered: events, treasures and rewards
    /// give and take checkmarks that don't count for Battle Legacy (FAQ).
    var battleGoalChecks = 0
    /// Other characters' retirements they were in the party for (A Helping Hand).
    var retirementsSeen = 0
    /// Extra perks from their player's earlier retirements (GH p.48).
    var extraPerks = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scenariosCompleted = try c.decodeIfPresent(Set<String>.self, forKey: .scenariosCompleted) ?? []
        kills = try c.decodeIfPresent([String: Int].self, forKey: .kills) ?? [:]
        eliteKills = try c.decodeIfPresent(Int.self, forKey: .eliteKills) ?? 0
        timesExhausted = try c.decodeIfPresent(Int.self, forKey: .timesExhausted) ?? 0
        partyExhaustions = try c.decodeIfPresent(Int.self, forKey: .partyExhaustions) ?? 0
        donatedGold = try c.decodeIfPresent(Int.self, forKey: .donatedGold) ?? 0
        battleGoalChecks = try c.decodeIfPresent(Int.self, forKey: .battleGoalChecks) ?? 0
        retirementsSeen = try c.decodeIfPresent(Int.self, forKey: .retirementsSeen) ?? 0
        extraPerks = try c.decodeIfPresent(Int.self, forKey: .extraPerks) ?? 0
    }

    /// "cultist-scenario-78" → "cultist"; "bandit-guard-music-note-solo" → "bandit-guard".
    static func baseMonsterName(_ name: String) -> String {
        var base = name
        if let range = base.range(of: #"-scenario-\d+$"#, options: .regularExpression) { base.removeSubrange(range) }
        // Solo variants end in the class they're for ("-music-note-solo").
        let classes = "brute|tinkerer|spellweaver|scoundrel|cragheart|mindthief|sun|three-spears|circles|eclipse|"
            + "squidface|lightning|music-note|angry-face|saw|triangles|two-mini"
        if let range = base.range(of: "-(\(classes))-solo$", options: .regularExpression) { base.removeSubrange(range) }
        return base
    }
}
