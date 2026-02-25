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
        let standeeNumber = number ?? nextStandeeNumber(for: monster, type: resolvedType)
        // Prevent duplicate numbers
        guard !monster.entities.contains(where: { !$0.dead && $0.number == standeeNumber }) else { return }
        let charCount = game.activeCharacters.count
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

    func availableStandeeNumbers(for monster: GameMonster) -> [Int] {
        let used = Set(monster.entities.filter { !$0.dead }.map(\.number))
        return (1...monster.maxCount).filter { !used.contains($0) }
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
                                                   characterCount: game.activeCharacters.count)
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
        guard monster.ability >= 0, monster.ability < monster.abilities.count else { return nil }
        let abilityIndex = monster.abilities[monster.ability]
        let allAbilities = abilities(for: monster)
        guard abilityIndex >= 0, abilityIndex < allAbilities.count else { return nil }
        return allAbilities[abilityIndex]
    }

    /// Returns the zero-based index of the currently drawn ability card within the ordered deck array.
    /// Use this with `ImageLoader.monsterAbilityCardURL(deckName:cardIndex:)` to get the card image URL.
    func currentAbilityCardIndex(for monster: GameMonster) -> Int? {
        guard monster.ability >= 0, monster.ability < monster.abilities.count else { return nil }
        return monster.abilities[monster.ability]
    }

    func currentAbilityInitiative(for monster: GameMonster) -> Int? {
        currentAbility(for: monster)?.initiative
    }

    func drawAbility(for monster: GameMonster) {
        monster.ability += 1
        if monster.ability >= monster.abilities.count {
            shuffleAbilities(for: monster)
            monster.ability = 0
        }
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

    /// Apply stat effects (shield, retaliate) from drawn ability card, base stats, and scenario overrides to all alive entities
    func applyStatEffects(for monster: GameMonster) {
        guard let ability = currentAbility(for: monster) else { return }
        let allActions = (ability.actions ?? []) + (ability.bottomActions ?? [])

        for entity in monster.aliveEntities {
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
                let altAbilities = editionStore.abilities(forDeck: name, edition: monster.edition)
                if !altAbilities.isEmpty {
                    monster.deckOverride = name
                    monster.abilities = Array(0..<altAbilities.count).shuffled()
                    monster.ability = -1
                }
            }
        }

        // 2. Explicit deck override
        if let deck = effect.deck {
            monster.deckOverride = deck
            let deckAbilities = editionStore.abilities(forDeck: deck, edition: monster.edition)
            if !deckAbilities.isEmpty {
                monster.abilities = Array(0..<deckAbilities.count).shuffled()
                monster.ability = -1
            }
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
            if persistent {
                entity.shieldPersistent = action
            } else {
                entity.shield = action
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

    func nextStandeeNumber(for monster: GameMonster, type: MonsterType) -> Int {
        let used = Set(monster.entities.filter { !$0.dead }.map(\.number))
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }
}
