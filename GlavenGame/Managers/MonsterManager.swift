import Foundation

@Observable
final class MonsterManager {
    private let game: GameState
    private let editionStore: EditionDataStore
    var onBeforeMutate: (() -> Void)?

    // Cache ability initiative lookups
    var abilityInitiatives: [String: Int] = [:]

    init(game: GameState, editionStore: EditionDataStore) {
        self.game = game
        self.editionStore = editionStore
    }

    func addMonster(name: String, edition: String) {
        onBeforeMutate?()
        guard let data = editionStore.monsterData(name: name, edition: edition) else { return }
        let monster = GameMonster(name: name, edition: edition, level: game.level, monsterData: data)

        // Initialize ability deck
        let deckName = data.deck ?? name
        let abilities = editionStore.abilities(forDeck: deckName, edition: edition)
        monster.abilities = Array(0..<abilities.count).shuffled()

        game.figures.append(.monster(monster))
    }

    func removeMonster(_ monster: GameMonster) {
        onBeforeMutate?()
        game.figures.removeAll { $0.id == "mon-\(monster.edition)-\(monster.name)" }
    }

    func addEntity(type: MonsterType, to monster: GameMonster, number: Int? = nil) {
        onBeforeMutate?()
        let resolvedType = monster.isBoss ? .boss : type
        guard let stat = monster.stat(for: resolvedType) else { return }
        // Only as many monsters as there are standees can be on the board (p.17).
        guard let standeeNumber = number ?? availableStandeeNumbers(for: monster).first else { return }
        // Prevent duplicate numbers
        guard !monster.entities.contains(where: { !$0.dead && $0.number == standeeNumber }) else { return }
        // A standee number freed by a dead monster is reused: drop the old record so lookups by
        // number find the new monster.
        monster.entities.removeAll { $0.dead && $0.number == standeeNumber }
        // C counts every character in the scenario, including exhausted ones.
        let charCount = game.characters.filter { !$0.absent }.count
        var hp = evaluateEntityValue(stat.health ?? .int(0), level: monster.level, characterCount: charCount)
        // Apply scenario stat-effect health override
        if let healthExpr = monster.statEffectHealthExpr {
            hp = evaluateStatEffectHealth(healthExpr, baseHealth: hp, level: monster.level, charCount: charCount)
        }
        let entity = GameMonsterEntity(
            number: standeeNumber,
            type: resolvedType,
            health: hp,
            maxHealth: hp,
            level: monster.level
        )
        if let immunities = stat.immunities {
            entity.immunities = immunities
        }
        // Apply scenario stat-effect immunities
        for immunity in monster.additionalImmunities where !entity.immunities.contains(immunity) {
            entity.immunities.append(immunity)
        }
        monster.entities.append(entity)
    }

    /// Standee numbers not currently in use. Empty when every standee of the type is on the
    /// board — no more of that monster can be placed (GH p.15).
    func availableStandeeNumbers(for monster: GameMonster) -> [Int] {
        let used = Set(monster.entities.filter { !$0.dead }.map(\.number))
        return (1...max(1, monster.maxCount)).filter { !used.contains($0) }
    }

    func removeEntity(_ entity: GameMonsterEntity, from monster: GameMonster) {
        onBeforeMutate?()
        monster.entities.removeAll { $0.id == entity.id }
        if monster.aliveEntities.isEmpty {
            monster.off = true
        }
    }

    func setLevel(_ level: Int, for monster: GameMonster) {
        onBeforeMutate?()
        monster.level = max(0, min(7, level))
        // Update all entities' max health
        for entity in monster.entities where !entity.dead {
            if let stat = monster.stat(for: entity.type) {
                let newMax = evaluateEntityValue(stat.health ?? .int(0), level: monster.level,
                                                   characterCount: game.characters.filter { !$0.absent }.count)
                entity.maxHealth = newMax
                entity.health = min(entity.health, newMax)
            }
        }
    }

