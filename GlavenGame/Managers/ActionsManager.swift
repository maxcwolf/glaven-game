import Foundation

/// Handles interactive action processing for monster/entity abilities.
@Observable
final class ActionsManager {
    private let game: GameState
    private let monsterManager: MonsterManager
    var onBeforeMutate: (() -> Void)?

    init(game: GameState, monsterManager: MonsterManager) {
        self.game = game
        self.monsterManager = monsterManager
    }

    // MARK: - Action Hints

    /// Calculate action hints (shield, retaliate) for an entity.
    func calcActionHints(figure: any Figure, entity: any Entity) -> [ActionHint] {
        var hints: [ActionHint] = []

        // Shield from entity stat effects
        if let shield = entity.shield {
            let value = shield.value?.intValue ?? 0
            let range = extractRange(from: shield.subActions)
            if value > 0 {
                hints.append(ActionHint(type: .shield, value: value, range: range))
            }
        }
        if let shield = entity.shieldPersistent {
            let value = shield.value?.intValue ?? 0
            let range = extractRange(from: shield.subActions)
            if value > 0 {
                hints.append(ActionHint(type: .shield, value: value, range: range))
            }
        }

        // Retaliate from entity stat effects
        for ret in entity.retaliate + entity.retaliatePersistent {
            let value = ret.value?.intValue ?? 0
            let range = extractRange(from: ret.subActions)
            if value > 0 {
                hints.append(ActionHint(type: .retaliate, value: value, range: range))
            }
        }

        // Monster ability card actions
        if let monster = figure as? GameMonster {
            let abilityHints = calcMonsterAbilityHints(monster: monster, entity: entity)
            hints.append(contentsOf: abilityHints)
        }

        // Sort: shields first, then by range
        hints.sort { a, b in
            if a.type != b.type { return a.type == .shield }
            return a.range < b.range
        }

        return hints
    }

    private func calcMonsterAbilityHints(monster: GameMonster, entity: any Entity) -> [ActionHint] {
        guard let ability = monsterManager.currentAbility(for: monster) else { return [] }
        var hints: [ActionHint] = []

        for action in ability.actions ?? [] {
            collectHints(from: action, entity: entity, into: &hints)
        }

        return hints
    }

    private func collectHints(from action: ActionModel, entity: any Entity, into hints: inout [ActionHint]) {
        switch action.type {
        case .shield:
            let value = action.value?.intValue ?? 0
            let range = extractRange(from: action.subActions)
            if value > 0 {
                hints.append(ActionHint(type: .shield, value: value, range: range))
            }
        case .retaliate:
            let value = action.value?.intValue ?? 0
            let range = extractRange(from: action.subActions)
            if value > 0 {
                hints.append(ActionHint(type: .retaliate, value: value, range: range))
            }
        case .monsterType:
            // Only process if entity matches the monster type section
            if let monsterEntity = entity as? GameMonsterEntity {
                let typeStr = action.value?.stringValue ?? ""
                if typeStr == monsterEntity.type.rawValue {
                    for sub in action.subActions ?? [] {
                        collectHints(from: sub, entity: entity, into: &hints)
                    }
                }
            }
        default:
            break
        }

        // Recurse into subactions for non-monsterType actions
        if action.type != .monsterType {
            for sub in action.subActions ?? [] {
                collectHints(from: sub, entity: entity, into: &hints)
            }
        }
    }

    private func extractRange(from subActions: [ActionModel]?) -> Int {
        guard let subs = subActions else { return 0 }
        for sub in subs {
            if sub.type == .range {
                return sub.value?.intValue ?? 0
            }
        }
        return 0
    }

    // MARK: - Interactive Actions

    /// Check if an action is interactive (requires user interaction).
    func isInteractiveAction(_ action: ActionModel) -> Bool {
        switch action.type {
        case .heal:
            // Self-targeted heal (has condition subaction or is self)
            return hasSelfTarget(action)
        case .condition:
            return hasSelfTarget(action)
        case .sufferDamage:
            return true
        case .switchType:
            return true
        case .element:
            return true
        case .spawn, .summon:
            return true
        default:
            return false
        }
    }

