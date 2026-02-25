import Foundation

@Observable
final class ScenarioRulesManager {
    private let game: GameState
    private let monsterManager: MonsterManager
    private let entityManager: EntityManager

    /// Called when a rule's `rooms` effect should reveal rooms. Wired from GameManager.
    var onOpenRooms: (([Int]) -> Void)?

    init(game: GameState, monsterManager: MonsterManager, entityManager: EntityManager) {
        self.game = game
        self.monsterManager = monsterManager
        self.entityManager = entityManager
    }

    // MARK: - Rule Evaluation

    func evaluateRules() {
        guard let scenario = game.scenario else { return }
        guard let rules = scenario.data.rules else { return }

        for (index, rule) in rules.enumerated() {
            guard shouldTrigger(rule, index: index, scenario: scenario) else { continue }
            applyRule(rule, index: index, scenario: scenario)
        }
    }

    // MARK: - Trigger Conditions

    private func shouldTrigger(_ rule: ScenarioRule, index: Int, scenario: Scenario) -> Bool {
        let ruleKey = scenario.ruleKey(index: index)

        if scenario.disabledRules.contains(index) { return false }
        if rule.isOnce && scenario.appliedRules.contains(ruleKey) { return false }

        if let requiredRooms = rule.requiredRooms {
            let revealed = Set(scenario.revealedRooms)
            if !Set(requiredRooms).isSubset(of: revealed) { return false }
        }

        if let roundExpr = rule.round {
            if !evaluateRoundCondition(roundExpr, round: game.round) { return false }
        }

        // Check figure-based trigger conditions (dead / present / killed).
        // A rule's figures array may contain both trigger entries and effect entries.
        // All trigger entries must pass for the rule to fire.
        if let figures = rule.figures {
            let triggers = figures.filter { isTriggerType($0.type) }
            if !triggers.isEmpty {
                let allPass = triggers.allSatisfy { evaluateFigureTrigger($0, scenario: scenario) }
                if !allPass { return false }
            }
        }

        return true
    }

    private func isTriggerType(_ type: String?) -> Bool {
        guard let type = type else { return false }
        return ["dead", "present", "killed"].contains(type)
    }

    private func evaluateFigureTrigger(_ figureRule: ScenarioFigureRule, scenario: Scenario) -> Bool {
        guard let type = figureRule.type, let identifier = figureRule.identifier else { return true }
        let edition = identifier.edition ?? scenario.data.edition

        switch type {
        case "dead":
            // All matching alive entities must be gone (either never existed or all dead).
            let alive = findTargets(identifier: identifier, edition: edition)
            return alive.isEmpty

        case "present":
            // At least one matching entity must be alive.
            let alive = findTargets(identifier: identifier, edition: edition)
            return !alive.isEmpty

        case "killed":
            let namePattern = identifier.name ?? ".*"
            let count = totalKills(matching: namePattern, scenario: scenario)
            switch figureRule.value {
            case .string("all"):
                // "all" means every spawned entity of this type is dead.
                return findTargets(identifier: identifier, edition: edition).isEmpty
            case .string(let s):
                return count >= (Int(s) ?? 1)
            case .int(let threshold):
                return count >= threshold
            case nil:
                return count >= 1
            }

        default:
            return true
        }
    }

    private func totalKills(matching namePattern: String, scenario: Scenario) -> Int {
        if namePattern == ".*" {
            return scenario.killCounts.values.reduce(0, +)
        }
        return scenario.killCounts
            .filter { matchesName($0.key, pattern: namePattern) }
            .values.reduce(0, +)
    }

    private func evaluateRoundCondition(_ expr: String, round: Int) -> Bool {
        if expr == "true" { return true }
        if expr == "false" { return false }
        if expr == "start" { return round == 0 }
        if let targetRound = Int(expr) { return round == targetRound }

        let substituted = expr.replacingOccurrences(of: "R", with: "\(round)")
        let predicate = NSPredicate(format: substituted)
        return predicate.evaluate(with: nil)
    }

    // MARK: - Apply Rule Effects

