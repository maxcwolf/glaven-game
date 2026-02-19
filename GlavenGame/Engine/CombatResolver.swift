import Foundation

/// Result of resolving a single attack.
struct AttackResult {
    let attacker: PieceID
    let defender: PieceID
    /// Base attack value before modifier.
    let baseAttack: Int
    /// The modifier card drawn.
    let modifierCard: AttackModifier?
    /// Final damage dealt (after shield, floor at 0).
    let damage: Int
    /// Whether this was a null/miss.
    let isMiss: Bool
    /// Whether this was a critical (2x).
    let isCritical: Bool
    /// Conditions applied to the defender.
    let appliedConditions: [ConditionName]
    /// Whether the defender was killed.
    let killed: Bool
    /// Retaliate damage dealt back to attacker (0 if none or out of range).
    let retaliateDamage: Int
}

/// Resolves attacks using the Gloomhaven attack pipeline.
enum CombatResolver {

    /// Resolve a full attack.
    /// - Parameters:
    ///   - attacker: The attacking piece
    ///   - defender: The defending piece
    ///   - baseAttack: Base attack value (from stat card + ability card)
    ///   - advantage: Whether attacker has advantage
    ///   - disadvantage: Whether attacker has disadvantage
    ///   - isPoisoned: Whether the defender is poisoned (+1 to attack)
    ///   - shield: Defender's shield value
    ///   - pierce: Attacker's pierce value (ignores shield)
    ///   - conditions: Conditions to apply from the attack (ability card effects)
    ///   - attackerIsAdjacent: Whether attacker is adjacent to defender (for retaliate)
    ///   - retaliateValue: Defender's retaliate damage
    ///   - retaliateRange: Defender's retaliate range
    ///   - attackerDefenderDistance: Distance between attacker and defender
    ///   - drawModifier: Closure to draw from the appropriate modifier deck
    ///   - defenderHealth: Defender's current health
    static func resolveAttack(
        attacker: PieceID,
        defender: PieceID,
        baseAttack: Int,
        advantage: Bool = false,
        disadvantage: Bool = false,
        isPoisoned: Bool = false,
        shield: Int = 0,
        pierce: Int = 0,
        conditions: [ConditionName] = [],
        retaliateValue: Int = 0,
        retaliateRange: Int = 1,
        attackerDefenderDistance: Int = 1,
        drawModifier: () -> AttackModifier?,
        defenderHealth: Int
    ) -> AttackResult {
        // 1. Start with base attack value
        var attackValue = baseAttack

        // 2. Add poison bonus (+1 to incoming attack if defender is poisoned)
        if isPoisoned {
            attackValue += 1
        }

        // 3. Draw modifier card(s)
        let modifier: AttackModifier?
        if advantage && !disadvantage {
            // Advantage: draw two, use better
            let card1 = drawModifier()
            let card2 = drawModifier()
            modifier = betterCard(card1, card2)
        } else if disadvantage && !advantage {
            // Disadvantage: draw two, use worse
            let card1 = drawModifier()
            let card2 = drawModifier()
            modifier = worseCard(card1, card2)
        } else {
            // Normal draw (or advantage + disadvantage cancel out)
            modifier = drawModifier()
        }

        // 4. Apply modifier
        var isMiss = false
        var isCritical = false
        var modifierConditions: [ConditionName] = []

        if let mod = modifier {
            if mod.valueType == .multiply {
                if mod.value == 0 {
                    // Null / Miss
                    attackValue = 0
                    isMiss = true
                } else {
                    // 2x critical
                    attackValue *= mod.value
                    isCritical = mod.value >= 2
                }
            } else {
                // Additive modifier
                attackValue += mod.value
            }

            // Collect conditions from modifier card effects
            for effect in mod.effects {
                if let condition = conditionFromEffect(effect) {
                    modifierConditions.append(condition)
                }
            }
        }

        // 5. Apply shield (reduced by pierce)
        let effectiveShield = max(0, shield - pierce)
        if !isMiss {
            attackValue = max(0, attackValue - effectiveShield)
        }

        // 6. Floor at 0
        let finalDamage = max(0, attackValue)

        // 7. Determine conditions to apply
        // On a miss (null): no conditions from the attack, but modifier card conditions still apply per FAQ
        // Actually per official FAQ: on a null, NO conditions apply at all (neither from card nor modifier)
        let appliedConditions: [ConditionName]
        if isMiss {
            appliedConditions = []
        } else {
            appliedConditions = conditions + modifierConditions
        }

        // 8. Check if defender is killed
        let killed = defenderHealth - finalDamage <= 0 && !isMiss

        // 9. Check retaliate
        let retaliateDamage: Int
        if retaliateValue > 0 && attackerDefenderDistance <= retaliateRange && !killed {
            retaliateDamage = retaliateValue
        } else {
            retaliateDamage = 0
        }

        return AttackResult(
            attacker: attacker,
            defender: defender,
            baseAttack: baseAttack,
            modifierCard: modifier,
            damage: finalDamage,
            isMiss: isMiss,
            isCritical: isCritical,
            appliedConditions: appliedConditions,
            killed: killed,
            retaliateDamage: retaliateDamage
        )
    }

