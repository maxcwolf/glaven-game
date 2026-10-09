import Foundation

/// A personal quest as the player reads it.
struct PersonalQuest: Equatable, Identifiable {
    struct Requirement: Equatable {
        let text: String
        let target: Int
        let tracking: PersonalQuestEvaluator.Tracking
        /// Earlier requirements (0-based) that must be met first.
        let after: [Int]
    }
    let id: String
    let name: String
    let requirements: [Requirement]
    /// The class it unlocks on retirement, if any.
    let unlocks: String?
    /// The envelope it opens on retirement instead ("X"), if any.
    var envelope: String? = nil
    /// The class it unlocks, as the edition names it ("plagueherald"), for its explanation.
    var unlocksClass: String? = nil

    /// What retiring with it brings: "Unlocks the Plagueherald", "Opens Envelope X".
    var reward: String? {
        if let unlocks { return "Unlocks the \(unlocks)" }
        if let envelope { return "Opens Envelope \(envelope)" }
        return nil
    }
}

/// Dealing personal quests (GH p.12): a recruit is dealt two and keeps one; on completing it the
/// character retires.
extension CharacterManager {

    func personalQuest(_ cardId: String, edition: String = "gh") -> PersonalQuest? {
        guard let data = editionStore.personalQuest(cardId: cardId, edition: edition) else { return nil }
        let labels = (editionStore.labelsByEdition[edition]?["personalQuest"] as? [String: Any])
            .flatMap { ($0[edition] as? [String: Any])?[cardId] as? [String: Any] }
        let requirements = data.requirements.enumerated().map { index, req in
            PersonalQuest.Requirement(
                text: Self.requirementText(req.name, labels: labels?["\(index + 1)"] as? String, store: editionStore, edition: edition),
                target: req.counterValue,
                tracking: PersonalQuestEvaluator.tracking(questId: cardId, index: index, requirement: req),
                after: (req.requires ?? []).map { $0 - 1 })
        }
        let unlocks = data.unlockCharacter.map { GameText.className($0, edition: edition, labels: editionStore) }
        return PersonalQuest(id: cardId, name: labels?[""] as? String ?? "Quest \(cardId)",
                             requirements: requirements, unlocks: unlocks, envelope: data.openEnvelope,
                             unlocksClass: data.unlockCharacter)
    }

    private static func requirementText(_ raw: String, labels: String?, store: EditionDataStore, edition: String) -> String {
        var text = raw.hasPrefix("%data.") ? (labels ?? store.resolveCustomText(raw, edition: edition) ?? raw) : raw
        let words: [String: String] = [
            "%game.items.slots.head%": "Head", "%game.items.slots.body%": "Body", "%game.items.slots.legs%": "Legs",
            "%game.items.slots.onehand%": "One-hand", "%game.items.slots.twohand%": "Two-hand",
            "%game.items.slots.small%": "Small", "%character.progress.gold%": "Gold",
            "%game.checkmark%": "checkmarks", "%game.exhausted%": "Times exhausted",
        ]
        for (placeholder, word) in words { text = text.replacingOccurrences(of: placeholder, with: word) }
        // The data's own shorthand, in the card's words (The Thin Places).
        text = text.replacingOccurrences(of: "(scenario number > 51)", with: "(numbered 52 or higher)")
        text = text.replacingOccurrences(of: #"%[^%]+%"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Deal two quests to a recruit, from those no one in the party holds.
    func dealQuests(to character: GameCharacter) {
        let held = Set(game.characters.compactMap(\.personalQuest))
        let deck = editionStore.personalQuests(for: character.edition).map(\.cardId).filter { !held.contains($0) }
        character.questChoices = Array(deck.shuffled(using: &GameRandom.shared).prefix(2))
    }

    /// Keep one of the two quests dealt.
    func chooseQuest(_ cardId: String, for character: GameCharacter) {
        guard character.questChoices.contains(cardId),
              let quest = editionStore.personalQuest(cardId: cardId, edition: character.edition) else { return }
        onBeforeMutate?()
        character.personalQuest = cardId
        character.personalQuestProgress = Array(repeating: 0, count: quest.requirements.count)
        character.questChoices = []
    }

    /// Count a requirement the game can't see by hand (a map region, an enhancement).
    func adjustQuest(_ index: Int, by delta: Int, for character: GameCharacter) {
        guard let id = character.personalQuest, let quest = personalQuest(id, edition: character.edition),
              index < quest.requirements.count, quest.requirements[index].tracking == .manual else { return }
        while character.personalQuestProgress.count <= index { character.personalQuestProgress.append(0) }
        let target = quest.requirements[index].target
        character.personalQuestProgress[index] = max(0, min(target, character.personalQuestProgress[index] + delta))
    }

    func questComplete(_ character: GameCharacter) -> Bool {
        PersonalQuestEvaluator.isComplete(character: character, editionStore: editionStore)
    }
}

/// The Sanctuary of the Great Oak (GH p.48): in town, each character may donate 10 gold once per
/// visit for two blessings in their next scenario; every 100 gold the party gives raises
/// prosperity by one.
extension CharacterManager {
    static let donation = 10

    func canDonate(_ character: GameCharacter) -> Bool {
        character.loot >= Self.donation && !game.events.donatedThisVisit.contains(character.id)
    }

    @discardableResult
    func donate(_ character: GameCharacter) -> Bool {
        guard canDonate(character) else { return false }
        onBeforeMutate?()
        character.loot -= Self.donation
        character.record.donatedGold += Self.donation
        game.events.donatedThisVisit.insert(character.id)
        game.events.nextScenario.blessings[character.id, default: 0] += 2
        game.events.sanctuaryGold += Self.donation
        if game.events.sanctuaryGold % 100 == 0 {
            game.partyProsperity += 1
            game.campaignLog.append(CampaignLogEntry(type: .prosperityGained,
                message: "Prosperity +1 from \(game.events.sanctuaryGold) gold given to the sanctuary"))
        }
        return true
    }
}