    private func applyRule(_ rule: ScenarioRule, index: Int, scenario: Scenario) {
        let ruleKey = scenario.ruleKey(index: index)
        scenario.appliedRules.insert(ruleKey)

        let edition = scenario.data.edition
        let playerCount = max(2, game.activeCharacters.count)

        // Spawn monsters
        if let spawns = rule.spawns {
            for spawn in spawns {
                guard let monsterType = spawn.monster.monsterType(forPlayerCount: playerCount) else { continue }
                for _ in 0..<spawn.resolvedCount {
                    spawnMonsterEntity(name: spawn.monster.name, type: monsterType,
                                       edition: edition, marker: spawn.marker,
                                       health: spawn.monster.health)
                }
            }
        }

        // Spawn objectives
        if let objectiveSpawns = rule.objectiveSpawns {
            for spawn in objectiveSpawns {
                for i in 0..<spawn.resolvedCount {
                    spawnObjective(spawn.objective, edition: edition, number: i + 1, marker: spawn.marker)
                }
            }
        }

        // Apply figure effects (non-trigger entries only)
        if let figures = rule.figures {
            let effects = figures.filter { !isTriggerType($0.type) }
            for figureRule in effects {
                applyFigureRule(figureRule, edition: edition)
            }
        }

        // Set element states
        if let elements = rule.elements {
            for elementRule in elements { applyElementRule(elementRule) }
        }

        // Reveal rooms as an effect
        if let roomNumbers = rule.rooms, !roomNumbers.isEmpty {
            onOpenRooms?(roomNumbers)
        }

        // Disable other rules
        if let disableRules = rule.disableRules {
            for ruleId in disableRules {
                if let ruleIndex = ruleId.index {
                    let isCurrent = (ruleId.edition == nil || ruleId.edition == scenario.data.edition) &&
                                    (ruleId.scenario == nil || ruleId.scenario == scenario.data.index)
                    if isCurrent { scenario.disabledRules.insert(ruleIndex) }
                }
            }
        }

        // Apply scenario stat effects (monster renames, health overrides, immunities, actions)
        if let statEffects = rule.statEffects, !statEffects.isEmpty {
            applyScenarioStatEffects(statEffects, edition: edition, playerCount: playerCount)
        }

        // Finish condition — signal win or loss via the scenario object.
        // BoardCoordinator.checkVictoryDefeat() reads this on each call.
        if let finish = rule.finish, finish == "won" || finish == "lost" {
            scenario.pendingFinish = finish
        }
    }

    // MARK: - Private: Stat Effects

    private func applyScenarioStatEffects(_ effects: [StatEffectRule], edition: String, playerCount: Int) {
        for effect in effects {
            guard let identifier = effect.identifier,
                  let statEffect = effect.statEffect else { continue }

            // Check reference condition (e.g. "Altar present")
            if let reference = effect.reference {
                guard checkStatEffectReference(reference, edition: edition) else { continue }
            }

            let targetEdition = identifier.edition ?? edition
            let namePattern = identifier.name ?? ".*"

            for monster in game.monsters {
                let editionMatches = identifier.edition == nil || monster.edition == targetEdition
                guard editionMatches, matchesName(monster.name, pattern: namePattern) else { continue }
                monsterManager.applyScenarioStatEffect(statEffect, to: monster, charCount: playerCount)
            }
        }
    }

    private func checkStatEffectReference(_ reference: StatEffectReference, edition: String) -> Bool {
        guard let identifier = reference.identifier, let type = reference.type else { return true }
        let targets = findTargets(identifier: identifier, edition: edition)
        switch type {
        case "present": return !targets.isEmpty
        case "dead":    return targets.isEmpty
        default:        return true
        }
    }

    // MARK: - Private: Spawning

    private func spawnMonsterEntity(name: String, type: MonsterType, edition: String,
                                     marker: String? = nil, health: String? = nil) {
        var monster = game.monsters.first(where: { $0.name == name && $0.edition == edition })
        if monster == nil {
            monsterManager.addMonster(name: name, edition: edition)
            monster = game.monsters.last(where: { $0.name == name && $0.edition == edition })
        }
        guard let monster = monster else { return }

        monster.off = false
        monsterManager.addEntity(type: type, to: monster)

        if let marker = marker, let entity = monster.entities.last {
            entity.markers.append(marker)
        }
        if let healthExpr = health, let entity = monster.entities.last {
            let hp = evaluateEntityValue(.string(healthExpr), level: game.level,
                                          characterCount: game.activeCharacters.count)
            entity.health = hp
            entity.maxHealth = hp
        }
    }

    private func spawnObjective(_ objData: ObjectiveData, edition: String, number: Int, marker: String?) {
        let container = GameObjectiveContainer(
            name: objData.name ?? "Objective",
            edition: edition,
            title: objData.name ?? "",
            escort: objData.isEscort,
            level: game.level
        )
        container.initiative = objData.resolvedInitiative

        if let healthValue = objData.health {
            let hp = evaluateEntityValue(healthValue, level: game.level,
                                          characterCount: game.activeCharacters.count)
            let entity = GameObjectiveEntity(number: number, health: hp, maxHealth: hp)
            if let marker = marker ?? objData.marker { entity.marker = marker }
            container.entities.append(entity)
        }

        game.figures.append(.objective(container))
    }

    // MARK: - Private: Figure Rules

    private func applyFigureRule(_ figureRule: ScenarioFigureRule, edition: String) {
        guard let ruleType = figureRule.type else { return }
        guard let identifier = figureRule.identifier else { return }

        let targets = findTargets(identifier: identifier, edition: edition)

        let valueStr: String?
        switch figureRule.value {
        case .int(let v): valueStr = String(v)
        case .string(let s): valueStr = s
        case nil: valueStr = nil
        }

        for target in targets {
            applyFigureEffect(ruleType, value: valueStr, to: target)
        }
    }

