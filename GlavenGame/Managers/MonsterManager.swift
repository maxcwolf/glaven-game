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
        let hp = evaluateEntityValue(stat.health ?? .int(0), level: monster.level, characterCount: game.activeCharacters.count)
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
        let deckName = monster.monsterData?.deck ?? monster.name
        return editionStore.abilities(forDeck: deckName, edition: monster.edition)
    }

    func currentAbility(for monster: GameMonster) -> AbilityModel? {
        guard monster.ability >= 0, monster.ability < monster.abilities.count else { return nil }
        let abilityIndex = monster.abilities[monster.ability]
        let allAbilities = abilities(for: monster)
        guard abilityIndex >= 0, abilityIndex < allAbilities.count else { return nil }
        return allAbilities[abilityIndex]
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

    /// Apply stat effects (shield, retaliate) from drawn ability card and base stats to all alive entities
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

            // Apply ability card actions (round-based effects)
            for action in allActions {
                applyStatAction(action, to: entity, persistent: ability.persistent == true)
            }
        }
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
