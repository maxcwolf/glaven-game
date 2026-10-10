import Foundation

/// Campaign rules that several managers share (GH p.40, 47–49 and the FAQ): global achievements
/// and their types, reputation and what it brings at ±20, losses that never undo a level already
/// reached, loose item copies in the city's supply, and what a class and a player keep when a
/// character leaves.
extension GameState {

    // MARK: - Global achievements

    /// Types of global achievement ("City Rule: Demonic", "Artifact: Lost"). Only one of a type is
    /// active: a new one takes the old one's place (GH p.40).
    static let globalAchievementTypes = ["city-rule", "artifact"]

    static func globalAchievementType(_ id: String) -> String? {
        globalAchievementTypes.first { id.hasPrefix($0 + "-") }
    }

    /// What the world starts with (scenario book p.1): Gloomhaven is under military rule.
    static let startingGlobalAchievements = ["gh": ["city-rule-militaristic"]]

    /// Earn a global achievement. One with a type replaces the other of its type; one without
    /// can be earned again, and each time counts (End of Corruption, Ancient Technology).
    func gainGlobalAchievement(_ id: String) {
        if let type = Self.globalAchievementType(id) {
            globalAchievements = globalAchievements.filter { Self.globalAchievementType($0) != type }
            globalAchievements.insert(id)
        } else if globalAchievements.contains(id) {
            events.achievementCounts[id, default: 1] += 1
        } else {
            globalAchievements.insert(id)
        }
    }

    /// How many times the world has earned a global achievement.
    func globalAchievementCount(_ id: String) -> Int {
        globalAchievements.contains(id) ? max(1, events.achievementCounts[id] ?? 1) : 0
    }

    /// Earn a party achievement, and what some of them bring together (GH p.49): The Drake's
    /// Command with The Drake's Treasure makes The Drake Aided and adds city event 75 and road
    /// event 66.
    func gainPartyAchievement(_ id: String) {
        partyAchievements.insert(id)
        if edition == "gh", partyAchievements.isSuperset(of: ["the-drakes-command", "the-drakes-treasure"]),
           !globalAchievements.contains("the-drake-aided") {
            gainGlobalAchievement("the-drake-aided")
            events.add("75", to: "city")
            events.add("66", to: "road")
        }
    }

    // MARK: - Reputation and prosperity

    /// Change the party's reputation, kept within −20…+20 (GH p.48). What it brings the first
    /// time it gets there (GH p.49): at +10 the box with the sun is opened, at −10 the one with
    /// the moon (the Sunkeeper and the Nightshroud); at +20 city event 76 and road event 67
    /// join the decks, at −20 city event 77 and road event 68.
    func changeReputation(by amount: Int, labels: EditionDataStore) {
        partyReputation = max(-20, min(20, partyReputation + amount))
        guard edition == "gh" else { return }
        for milestone in [10, -10, 20, -20] where !events.reputationMilestones.contains(milestone) {
            guard milestone > 0 ? partyReputation >= milestone : partyReputation <= milestone else { continue }
            events.reputationMilestones.insert(milestone)
            if abs(milestone) == 10 {
                unlockClass(milestone > 0 ? "sun" : "eclipse", edition: "gh", how: "Reputation \(milestone)", labels: labels)
            } else {
                events.add(milestone > 0 ? "76" : "77", to: "city")
                events.add(milestone > 0 ? "67" : "68", to: "road")
            }
        }
    }

    static let prosperityThresholds = [0, 4, 9, 15, 22, 30, 39, 50, 64]

    /// Change the city's prosperity. A loss never takes it below the level it has reached (FAQ).
    func changeProsperity(by amount: Int) {
        let floor = Self.prosperityThresholds[prosperityLevel - 1]
        partyProsperity = amount < 0 ? max(floor, partyProsperity + amount) : partyProsperity + amount
    }

    // MARK: - The city's supply

    /// Put one copy of an item into the city's supply. A design the city already has needs no
    /// note (every copy not owned is on its shelves); another item is kept as a loose copy.
    func returnToSupply(_ itemKey: String, designKnown: Bool) {
        guard !designKnown else { return }
        events.looseItems[itemKey, default: 0] += 1
    }

    // MARK: - What a character leaves behind

    /// Note what stays when a character leaves the party: the enhancements on the class's cards
    /// (GH p.48), and the extra perks their player has earned for later characters. A retirement
    /// earns the player one more (GH p.48).
    func noteDeparture(of character: GameCharacter, retired: Bool) {
        if !character.enhancements.isEmpty {
            events.classEnhancements[character.id] = character.enhancements.map {
                var kept = $0
                kept.inherited = true
                return kept
            }
        }
        let perks = character.record.extraPerks + (retired ? 1 : 0)
        if perks > 0 { events.perksForRecruits.append(perks) }
    }

    /// The enhancements already on a class's cards, from its earlier characters.
    func classEnhancements(for classId: String) -> [Enhancement] {
        if let kept = events.classEnhancements[classId] { return kept }
        // Saves from before this was kept: the class's last retired character had them.
        return retiredCharacters.last { "\($0.edition)-\($0.name)" == classId }?.enhancements.map {
            var kept = $0
            kept.inherited = true
            return kept
        } ?? []
    }

    /// Extra perks for a new character: those of a player whose last character retired or left.
    /// The game has no players, only seats, so the next recruit is taken to be that player's.
    func claimPerksForRecruit(_ character: GameCharacter) {
        guard let most = events.perksForRecruits.max(), let index = events.perksForRecruits.firstIndex(of: most) else { return }
        events.perksForRecruits.remove(at: index)
        character.record.extraPerks = most
    }
}
