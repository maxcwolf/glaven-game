import Foundation

@Observable
final class ScenarioRulesManager {
    private let game: GameState
    private let monsterManager: MonsterManager
    private let entityManager: EntityManager

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

        // Check if rule is disabled
        if scenario.disabledRules.contains(index) { return false }

        // Once-only rules that have already fired
        if rule.isOnce && scenario.appliedRules.contains(ruleKey) { return false }

        // Check required rooms
        if let requiredRooms = rule.requiredRooms {
            let revealed = Set(scenario.revealedRooms)
            if !Set(requiredRooms).isSubset(of: revealed) { return false }
        }

        // Check round condition
        if let roundExpr = rule.round {
            if !evaluateRoundCondition(roundExpr, round: game.round) { return false }
        }

        return true
    }

    private func evaluateRoundCondition(_ expr: String, round: Int) -> Bool {
        // Handle simple cases
        if expr == "true" { return true }
        if expr == "false" { return false }
        if expr == "start" { return round == 0 }

        // Try evaluating as plain number
        if let targetRound = Int(expr) {
            return round == targetRound
        }

        // Evaluate expression with R variable substitution
        let substituted = expr.replacingOccurrences(of: "R", with: "\(round)")

        // Try NSPredicate for comparison expressions (e.g. "3 % 2 == 1")
        let predicate = NSPredicate(format: substituted)
        return predicate.evaluate(with: nil)
    }

    // MARK: - Apply Rule Effects

    private func applyRule(_ rule: ScenarioRule, index: Int, scenario: Scenario) {
        let ruleKey = scenario.ruleKey(index: index)

        // Mark as applied
        scenario.appliedRules.insert(ruleKey)

        let edition = scenario.data.edition
        let playerCount = max(2, game.activeCharacters.count)

        // Spawn monsters
        if let spawns = rule.spawns {
            for spawn in spawns {
                guard let monsterType = spawn.monster.monsterType(forPlayerCount: playerCount) else { continue }
                let count = spawn.resolvedCount
                for _ in 0..<count {
                    spawnMonsterEntity(name: spawn.monster.name, type: monsterType,
                                       edition: edition, marker: spawn.marker,
                                       health: spawn.monster.health)
                }
            }
        }

        // Spawn objectives
        if let objectiveSpawns = rule.objectiveSpawns {
            for spawn in objectiveSpawns {
                let count = spawn.resolvedCount
                for i in 0..<count {
                    spawnObjective(spawn.objective, edition: edition, number: i + 1, marker: spawn.marker)
                }
            }
        }

        // Apply figure rules
        if let figures = rule.figures {
            for figureRule in figures {
                applyFigureRule(figureRule, edition: edition)
            }
        }

        // Set element states
        if let elements = rule.elements {
            for elementRule in elements {
                applyElementRule(elementRule)
            }
        }

        // Disable other rules
        if let disableRules = rule.disableRules {
            for ruleId in disableRules {
                if let ruleIndex = ruleId.index {
                    // Check if it refers to current scenario
                    let isCurrentScenario = (ruleId.edition == nil || ruleId.edition == scenario.data.edition) &&
                                            (ruleId.scenario == nil || ruleId.scenario == scenario.data.index)
                    if isCurrentScenario {
                        scenario.disabledRules.insert(ruleIndex)
                    }
                }
            }
        }

        // Finish condition
        if let finish = rule.finish {
            switch finish {
            case "won":
                // Signal scenario won — UI will show conclusion
                break
            case "lost":
                // Signal scenario lost
                break
            default:
                break
            }
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
            if let marker = marker ?? objData.marker {
                entity.marker = marker
            }
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
        var results: [any Entity] = []

        switch targetType {
        case "character", "characterWithSummon":
            for character in game.characters {
                if matchesName(character.name, pattern: namePattern) {
                    results.append(character)
                }
            }
        case "monster":
            for monster in game.monsters {
                if matchesName(monster.name, pattern: namePattern) {
                    for entity in monster.aliveEntities {
                        if let markerFilter = identifier.marker {
                            if entity.markers.contains(markerFilter) {
                                results.append(entity)
                            }
                        } else {
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
                            results.append(entity)
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
        // Try regex match
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
        case "condition":
            if let condStr = value, let cond = ConditionName(rawValue: condStr) {
                entityManager.addCondition(cond, to: entity)
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
        case "toggleOff":
            entity.off = true
        case "toggleOn":
            entity.off = false
        default:
            break
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