    func abilities(for monster: GameMonster) -> [AbilityModel] {
        let deckName = monster.deckOverride ?? monster.monsterData?.deck ?? monster.name
        return editionStore.abilities(forDeck: deckName, edition: monster.edition)
    }

    func currentAbility(for monster: GameMonster) -> AbilityModel? {
        guard monster.abilityDrawn,
              monster.ability >= 0, monster.ability < monster.abilities.count else { return nil }
        let abilityIndex = monster.abilities[monster.ability]
        let allAbilities = abilities(for: monster)
        guard abilityIndex >= 0, abilityIndex < allAbilities.count else { return nil }
        return allAbilities[abilityIndex]
    }

    /// Returns the zero-based index of the currently drawn ability card within the ordered deck array.
    /// Use this with `ImageLoader.monsterAbilityCardURL(deckName:cardIndex:)` to get the card image URL.
    func currentAbilityCardIndex(for monster: GameMonster) -> Int? {
        guard monster.abilityDrawn,
              monster.ability >= 0, monster.ability < monster.abilities.count else { return nil }
        return monster.abilities[monster.ability]
    }

    func currentAbilityInitiative(for monster: GameMonster) -> Int? {
        currentAbility(for: monster)?.initiative
    }

    func drawAbility(for monster: GameMonster) {
        // One card per type per round.
        guard !monster.abilityDrawn else { return }
        if monster.abilities.isEmpty {
            shuffleAbilities(for: monster)
        }
        monster.ability += 1
        if monster.ability >= monster.abilities.count {
            shuffleAbilities(for: monster)
            monster.ability = 0
        }
        monster.abilityDrawn = true
        monster.drawnInitiative = currentAbilityInitiative(for: monster)
        // Cache initiative for sorting
        if let init_ = currentAbilityInitiative(for: monster) {
            abilityInitiatives[monster.id] = init_
        }
    }

    func shuffleAbilities(for monster: GameMonster) {
        let allAbilities = abilities(for: monster)
        monster.abilities = Array(0..<allAbilities.count).shuffled()
        monster.ability = -1
    }

    /// End-of-round cleanup for a monster type's ability deck: if the card drawn this round has
    /// the shuffle icon, shuffle the discards back into the deck (GH p.18). The draw position is
    /// otherwise kept, so next round reveals the next card.
    func finishRound(for monster: GameMonster) {
        if monster.abilityDrawn, currentAbility(for: monster)?.shuffle == true {
            shuffleAbilities(for: monster)
        }
        monster.abilityDrawn = false
        monster.drawnInitiative = nil
    }

    /// Switch a monster type to a different ability deck. A no-op if it already uses that deck;
    /// if a card was already drawn this round, draw the replacement card immediately.
    private func switchDeck(of monster: GameMonster, to deckName: String) {
        guard monster.deckOverride != deckName else { return }
        let deckAbilities = editionStore.abilities(forDeck: deckName, edition: monster.edition)
        guard !deckAbilities.isEmpty else { return }
        monster.deckOverride = deckName
        monster.abilities = Array(0..<deckAbilities.count).shuffled()
        monster.ability = -1
        if monster.abilityDrawn {
            monster.abilityDrawn = false
            drawAbility(for: monster)
        }
    }

    /// Apply stat effects (shield, retaliate) from drawn ability card, base stats, and scenario overrides to all alive entities
    func applyStatEffects(for monster: GameMonster) {
        guard let ability = currentAbility(for: monster) else { return }
        let allActions = (ability.actions ?? []) + (ability.bottomActions ?? [])

        for entity in monster.aliveEntities {
            // Rebuild from scratch every round so stat/scenario bonuses don't accumulate.
            entity.shield = nil
            entity.shieldPersistent = nil
            entity.retaliate = []
            entity.retaliatePersistent = []

            // Apply base stat actions (permanent effects from monster stat card)
            if let stat = monster.stat(for: entity.type), let statActions = stat.actions {
                for action in statActions {
                    applyStatAction(action, to: entity, persistent: true)
                }
            }

            // Apply scenario stat-effect actions (e.g. poison added by scenario rule)
            for action in monster.additionalStatActions {
                applyStatAction(action, to: entity, persistent: true)
            }

            // Apply ability card actions (round-based effects)
            for action in allActions {
                applyStatAction(action, to: entity, persistent: ability.persistent == true)
            }
        }
    }