    private func findTargets(identifier: ScenarioFigureRuleIdentifier, edition: String) -> [any Entity] {
        let targetType = identifier.type ?? "monster"
        let namePattern = identifier.name ?? ".*"
        let requiredTags = identifier.tags ?? []
        var results: [any Entity] = []

        func hasTags(_ entity: any Entity) -> Bool {
            guard !requiredTags.isEmpty else { return true }
            return requiredTags.allSatisfy { entity.tags.contains($0) }
        }

        switch targetType {
        case "character", "characterWithSummon":
            for character in game.characters {
                if matchesName(character.name, pattern: namePattern) && hasTags(character) {
                    results.append(character)
                }
            }
        case "monster":
            for monster in game.monsters {
                if matchesName(monster.name, pattern: namePattern) {
                    for entity in monster.aliveEntities {
                        if let markerFilter = identifier.marker {
                            if entity.markers.contains(markerFilter) && hasTags(entity) {
                                results.append(entity)
                            }
                        } else if hasTags(entity) {
                            results.append(entity)
                        }
                    }
                }
            }
        case "objective":
            for figure in game.figures {
                if case .objective(let container) = figure {
                    if matchesName(container.name, pattern: namePattern) {
                        for entity in container.entities where !entity.dead {
                            if let markerFilter = identifier.marker {
                                if entity.marker == markerFilter && hasTags(entity) {
                                    results.append(entity)
                                }
                            } else if hasTags(entity) {
                                results.append(entity)
                            }
                        }
                    }
                }
            }
        default:
            break
        }

        return results
    }

    private func matchesName(_ name: String, pattern: String) -> Bool {
        if pattern == ".*" { return true }
        if pattern == name { return true }
        if let regex = try? NSRegularExpression(pattern: "^\(pattern)$", options: []) {
            let range = NSRange(name.startIndex..., in: name)
            return regex.firstMatch(in: name, options: [], range: range) != nil
        }
        return false
    }

    private func applyFigureEffect(_ type: String, value: String?, to entity: any Entity) {
        switch type {
        case "damage":
            let amount = Int(value ?? "1") ?? 1
            entityManager.changeHealth(entity, amount: -amount)

        case "heal":
            let amount = Int(value ?? "1") ?? 1
            entityManager.changeHealth(entity, amount: amount)

        case "setHp":
            if let hpStr = value {
                let hp = evaluateEntityValue(.string(hpStr), level: game.level,
                                              characterCount: game.activeCharacters.count)
                entity.health = hp
            }

        case "condition", "gainCondition":
            if let condStr = value, let cond = ConditionName(rawValue: condStr) {
                entityManager.addCondition(cond, to: entity)
            }

        case "permanentCondition":
            if let condStr = value, let cond = ConditionName(rawValue: condStr) {
                entityManager.addCondition(cond, to: entity, permanent: true)
            }

        case "removeCondition":
            if let condStr = value, let cond = ConditionName(rawValue: condStr) {
                entityManager.removeCondition(cond, from: entity)
            }

        case "remove":
            if let monsterEntity = entity as? GameMonsterEntity {
                monsterEntity.dead = true
            } else if let objectiveEntity = entity as? GameObjectiveEntity {
                objectiveEntity.dead = true
            }

        case "toggleOff", "dormant":
            entity.off = true

        case "toggleOn", "activate":
            entity.off = false

        case "amAdd":
            // value format: "type:count" e.g. "curse:3", "minus1:3", "bless:2"
            applyAmAdd(value: value, to: entity)

        default:
            break
        }
    }

    // MARK: - amAdd helper

    /// Adds attack modifier cards to a character's AM deck.
    /// value format: "{cardType}:{count}", e.g. "curse:3", "minus1:2"
    private func applyAmAdd(value: String?, to entity: any Entity) {
        guard let character = entity as? GameCharacter,
              let value = value else { return }

        let parts = value.split(separator: ":", maxSplits: 1)
        let typeName = parts.first.map(String.init) ?? value
        let count = parts.count > 1 ? Int(String(parts[1])) ?? 1 : 1

        guard let cardType = AttackModifierType(rawValue: typeName) else { return }

        let card = makeAmCard(type: cardType)
        for _ in 0..<count {
            character.attackModifierDeck.cards.append(card)
        }
    }

    private func makeAmCard(type: AttackModifierType) -> AttackModifier {
        switch type {
        case .curse:
            return AttackModifier(type: .curse, value: 0, valueType: .multiply, shuffle: true)
        case .bless:
            return AttackModifier(type: .bless, value: 2, valueType: .multiply, shuffle: true)
        default:
            return AttackModifier(type: type)
        }
    }

    // MARK: - Private: Element Rules

    private func applyElementRule(_ elementRule: ElementRuleData) {
        guard let typeName = elementRule.type,
              let stateName = elementRule.state,
              let elementType = ElementType(rawValue: typeName),
              let elementState = ElementState(rawValue: stateName) else { return }

        if let idx = game.elementBoard.firstIndex(where: { $0.type == elementType }) {
            game.elementBoard[idx].state = elementState
        }
    }
}
