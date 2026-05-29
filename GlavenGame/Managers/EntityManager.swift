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
        var adjustedAmount = amount

        if amount < 0 {
            // Brittle (FH): double damage from next source, then remove
            if hasCondition(.brittle, on: entity) {
                adjustedAmount = amount * 2
                entity.entityConditions.removeAll { $0.name == .brittle }
            }
            // Ward (FH): halve damage from next source (rounded down), then remove
            if hasCondition(.ward, on: entity) {
                adjustedAmount = adjustedAmount / 2
                entity.entityConditions.removeAll { $0.name == .ward }
            }
        } else if amount > 0 {
            // Infect (FH): prevent all healing
            if hasCondition(.infect, on: entity) {
                adjustedAmount = 0
            }
        }

        let oldHealth = entity.health
        entity.health = max(0, min(entity.maxHealth, entity.health + adjustedAmount))
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
            } else if let objectiveEntity = entity as? GameObjectiveEntity {
                objectiveEntity.dead = true
            } else if let summon = entity as? GameSummon {
                summon.dead = true
            } else if let character = entity as? GameCharacter {
                character.exhausted = true
            }
        }
    }

    func addCondition(_ conditionName: ConditionName, to entity: any Entity, value: Int = 0, permanent: Bool = false) {
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
            if permanent { entity.entityConditions[idx].permanent = true }
            return
        }

        var condition = EntityCondition(name: conditionName, value: value)
        condition.permanent = permanent
        entity.entityConditions.append(condition)

        // Rupture (FH): suffer 1 damage when gaining a positive condition
        if conditionName.isPositive && hasCondition(.rupture, on: entity) {
            changeHealth(entity, amount: -1)
        }

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

            // Wound: deal 1 damage at start of turn (persists until removed)
            if condition.name == .wound && types.contains(.apply) {
                changeHealth(entity, amount: -1)
            }

            // Regenerate (FH): heal 1 at start of each turn. Persistent — it is NOT a
            // one-shot; the figure keeps regenerating every turn until the condition is
            // removed. (Bane is handled at the END of the turn, in expireConditions.)
            if condition.name == .regenerate && types.contains(.apply) {
                changeHealth(entity, amount: 1)
            }

            // Mark turn-type conditions
            if types.contains(.turn) {
                entity.entityConditions[i].state = .turn
            }
        }
    }

    func expireConditions(_ entity: any Entity) {
        // Bane deals its damage at the end of the figure's turn; defer the actual
        // health change until after the loop so we never mutate entityConditions
        // (changeHealth can strip brittle/ward) while iterating it by index.
        var baneDamage = 0

        for i in entity.entityConditions.indices {
            let condition = entity.entityConditions[i]
            let types = condition.types

            if condition.permanent { continue }

            // Turn conditions (e.g. stun) expire at end of turn.
            if condition.state == .turn {
                entity.entityConditions[i].state = .removed
            }

            // AfterTurn conditions (immobilize/disarm/muddle/impair/strengthen/dodge/
            // invisible/safeguard/bane) are active during the figure's next turn and
            // are then REMOVED at the end of it. Marking them .removed (rather than a
            // self-healing .expire/expired) prevents restoreConditions from reviving
            // them on the following turn.
            if types.contains(.afterTurn) && condition.state == .normal {
                // Bane (FH): suffer 10 damage at the end of the figure's next turn.
                if condition.name == .bane {
                    baneDamage += 10
                }
                entity.entityConditions[i].state = .removed
            }
        }

        // Remove fully removed conditions, then apply any deferred bane damage.
        entity.entityConditions.removeAll { $0.state == .removed }
        if baneDamage > 0 {
            changeHealth(entity, amount: -baneDamage)
        }
    }

    private func characterName(for entity: any Entity) -> String? {
        if let c = entity as? GameCharacter { return c.name }
        return nil
    }
}