    /// Apply a scenario-rule stat effect to a monster (display name, deck, health, actions, immunities).
    func applyScenarioStatEffect(_ effect: StatEffectData, to monster: GameMonster, charCount: Int) {
        // 1. Name override → display name + ability deck if one exists under that name
        if let name = effect.name {
            monster.displayName = name
            if effect.deck == nil {
                switchDeck(of: monster, to: name)
            }
        }

        // 2. Explicit deck override
        if let deck = effect.deck {
            switchDeck(of: monster, to: deck)
        }

        // 3. Additional stat actions (replace so re-applying is idempotent)
        if let actions = effect.actions {
            monster.additionalStatActions = actions
        }

        // 4. Additional immunities (replace so re-applying is idempotent)
        if let immunities = effect.immunities {
            monster.additionalImmunities = immunities
            for entity in monster.aliveEntities {
                for immunity in immunities where !entity.immunities.contains(immunity) {
                    entity.immunities.append(immunity)
                }
            }
        }

        // 5. Health formula override — apply to existing entities idempotently
        if let healthExpr = effect.health {
            monster.statEffectHealthExpr = healthExpr
            monster.statEffectHealthAbsolute = effect.absolute ?? false
            let resolvedCharCount = max(2, charCount)
            for entity in monster.aliveEntities {
                guard let stat = monster.stat(for: entity.type) else { continue }
                let statBaseHP = evaluateEntityValue(stat.health ?? .int(0), level: monster.level,
                                                      characterCount: resolvedCharCount)
                let targetMax = evaluateStatEffectHealth(healthExpr, baseHealth: statBaseHP,
                                                          level: monster.level, charCount: resolvedCharCount)
                guard entity.maxHealth != targetMax else { continue }
                let ratio = entity.maxHealth > 0 ? Double(entity.health) / Double(entity.maxHealth) : 1.0
                entity.maxHealth = targetMax
                entity.health = max(1, Int((Double(targetMax) * ratio).rounded()))
            }
        }
    }

    private func evaluateStatEffectHealth(_ expr: String, baseHealth: Int, level: Int, charCount: Int) -> Int {
        // Substitute H = base health value, then evaluate using the standard expression evaluator.
        let withH = expr.replacingOccurrences(of: "H", with: "\(baseHealth)")
        return max(1, evaluateEntityValue(.string(withH), level: level, characterCount: charCount))
    }

    private func applyStatAction(_ action: ActionModel, to entity: GameMonsterEntity, persistent: Bool) {
        switch action.type {
        case .shield:
            // Multiple shield bonuses stack (GH p.24).
            if persistent {
                entity.shieldPersistent = Self.stackedShield(entity.shieldPersistent, action)
            } else {
                entity.shield = Self.stackedShield(entity.shield, action)
            }
        case .retaliate:
            if persistent {
                entity.retaliatePersistent.append(action)
            } else {
                entity.retaliate.append(action)
            }
        default:
            break
        }
    }

    private static func stackedShield(_ existing: ActionModel?, _ added: ActionModel) -> ActionModel {
        guard let existing, let a = existing.value?.intValue, let b = added.value?.intValue else { return added }
        return ActionModel(type: .shield, value: .int(a + b))
    }

    func nextStandeeNumber(for monster: GameMonster, type: MonsterType) -> Int {
        let used = Set(monster.entities.filter { !$0.dead }.map(\.number))
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }
}
