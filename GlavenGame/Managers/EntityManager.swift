import Foundation

@Observable
final class EntityManager {
    private let game: GameState
    var onBeforeMutate: (() -> Void)?
    var scenarioStatsManager: ScenarioStatsManager?

    init(game: GameState) {
        self.game = game
    }

    func isAlive(_ entity: any Entity) -> Bool {
        entity.health > 0
    }

    func changeHealth(_ entity: any Entity, amount: Int) {
        onBeforeMutate?()
        let oldHealth = entity.health
        entity.health = max(0, min(entity.maxHealth, entity.health + amount))
        let actualChange = entity.health - oldHealth

        // Record stats for characters
        if let charName = characterName(for: entity) {
            if actualChange < 0 {
                scenarioStatsManager?.recordDamageTaken(by: charName, amount: -actualChange)
            } else if actualChange > 0 {
                scenarioStatsManager?.recordHeal(by: charName, amount: actualChange)
            }
        }

        // Check for death
        if entity.health <= 0 {
            if let monsterEntity = entity as? GameMonsterEntity {
                monsterEntity.dead = true
            } else if let summon = entity as? GameSummon {
                summon.dead = true
            } else if let character = entity as? GameCharacter {
                character.exhausted = true
            }
        }
    }

    func addCondition(_ conditionName: ConditionName, to entity: any Entity, value: Int = 0) {
        onBeforeMutate?()
        // Check immunity
        if entity.immunities.contains(conditionName) { return }

        // Check if already exists
        if let idx = entity.entityConditions.firstIndex(where: { $0.name == conditionName }) {
            // Update value for stackable conditions
            let types = Condition.conditionTypes(for: conditionName)
            if types.contains(.stack) || types.contains(.stackable) {
                entity.entityConditions[idx].value += max(1, value)
            }
            return
        }

        let condition = EntityCondition(name: conditionName, value: value)
        entity.entityConditions.append(condition)

        // Record stats
        if let charName = characterName(for: entity) {
            scenarioStatsManager?.recordConditionReceived(by: charName)
        }
    }

    func removeCondition(_ conditionName: ConditionName, from entity: any Entity) {
        onBeforeMutate?()
        entity.entityConditions.removeAll { $0.name == conditionName && !$0.permanent }
    }

    func hasCondition(_ conditionName: ConditionName, on entity: any Entity) -> Bool {
        entity.entityConditions.contains { $0.name == conditionName && $0.state != .removed }
    }

    func restoreConditions(_ entity: any Entity) {
        for i in entity.entityConditions.indices {
            if entity.entityConditions[i].expired {
                entity.entityConditions[i].expired = false
                entity.entityConditions[i].state = .normal
            }
            if entity.entityConditions[i].state == .new {
                entity.entityConditions[i].state = .normal
            }
        }
    }

    func applyConditionsTurn(_ entity: any Entity) {
        for i in entity.entityConditions.indices {
            let condition = entity.entityConditions[i]
            guard condition.state == .normal else { continue }

            let types = condition.types

            // Wound: deal 1 damage at start of turn
            if condition.name == .wound && types.contains(.apply) {
                changeHealth(entity, amount: -1)
            }

            // Regenerate: heal 1 at start of turn
            if condition.name == .regenerate && types.contains(.apply) {
                changeHealth(entity, amount: 1)
                // Regenerate expires after healing
                entity.entityConditions[i].state = .expire
                entity.entityConditions[i].expired = true
            }

            // Mark turn-type conditions
            if types.contains(.turn) {
                entity.entityConditions[i].state = .turn
            }
        }
    }

    func expireConditions(_ entity: any Entity) {
        for i in entity.entityConditions.indices.reversed() {
            let condition = entity.entityConditions[i]
            let types = condition.types

            if condition.permanent { continue }

            // Turn conditions expire at end of turn
            if condition.state == .turn {
                entity.entityConditions[i].state = .removed
            }

            // AfterTurn conditions expire
            if types.contains(.afterTurn) && condition.state == .normal {
                entity.entityConditions[i].state = .expire
                entity.entityConditions[i].expired = true
            }
        }

        // Remove fully removed conditions
        entity.entityConditions.removeAll { $0.state == .removed }
    }

    private func characterName(for entity: any Entity) -> String? {
        if let c = entity as? GameCharacter { return c.name }
        return nil
    }
}