    /// Get all applicable interactive actions for an entity.
    func getInteractiveActions(entity: any Entity, figure: any Figure, actions: [ActionModel], preIndex: String = "") -> [InteractiveAction] {
        var result: [InteractiveAction] = []

        for (i, action) in actions.enumerated() {
            let index = preIndex.isEmpty ? "\(i)" : "\(preIndex)-\(i)"

            if isInteractiveAction(action) && isApplicable(entity: entity, action: action, index: index) {
                result.append(InteractiveAction(action: action, index: index))
            }

            // Check monsterType sections
            if action.type == .monsterType, let entity = entity as? GameMonsterEntity {
                let typeStr = action.value?.stringValue ?? ""
                if typeStr == entity.type.rawValue {
                    let subResults = getInteractiveActions(entity: entity, figure: figure,
                                                           actions: action.subActions ?? [], preIndex: index)
                    result.append(contentsOf: subResults)
                }
            } else if let subs = action.subActions {
                let subResults = getInteractiveActions(entity: entity, figure: figure,
                                                       actions: subs, preIndex: index)
                result.append(contentsOf: subResults)
            }
        }

        return result
    }

    /// Get all unique interactive actions for all entities of a figure.
    func getAllInteractiveActions(figure: any Figure, actions: [ActionModel]) -> [InteractiveAction] {
        var seen: Set<String> = []
        var result: [InteractiveAction] = []

        let entities = entitiesForFigure(figure)
        for entity in entities {
            let entityActions = getInteractiveActions(entity: entity, figure: figure, actions: actions)
            for ia in entityActions {
                if !seen.contains(ia.index) {
                    seen.insert(ia.index)
                    result.append(ia)
                }
            }
        }

        return result
    }

    /// Check if an interactive action is applicable to this entity right now.
    func isApplicable(entity: any Entity, action: ActionModel, index: String) -> Bool {
        // Already applied this round
        let tag = "action-\(index)"
        if entity.tags.contains(tag) { return false }

        // Dead entities can't act
        if entity.health <= 0 { return false }

        switch action.type {
        case .heal:
            // Can heal if health < max, or conditions can be removed
            return entity.health < entity.maxHealth ||
                   entity.entityConditions.contains(where: { $0.name.isNegative && !$0.permanent })
        case .condition:
            let condName = action.value?.stringValue ?? ""
            guard let cond = ConditionName(rawValue: condName) else { return false }
            return !entity.entityConditions.contains(where: { $0.name == cond })
        case .sufferDamage:
            return entity.health > 0
        case .switchType:
            // Only for monster entities
            if let me = entity as? GameMonsterEntity {
                return me.type == .normal || me.type == .elite
            }
            return false
        case .element:
            let values = getValues(action)
            if values.isEmpty { return false }
            // Consume: check if element is available on board
            if action.valueType == nil || action.valueType == .fixed {
                // Infuse: always applicable
                return true
            }
            // Consume element
            for val in values {
                if let elemType = ElementType(rawValue: val) {
                    let elem = game.elementBoard.first(where: { $0.type == elemType })
                    if let elem, elem.state == .strong || elem.state == .waning {
                        return true
                    }
                }
                if val == "wild" { return true }
            }
            return false
        case .spawn, .summon:
            return true
        default:
            return false
        }
    }

    // MARK: - Apply Interactive Actions

    /// Apply an interactive action to an entity.
    func applyInteractiveAction(entity: any Entity, figure: any Figure, interactiveAction: InteractiveAction) {
        onBeforeMutate?()

        let action = interactiveAction.action
        let tag = "action-\(interactiveAction.index)"

        switch action.type {
        case .heal:
            let amount = action.value?.intValue ?? 0
            entity.health = min(entity.maxHealth, entity.health + amount)
            // Apply heal-related conditions from subactions
            for sub in action.subActions ?? [] {
                if sub.type == .condition, let condName = sub.value?.stringValue,
                   let cond = ConditionName(rawValue: condName) {
                    if !entity.entityConditions.contains(where: { $0.name == cond }) {
                        entity.entityConditions.append(EntityCondition(name: cond))
                    }
                }
            }
            entity.tags.append(tag)

        case .condition:
            if let condName = action.value?.stringValue, let cond = ConditionName(rawValue: condName) {
                if cond == .bless || cond == .curse {
                    // Add to attack modifier deck instead
                    handleBlessing(cond, figure: figure)
                } else {
                    if !entity.entityConditions.contains(where: { $0.name == cond }) {
                        entity.entityConditions.append(EntityCondition(name: cond))
                    }
                }
            }
            entity.tags.append(tag)

        case .sufferDamage:
            let amount = action.value?.intValue ?? 0
            entity.health = max(0, entity.health - amount)
            entity.tags.append(tag)

        case .switchType:
            if let me = entity as? GameMonsterEntity {
                switchMonsterType(me, in: figure as? GameMonster)
            }
            entity.tags.append(tag)

        case .element:
            let values = getValues(action)
            for val in values {
                if let elemType = ElementType(rawValue: val) {
                    let isConsume = action.valueType == .minus || action.valueType == .subtract
                    if isConsume {
                        consumeElement(elemType)
                    } else {
                        infuseElement(elemType)
                    }
                }
            }
            // Tag all entities of this figure for element actions
            for ent in entitiesForFigure(figure) {
                if !ent.tags.contains(tag) {
                    ent.tags.append(tag)
                }
            }

        case .spawn:
            // Spawn handled by MonsterManager — just mark as applied
            entity.tags.append(tag)

        case .summon:
            entity.tags.append(tag)

        default:
            entity.tags.append(tag)
        }
    }

