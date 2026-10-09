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
    /// Every condition the attack carries (ability + modifier cards), for callers that resolve
    /// the target's death themselves (e.g. after a character negates the damage).
    var allConditions: [ConditionName] = []
    /// Push/pull added by drawn modifier cards.
    var modifierPush: Int = 0
    var modifierPull: Int = 0
    /// What drawn modifier cards give the attacker (p.19): positive conditions (a Scoundrel's
    /// Invisible), "Heal X, self", "Shield X, self" for the round, element infusions, and items
    /// to refresh.
    var attackerEffects = ModifierSelfEffects()
}

/// Effects of attack modifier cards that go to the attacker rather than the target.
struct ModifierSelfEffects: Equatable {
    var conditions: [ConditionName] = []
    var heal = 0
    var shield = 0
    var infusions: [ElementType] = []
    var itemsToRefresh = 0

    var isEmpty: Bool { self == ModifierSelfEffects() }

    /// The self effects of `cards`.
    init(cards: [AttackModifier] = []) {
        for effect in cards.flatMap(\.effects) {
            let isSelf = effect.effects?.contains { $0.type == .specialTarget && $0.value?.stringValue == "self" } ?? false
            switch effect.type {
            case .condition:
                if let condition = effect.value.flatMap({ ConditionName(rawValue: $0.stringValue) }), condition.isPositive {
                    conditions.append(condition)
                }
            case .heal where isSelf:
                heal += effect.value?.intValue ?? 0
            case .shield where isSelf:
                shield += effect.value?.intValue ?? 0
            case .element:
                if let element = effect.value.flatMap({ ElementType(rawValue: $0.stringValue) }) { infusions.append(element) }
            case .refreshItem:
                itemsToRefresh += 1
            default:
                break
            }
        }
    }
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
    ///   - retaliateValue: Defender's retaliate damage
    ///   - retaliateRange: Defender's retaliate range
    ///   - attackerDefenderDistance: Distance between attacker and defender
    ///   - preDrawnCards: Cards already drawn by the interactive UI (skips drawModifier when non-empty).
    ///     For rolling chains: rolling cards come first, terminal card last. All values/effects applied in order.
    ///   - drawModifier: Closure to draw from the appropriate modifier deck (unused when preDrawnCards non-empty)
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
        preDrawnCards: [AttackModifier] = [],
        drawModifier: () -> AttackModifier?,
        defenderHealth: Int
    ) -> AttackResult {
        // 1. Start with base attack value
        var attackValue = baseAttack

        // 2. Add poison bonus (+1 to incoming attack if defender is poisoned)
        if isPoisoned {
            attackValue += 1
        }

        // 3. Determine the modifier cards that apply (interactive UI pre-draws them).
        let cards = preDrawnCards.isEmpty
            ? drawModifiers(advantage: advantage, disadvantage: disadvantage, baseAttack: attackValue, draw: drawModifier)
            : preDrawnCards

        // 4. Apply the cards: additive values first, then ×2 / null (the attacker chooses the
        //    order within a step, and doubling after the additions is never worse).
        var isMiss = false
        var isCritical = false
        var modifierConditions: [ConditionName] = []
        var modifierPierce = 0
        var modifierPush = 0
        var modifierPull = 0
        for card in cards where card.valueType != .multiply {
            attackValue += card.value
        }
        for card in cards where card.valueType == .multiply {
            if card.value == 0 {
                attackValue = 0
                isMiss = true
            } else {
                attackValue *= card.value
                isCritical = card.value >= 2
            }
        }
        for card in cards {
            for effect in card.effects {
                // Positive conditions go to the attacker (ModifierSelfEffects), the rest to the target.
                if let condition = conditionFromEffect(effect), !condition.isPositive { modifierConditions.append(condition) }
                if effect.type == .pierce, let value = effect.value?.intValue { modifierPierce += value }
                if effect.type == .push, let value = effect.value?.intValue { modifierPush += value }
                if effect.type == .pull, let value = effect.value?.intValue { modifierPull += value }
            }
        }
        let modifier = cards.last

        // 5. Apply shield (reduced by pierce). Shield only matters when there is damage to reduce.
        let effectiveShield = max(0, shield - pierce - modifierPierce)
        if !isMiss {
            attackValue = max(0, attackValue - effectiveShield)
        }

        // 6. Floor at 0
        let finalDamage = max(0, attackValue)

        // 7. Check if defender is killed
        let killed = finalDamage > 0 && defenderHealth - finalDamage <= 0

        // 8. Conditions: attack effects apply whether or not the attack does damage — including
        //    on a null/curse draw (GH p.19/p.23) — but not once the target has died (p.19).
        let appliedConditions: [ConditionName] = killed ? [] : conditions + modifierConditions

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
            retaliateDamage: retaliateDamage,
            allConditions: conditions + modifierConditions,
            modifierPush: modifierPush,
            modifierPull: modifierPull,
            attackerEffects: ModifierSelfEffects(cards: cards)
        )
    }

    // MARK: - Damage Breakdown Log

    /// Returns a compact, human-readable breakdown of an attack for the turn log.
    /// Example: "3 +1(poison) +1(rolling) ×2(mod) -1(shield) = 10"
    /// Pass `preDrawnCards` from the interactive draw UI; pass `shield` before pierce reduction.
    static func damageBreakdown(
        base: Int,
        isPoisoned: Bool,
        preDrawnCards: [AttackModifier],
        shield: Int,
        pierce: Int = 0,
        isMiss: Bool,
        finalDamage: Int
    ) -> String {
        if isMiss { return "MISS" }

        var parts: [String] = ["\(base)"]
        if isPoisoned { parts.append("+1(poison)") }

        for card in preDrawnCards {
            if card.valueType == .multiply {
                if card.value == 0 { return "MISS" }
                parts.append("×\(card.value)(mod)")
            } else {
                let sign = card.value >= 0 ? "+" : ""
                let tag = card.rolling ? "(rolling)" : "(mod)"
                parts.append("\(sign)\(card.value)\(tag)")
            }
        }

        let cardPierce = preDrawnCards.flatMap(\.effects)
            .filter { $0.type == .pierce }
            .compactMap { $0.value?.intValue }
            .reduce(0, +)
        let totalPierce = pierce + cardPierce
        let effectiveShield = max(0, shield - totalPierce)
        if effectiveShield > 0 {
            if totalPierce > 0 {
                parts.append("-\(effectiveShield)(shield-\(totalPierce)pierce)")
            } else {
                parts.append("-\(effectiveShield)(shield)")
            }
        }

        return parts.joined(separator: " ") + " = \(finalDamage)"
    }

    /// The same sum in the battle log's words: "2 + 1 − 1 shield = 2 damage", "miss".
    static func readableBreakdown(
        base: Int,
        isPoisoned: Bool,
        preDrawnCards: [AttackModifier],
        shield: Int,
        pierce: Int = 0,
        isMiss: Bool,
        finalDamage: Int
    ) -> String {
        if isMiss || preDrawnCards.contains(where: { $0.valueType == .multiply && $0.value == 0 }) {
            return "miss"
        }
        var text = "\(base)"
        if isPoisoned { text += " + 1 poison" }
        for card in preDrawnCards {
            if card.valueType == .multiply {
                text += " ×\(card.value)"
            } else {
                text += card.value >= 0 ? " + \(card.value)" : " − \(-card.value)"
            }
        }
        let totalPierce = pierce + preDrawnCards.flatMap(\.effects)
            .filter { $0.type == .pierce }
            .compactMap { $0.value?.intValue }
            .reduce(0, +)
        let effectiveShield = max(0, shield - totalPierce)
        if effectiveShield > 0 {
            text += " − \(effectiveShield) shield"
        }
        return text + " = " + (finalDamage == 0 ? "no damage" : "\(finalDamage) damage")
    }

    // MARK: - Advantage / Disadvantage

    /// Draw the modifier cards for one attack and return the cards that apply.
    /// `baseAttack` (with poison) lets advantage and disadvantage compare the attacks the two
    /// cards make rather than the cards alone (on Attack 1, +2 beats ×2).
    static func drawModifiers(advantage: Bool, disadvantage: Bool, baseAttack: Int? = nil,
                              draw: () -> AttackModifier?) -> [AttackModifier] {
        drawModifiersDetailed(advantage: advantage, disadvantage: disadvantage, baseAttack: baseAttack, draw: draw).selected
    }

    /// Draw the modifier cards for one attack, keeping every card drawn (in draw order) as well as
    /// the ones that apply, so the board can show both draws of an advantage attack.
    static func drawModifiersDetailed(advantage: Bool, disadvantage: Bool, baseAttack: Int? = nil,
                                      draw: () -> AttackModifier?) -> (drawn: [AttackModifier], selected: [AttackModifier]) {
        if advantage == disadvantage {
            let chain = drawChain(draw)
            return (chain, chain)
        }
        let first = draw().map { [$0] } ?? []
        let second = drawSecond(after: first, draw)
        let selected = selectModifierCards(first: first, second: second,
                                           advantage: advantage, disadvantage: disadvantage, baseAttack: baseAttack)
        return (first + second, selected)
    }

    /// Normal draw: keep drawing while the drawn card is rolling (GH p.19).
    static func drawChain(_ draw: () -> AttackModifier?) -> [AttackModifier] {
        var chain: [AttackModifier] = []
        repeat {
            guard let card = draw() else { break }
            chain.append(card)
        } while chain.last?.rolling == true
        return chain
    }

    /// Second draw of an advantage/disadvantage attack: one card, continuing past rolling cards
    /// only when the first card was rolling as well (GH p.20).
    static func drawSecond(after first: [AttackModifier], _ draw: () -> AttackModifier?) -> [AttackModifier] {
        guard let card = draw() else { return [] }
        var second = [card]
        if first.first?.rolling == true && card.rolling {
            while second.last?.rolling == true, let next = draw() {
                second.append(next)
            }
        }
        return second
    }

    /// Choose which drawn cards apply (GH p.20).
    /// - Advantage: two non-rolling cards → the better one. If a rolling card was drawn, its
    ///   effect is added to the other card instead (both rolling → all cards to the first
    ///   non-rolling one are added together).
    /// - Disadvantage: two non-rolling cards → the worse one. Rolling cards are disregarded
    ///   (both rolling → only the first non-rolling card drawn after them applies).
    /// - Both or neither: a normal draw — the first chain applies.
    static func selectModifierCards(first: [AttackModifier], second: [AttackModifier],
                                    advantage: Bool, disadvantage: Bool, baseAttack: Int? = nil) -> [AttackModifier] {
        guard advantage != disadvantage else { return first }
        let all = first + second
        guard let a = first.last else { return second.last.map { [$0] } ?? [] }
        guard let b = second.last else { return [a] }
        let anyRolling = all.contains { $0.rolling }

        if advantage {
            if !anyRolling { return [betterCard(a, b, base: baseAttack)] }
            return all.filter(\.rolling) + all.filter { !$0.rolling }
        } else {
            if !anyRolling { return [worseCard(a, b, base: baseAttack)] }
            return all.last(where: { !$0.rolling }).map { [$0] } ?? []
        }
    }

    /// Pick the better of two modifier cards (ties → the card drawn first).
    private static func betterCard(_ a: AttackModifier, _ b: AttackModifier, base: Int?) -> AttackModifier {
        score(a, base: base) >= score(b, base: base) ? a : b
    }

    /// Pick the worse of two modifier cards (ties → the card drawn first).
    private static func worseCard(_ a: AttackModifier, _ b: AttackModifier, base: Int?) -> AttackModifier {
        score(a, base: base) <= score(b, base: base) ? a : b
    }

    /// How good a card is for this attack: the attack value it makes from `base` (a null is
    /// always the worst), or the card alone when the attack isn't known.
    static func score(_ card: AttackModifier, base: Int?) -> Int {
        guard let base else { return cardScore(card) }
        if card.valueType == .multiply {
            return card.value == 0 ? Int.min / 2 : max(0, base * card.value)
        }
        return max(0, base + card.value)
    }

    /// Numeric score for comparing modifier cards (higher = better for attacker).
    static func cardScore(_ card: AttackModifier) -> Int {
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

    /// Retaliate damage dealt to an attacker at `distance`: each retaliate bonus applies only if
    /// its own range (default 1 = adjacent) reaches the attacker; applicable bonuses stack (GH p.24).
    static func retaliateDamage(retaliate: [ActionModel], retaliatePersistent: [ActionModel], distance: Int) -> Int {
        (retaliate + retaliatePersistent).reduce(0) { total, action in
            let range = action.subActions?.first { $0.type == .range }?.value?.intValue ?? 1
            return distance <= max(1, range) ? total + (action.value?.intValue ?? 0) : total
        }
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
        hasCondition(.muddle, on: attacker) || hasCondition(.impair, on: attacker) || isRangedAdjacent
    }
}