    // MARK: - Advantage / Disadvantage

    /// Pick the better of two modifier cards.
    private static func betterCard(_ a: AttackModifier?, _ b: AttackModifier?) -> AttackModifier? {
        guard let a = a else { return b }
        guard let b = b else { return a }
        return cardScore(a) >= cardScore(b) ? a : b
    }

    /// Pick the worse of two modifier cards.
    private static func worseCard(_ a: AttackModifier?, _ b: AttackModifier?) -> AttackModifier? {
        guard let a = a else { return b }
        guard let b = b else { return a }
        return cardScore(a) <= cardScore(b) ? a : b
    }

    /// Numeric score for comparing modifier cards.
    private static func cardScore(_ card: AttackModifier) -> Int {
        if card.valueType == .multiply {
            return card.value == 0 ? -100 : card.value * 50
        }
        return card.value
    }

    // MARK: - Helpers

    /// Extract a condition name from a modifier card effect.
    private static func conditionFromEffect(_ effect: AttackModifierEffect) -> ConditionName? {
        guard effect.type == .condition else { return nil }
        guard let value = effect.value?.stringValue else { return nil }
        return ConditionName(rawValue: value)
    }

    /// Compute total shield value for an entity from its shield actions.
    static func totalShield(shield: ActionModel?, shieldPersistent: ActionModel?) -> Int {
        var total = 0
        if let s = shield, let val = s.value?.intValue { total += val }
        if let s = shieldPersistent, let val = s.value?.intValue { total += val }
        return total
    }

    /// Compute total retaliate value and range.
    static func retaliateInfo(retaliate: [ActionModel], retaliatePersistent: [ActionModel]) -> (value: Int, range: Int) {
        var totalValue = 0
        var maxRange = 1

        for r in retaliate + retaliatePersistent {
            if let val = r.value?.intValue {
                totalValue += val
            }
            // Check subActions for range
            for sub in r.subActions ?? [] {
                if sub.type == .range, let rangeVal = sub.value?.intValue {
                    maxRange = max(maxRange, rangeVal)
                }
            }
        }

        return (totalValue, maxRange)
    }

    /// Check if an entity has a specific condition active.
    static func hasCondition(_ condition: ConditionName, on entity: any Entity) -> Bool {
        entity.entityConditions.contains(where: { $0.name == condition && !$0.expired })
    }

    /// Determine if an attack has advantage based on conditions.
    static func hasAdvantage(attacker: any Entity) -> Bool {
        hasCondition(.strengthen, on: attacker)
    }

    /// Determine if an attack has disadvantage.
    static func hasDisadvantage(attacker: any Entity, isRangedAdjacent: Bool) -> Bool {
        hasCondition(.muddle, on: attacker) || isRangedAdjacent
    }
}