    // MARK: - Round Lifecycle

    /// Clear all action tags at end of round.
    func clearActionTags() {
        for figure in game.figures {
            switch figure {
            case .monster(let m):
                for entity in m.entities {
                    entity.tags.removeAll { $0.hasPrefix("action-") }
                }
            case .character(let c):
                c.tags.removeAll { $0.hasPrefix("action-") }
            case .objective(let o):
                for entity in o.entities {
                    entity.tags.removeAll { $0.hasPrefix("action-") }
                }
            }
        }
    }

    // MARK: - Helpers

    func getValues(_ action: ActionModel) -> [String] {
        guard let value = action.value?.stringValue else { return [] }
        return value.split(separator: ":").map(String.init)
    }

    func isMultiTarget(_ action: ActionModel) -> Bool {
        if let subs = action.subActions {
            for sub in subs {
                if sub.type == .target, let val = sub.value?.intValue, val > 1 {
                    return true
                }
            }
        }
        return false
    }

    private func hasSelfTarget(_ action: ActionModel) -> Bool {
        // An action is self-targeted if it has no target subaction, or target is "self"
        guard let subs = action.subActions else { return true }
        for sub in subs {
            if sub.type == .target {
                if let val = sub.value?.stringValue, val.lowercased() == "self" { return true }
                return false
            }
        }
        return true
    }

    private func entitiesForFigure(_ figure: any Figure) -> [any Entity] {
        if let monster = figure as? GameMonster {
            return monster.aliveEntities
        }
        if let character = figure as? GameCharacter {
            return [character] as [any Entity]
        }
        return []
    }

    private func handleBlessing(_ condition: ConditionName, figure: any Figure) {
        if figure is GameMonster {
            if condition == .bless {
                game.monsterAttackModifierDeck.addCard(type: .bless)
            } else if condition == .curse {
                game.monsterAttackModifierDeck.addCard(type: .curse)
            }
        }
    }

    private func switchMonsterType(_ entity: GameMonsterEntity, in monster: GameMonster?) {
        guard let monster else { return }
        let newType: MonsterType = entity.type == .normal ? .elite : .normal
        if let newStat = monster.stat(for: newType) {
            let healthDiff = entity.maxHealth - entity.health
            entity.type = newType
            entity.maxHealth = newStat.health?.intValue ?? entity.maxHealth
            entity.health = max(1, entity.maxHealth - healthDiff)
        }
    }

    private func consumeElement(_ type: ElementType) {
        if let idx = game.elementBoard.firstIndex(where: { $0.type == type }) {
            let current = game.elementBoard[idx].state
            if current == .strong || current == .waning {
                game.elementBoard[idx].state = .consumed
            }
        }
    }

    private func infuseElement(_ type: ElementType) {
        if let idx = game.elementBoard.firstIndex(where: { $0.type == type }) {
            let current = game.elementBoard[idx].state
            if current == .inert || current == .consumed {
                game.elementBoard[idx].state = .new
            }
        }
    }
}

// MARK: - Supporting Types

struct ActionHint: Identifiable {
    var id: String { "\(type.rawValue)-\(value)-\(range)" }
    var type: ActionType
    var value: Int
    var range: Int = 0
}

struct InteractiveAction: Identifiable {
    var id: String { index }
    var action: ActionModel
    var index: String
}
