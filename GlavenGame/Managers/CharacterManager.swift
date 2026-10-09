import Foundation

@Observable
final class CharacterManager {
    let game: GameState
    let editionStore: EditionDataStore
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
        // A new character starts with the experience of their level and 15 × (level + 1) gold (p.45).
        character.experience = GameCharacter.xpThresholds[clampedLevel - 1]
        character.loot = Self.startingGold(level: clampedLevel)
        character.attackModifierDeck = .defaultDeck()
        character.selectedPerks = Array(repeating: 0, count: data.perks?.count ?? 0)
        // Assign unique number
        var number = 1
        while game.characters.contains(where: { $0.number == number }) { number += 1 }
        character.number = number
        game.figures.append(.character(character))
        game.campaignLog.append(CampaignLogEntry(
            type: .characterAdded,
            message: "\(GameText.className(name, edition: edition, labels: editionStore)) joined the party",
            details: "Level \(clampedLevel)"
        ))
    }

    /// Gold a new character brings: 15 × (level + 1) (p.45).
    static func startingGold(level: Int) -> Int { 15 * (level + 1) }

    /// The highest level a new character can start at: the city's prosperity level (p.45).
    var highestStartingLevel: Int { game.prosperityLevel }

    func removeCharacter(_ character: GameCharacter) {
        onBeforeMutate?()
        game.figures.removeAll { $0.id == "char-\(character.edition)-\(character.name)" }
    }

    /// Take back a recruit who hasn't chosen their quest yet: they leave, and so does the log's
    /// "joined the party", as if they'd never been recruited.
    func undoRecruit(_ character: GameCharacter) {
        removeCharacter(character)
        let joined = "\(GameText.className(character.name, edition: character.edition, labels: editionStore)) joined the party"
        if let last = game.campaignLog.lastIndex(where: { $0.type == .characterAdded && $0.message == joined }) {
            game.campaignLog.remove(at: last)
        }
    }

    func retireCharacter(_ character: GameCharacter, addRetirementEvents: Bool = true) {
        onBeforeMutate?()

        // Mark as retired
        character.retired = true

        // Archive as snapshot
        game.retiredCharacters.append(character.toSnapshot())

        // Unlock character from personal quest if complete
        if let questId = character.personalQuest,
           let quest = editionStore.personalQuest(cardId: questId) {
            if let unlock = quest.unlockCharacter {
                game.unlockClass(unlock, edition: character.edition,
                                 how: "Via retirement of \(GameText.characterName(character, labels: editionStore))",
                                 labels: editionStore)
            }
        }
        if addRetirementEvents {
            game.addRetirementEvents(of: character.name, edition: character.edition, labels: editionStore)
        }

        // +1 prosperity on retirement
        game.partyProsperity += 1
        game.campaignLog.append(CampaignLogEntry(
            type: .prosperityGained,
            message: "Prosperity +1 from a retirement"
        ))

        // Log retirement
        let displayName = GameText.characterName(character, labels: editionStore)
        game.campaignLog.append(CampaignLogEntry(
            type: .characterRetired,
            message: "\(displayName) retired",
            details: "Level \(character.level), \(character.experience) XP, \(character.loot) Gold"
        ))

        // Remove from active game
        game.figures.removeAll { $0.id == "char-\(character.edition)-\(character.name)" }
    }

    // MARK: - Ability cards

    func abilities(for character: GameCharacter) -> [AbilityModel] {
        editionStore.abilities(forDeck: character.characterData?.deck ?? character.name, edition: character.edition)
    }

    /// The cards the character can bring into a scenario.
    func cardPool(for character: GameCharacter) -> [AbilityModel] {
        CardPool.pool(abilities(for: character), chosen: character.chosenCards)
    }

    func pendingCardChoices(for character: GameCharacter) -> Int {
        CardPool.pendingChoices(level: character.level, chosen: character.chosenCards)
    }

    func choosableCards(for character: GameCharacter) -> [AbilityModel] {
        CardPool.choosable(abilities(for: character), level: character.level, chosen: character.chosenCards)
    }

    /// Add a level-up card to the character's pool, and to their hand if it has room.
    @discardableResult
    func chooseCard(_ cardId: Int, for character: GameCharacter) -> Bool {
        guard pendingCardChoices(for: character) > 0,
              choosableCards(for: character).contains(where: { $0.cardId == cardId }) else { return false }
        onBeforeMutate?()
        character.chosenCards.append(cardId)
        if character.handCards.count < character.handSize { character.handCards.append(cardId) }
        return true
    }

    /// The hand the character brings into the next scenario: the one they chose, or the default
    /// from their pool if they haven't chosen one (it's dealt as the board is entered).
    func nextHand(for character: GameCharacter) -> [Int] {
        guard character.handCards.isEmpty else { return character.handCards }
        return CardPool.defaultHand(abilities(for: character), chosen: character.chosenCards, handSize: character.handSize)
    }

    /// Set the hand the character brings into the next scenario: cards from their pool, as many
    /// as their hand size (or the whole pool, if it's smaller).
    @discardableResult
    func setHand(_ cardIds: [Int], for character: GameCharacter) -> Bool {
        let pool = Set(cardPool(for: character).compactMap(\.cardId))
        let size = min(character.handSize, pool.count)
        guard cardIds.count == size, Set(cardIds).count == size, Set(cardIds).isSubset(of: pool) else { return false }
        onBeforeMutate?()
        character.handCards = cardIds
        return true
    }

    /// Whether a character has the experience for their next level (levels top out at 9).
    func canLevelUp(_ character: GameCharacter) -> Bool {
        character.level < 9 && GameCharacter.levelForXP(character.experience) > character.level
    }

    /// Go up a level between scenarios: more hit points, the next level's cards, and a perk.
    @discardableResult
    func levelUp(_ character: GameCharacter) -> Bool {
        guard canLevelUp(character) else { return false }
        setLevel(character.level + 1, for: character)
        character.health = character.maxHealth
        game.campaignLog.append(CampaignLogEntry(
            type: .levelUp,
            message: "\(GameText.characterName(character, labels: editionStore)) reached level \(character.level)"))
        return true
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
            uuid: GameRandom.uuid(),
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
        // The summon card's printed traits: flying, permanent shield/retaliate, and effects
        // added to each of its attacks.
        for action in [data.action, data.additionalAction].compactMap({ $0 }) {
            switch action.type {
            case .fly:
                summon.flying = true
            case .shield:
                summon.shieldPersistent = action
            case .retaliate:
                summon.retaliatePersistent.append(action)
            case .condition, .pierce, .push, .pull, .target, .specialTarget:
                summon.attackEffects.append(action)
            default:
                break
            }
        }
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
        character.battleGoalProgress = max(0, min(GameCharacter.maxBattleGoalChecks, progress))
    }

    /// Perks a character has earned but not taken: one for each level after the first and one
    /// for every three battle-goal checkmarks (p.44, p.46).
    func perksAvailable(for character: GameCharacter) -> Int {
        let earned = (character.level - 1) + character.battleGoalProgress / 3
        return max(0, earned - character.selectedPerks.reduce(0, +))
    }

    /// Take one more of a perk (if one is earned and the perk has more), or, once it's full or
    /// no perk is left to take, give that perk's marks back.
    func togglePerk(at index: Int, for character: GameCharacter) {
        onBeforeMutate?()
        guard let perks = character.characterData?.perks, index < perks.count else { return }
        while character.selectedPerks.count <= index { character.selectedPerks.append(0) }
        let perk = perks[index]
        character.selectedPerks[index] = character.selectedPerks[index] < perk.count && perksAvailable(for: character) > 0
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
