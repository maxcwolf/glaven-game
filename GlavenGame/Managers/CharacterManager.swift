import Foundation

@Observable
final class CharacterManager {
    private let game: GameState
    private let editionStore: EditionDataStore
    private let entityManager: EntityManager
    private let attackModifierManager: AttackModifierManager
    var onBeforeMutate: (() -> Void)?
    var onCharacterExhausted: ((GameCharacter) -> Void)?
    var scenarioStatsManager: ScenarioStatsManager?

    init(game: GameState, editionStore: EditionDataStore, entityManager: EntityManager, attackModifierManager: AttackModifierManager) {
        self.game = game
        self.editionStore = editionStore
        self.entityManager = entityManager
        self.attackModifierManager = attackModifierManager
    }

    func addCharacter(name: String, edition: String, level: Int = 1) {
        onBeforeMutate?()
        guard let data = editionStore.characterData(name: name, edition: edition) else { return }
        // Prevent duplicates
        guard !game.characters.contains(where: { $0.name == name && $0.edition == edition }) else { return }
        let clampedLevel = max(1, min(9, level))
        let character = GameCharacter(name: name, edition: edition, level: clampedLevel, characterData: data)
        character.attackModifierDeck = .defaultDeck()
        character.selectedPerks = Array(repeating: 0, count: data.perks?.count ?? 0)
        // Assign unique number
        var number = 1
        while game.characters.contains(where: { $0.number == number }) { number += 1 }
        character.number = number
        game.figures.append(.character(character))
        game.campaignLog.append(CampaignLogEntry(
            type: .characterAdded,
            message: "\(name.replacingOccurrences(of: "-", with: " ").capitalized) joined the party",
            details: "Level \(clampedLevel)"
        ))
    }

    func removeCharacter(_ character: GameCharacter) {
        onBeforeMutate?()
        game.figures.removeAll { $0.id == "char-\(character.edition)-\(character.name)" }
    }

    func retireCharacter(_ character: GameCharacter) {
        onBeforeMutate?()

        // Mark as retired
        character.retired = true

        // Archive as snapshot
        game.retiredCharacters.append(character.toSnapshot())

        // Unlock character from personal quest if complete
        if let questId = character.personalQuest,
           let quest = editionStore.personalQuest(cardId: questId) {
            if let unlock = quest.unlockCharacter {
                game.unlockedCharacters.insert("\(character.edition)-\(unlock)")
                game.campaignLog.append(CampaignLogEntry(
                    type: .characterUnlocked,
                    message: "\(unlock.replacingOccurrences(of: "-", with: " ").capitalized) unlocked",
                    details: "Via retirement of \(character.name.replacingOccurrences(of: "-", with: " ").capitalized)"
                ))
            }
        }

        // +1 prosperity on retirement
        game.partyProsperity += 1
        game.campaignLog.append(CampaignLogEntry(
            type: .prosperityGained,
            message: "+1 Prosperity from retirement"
        ))

        // Log retirement
        let displayName = character.title.isEmpty
            ? character.name.replacingOccurrences(of: "-", with: " ").capitalized
            : character.title
        game.campaignLog.append(CampaignLogEntry(
            type: .characterRetired,
            message: "\(displayName) retired",
            details: "Level \(character.level), \(character.experience) XP, \(character.loot) Gold"
        ))

        // Remove from active game
        game.figures.removeAll { $0.id == "char-\(character.edition)-\(character.name)" }
    }

    func setLevel(_ level: Int, for character: GameCharacter) {
        onBeforeMutate?()
        let newLevel = max(1, min(9, level))
        character.level = newLevel
        character.updateStatsForLevel()
    }

    func addXP(_ amount: Int, to character: GameCharacter) {
        onBeforeMutate?()
        character.experience = max(0, character.experience + amount)
        // Auto level-up when XP crosses threshold
        let newLevel = GameCharacter.levelForXP(character.experience)
        if newLevel != character.level {
            character.level = max(1, min(9, newLevel))
            character.updateStatsForLevel()
        }
    }

    func addLoot(_ amount: Int, to character: GameCharacter) {
        onBeforeMutate?()
        character.loot = max(0, character.loot + amount)
    }

    func toggleExhausted(_ character: GameCharacter) {
        onBeforeMutate?()
        character.exhausted.toggle()
        if character.exhausted {
            character.health = 0
            character.entityConditions.removeAll()
            scenarioStatsManager?.recordExhausted(character.name)
            // Remove all summons when character is exhausted
            onCharacterExhausted?(character)
            character.summons.removeAll()
        }
    }

    func toggleAbsent(_ character: GameCharacter) {
        onBeforeMutate?()
        character.absent.toggle()
    }

    func cycleIdentity(_ character: GameCharacter) {
        guard let identities = character.characterData?.identities, identities.count > 1 else { return }
        onBeforeMutate?()
        character.identity = (character.identity + 1) % identities.count
    }

    func setInitiative(_ initiative: Int, for character: GameCharacter) {
        onBeforeMutate?()
        character.initiative = max(0, min(99, initiative))
    }

    func addSummon(from data: SummonDataModel, for character: GameCharacter) {
        onBeforeMutate?()
        let hp = evaluateEntityValue(data.health, level: character.level)
        let summon = GameSummon(
            name: data.name,
            cardId: data.cardId ?? "",
            number: nextSummonNumber(for: character),
            health: hp,
            maxHealth: hp,
            level: data.level ?? character.level,
            attack: data.attack ?? .int(0),
            movement: data.movement?.intValue ?? 0,
            range: data.range?.intValue ?? 0,
            flying: data.flying ?? false
        )
        character.summons.append(summon)
    }

    func removeSummon(_ summon: GameSummon, from character: GameCharacter) {
        character.summons.removeAll { $0.uuid == summon.uuid }
    }

    func setTitle(_ title: String, for character: GameCharacter) {
        onBeforeMutate?()
        character.title = title
    }

    func setNotes(_ notes: String, for character: GameCharacter) {
        onBeforeMutate?()
        character.notes = notes
    }

    func setBattleGoalProgress(_ progress: Int, for character: GameCharacter) {
        onBeforeMutate?()
        character.battleGoalProgress = max(0, min(18, progress))
    }

    func togglePerk(at index: Int, for character: GameCharacter) {
        onBeforeMutate?()
        guard let perks = character.characterData?.perks, index < perks.count else { return }
        while character.selectedPerks.count <= index { character.selectedPerks.append(0) }
        let perk = perks[index]
        character.selectedPerks[index] = character.selectedPerks[index] < perk.count
            ? character.selectedPerks[index] + 1 : 0
        attackModifierManager.buildCharacterDeck(for: character)
    }

    private func nextSummonNumber(for character: GameCharacter) -> Int {
        let used = Set(character.summons.map(\.number))
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }
}
