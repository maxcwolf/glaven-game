import Foundation

/// Everything needed to resolve one attack against one target.
struct AttackParameters {
    var value: Int
    /// Whether the attack is ranged (ranged attacks against adjacent targets have disadvantage).
    var isRanged: Bool = false
    var pierce: Int = 0
    var conditions: [ConditionName] = []
    var push: Int = 0
    var pull: Int = 0
    /// Extra advantage source (e.g. a monster stat trait) on top of Strengthen.
    var advantage: Bool = false
}

extension BoardCoordinator {

    /// The attack modifier deck a figure draws from: characters their own, summons their
    /// owner's, allied figures the ally deck, monsters the monster deck (GH p.19, p.30).
    func modifierDrawer(for attacker: PieceID) -> () -> AttackModifier? {
        guard let gameManager else { return { nil } }
        let am = gameManager.attackModifierManager
        switch attacker {
        case .character(let id):
            guard let character = gameManager.game.characters.first(where: { $0.id == id }) else { return { nil } }
            return { am.drawCharacterCard(for: character) }
        case .summon:
            guard let owner = summonOwner(of: attacker) else { return { nil } }
            return { am.drawCharacterCard(for: owner) }
        case .monster:
            return isPlayerSide(attacker) ? { am.drawAllyCard() } : { am.drawMonsterCard() }
        case .objective:
            return { am.drawAllyCard() }
        }
    }

    /// Resolve one attack against one target (GH p.18–20): poison, modifier draw with
    /// advantage/disadvantage, shield/pierce, damage (characters may negate it by losing cards),
    /// conditions and push/pull on a surviving target, then retaliate.
    /// Returns true if the target died.
    @discardableResult
    @MainActor func performAttack(attacker: PieceID, target: PieceID, attack: AttackParameters,
                       drawCard: (() -> AttackModifier?)? = nil) async -> Bool {
        guard let attackerPos = boardState.piecePositions[attacker],
              let targetPos = boardState.piecePositions[target],
              let defender = entity(for: target) else { return false }
        attackObserver?(attacker, target)

        let distance = attackerPos.distance(to: targetPos)
        let isPoisoned = defender.entityConditions.contains { $0.name == .poison && !$0.expired }
        let shield = CombatResolver.totalShield(shield: defender.shield, shieldPersistent: defender.shieldPersistent)
        let retaliate = CombatResolver.retaliateDamage(retaliate: defender.retaliate,
                                                       retaliatePersistent: defender.retaliatePersistent,
                                                       distance: distance)

        var advantage = attack.advantage
        var disadvantage = attack.isRanged && attackerPos.isAdjacent(to: targetPos)
        // Some monsters' stat cards give every attack against them disadvantage (e.g. Night Demon).
        if case .monster(let name, _) = target, let monsterEntity = defender as? GameMonsterEntity,
           let stat = gameManager?.game.monsters.first(where: { $0.name == name })?.stat(for: monsterEntity.type),
           stat.attackersGainDisadvantage {
            disadvantage = true
        }
        if let attackerEntity = entity(for: attacker) {
            advantage = advantage || CombatResolver.hasAdvantage(attacker: attackerEntity)
            disadvantage = CombatResolver.hasDisadvantage(attacker: attackerEntity, isRangedAdjacent: disadvantage)
        }

        let preDrawn = await performModifierDraw(
            attacker: attacker, defender: target, baseAttack: attack.value,
            advantage: advantage, disadvantage: disadvantage,
            drawCard: drawCard ?? modifierDrawer(for: attacker)
        )

        let result = CombatResolver.resolveAttack(
            attacker: attacker, defender: target, baseAttack: attack.value,
            advantage: advantage, disadvantage: disadvantage,
            isPoisoned: isPoisoned, shield: shield, pierce: attack.pierce,
            conditions: attack.conditions,
            attackerDefenderDistance: distance,
            preDrawnCards: preDrawn, drawModifier: { nil },
            defenderHealth: defender.health
        )
        let breakdown = CombatResolver.damageBreakdown(
            base: attack.value, isPoisoned: isPoisoned, preDrawnCards: preDrawn,
            shield: shield, pierce: attack.pierce, isMiss: result.isMiss, finalDamage: result.damage)
        let sum = CombatResolver.readableBreakdown(
            base: attack.value, isPoisoned: isPoisoned, preDrawnCards: preDrawn,
            shield: shield, pierce: attack.pierce, isMiss: result.isMiss, finalDamage: result.damage)
        log("\(name(attacker)) attacks \(name(target)): \(sum)", category: .attack, trace: breakdown)
        if lastModifierReveal?.attacker == attacker, lastModifierReveal?.defender == target, lastModifierReveal?.sum == nil {
            lastModifierReveal?.sum = sum
        }

        var died = false
        if result.damage > 0 {
            died = await sufferDamageWithMitigation(result.damage, to: target,
                                                    source: pieceLabel(attacker), killer: attacker)
        }

        // Added effects apply even when no damage was dealt, but not to a dead target (p.19).
        if !died && isOnBoard(target) {
            for condition in result.allConditions {
                applyCondition(condition, to: target)
                if let credited = creditedCharacter(for: attacker) {
                    gameManager?.scenarioStatsManager.recordConditionApplied(by: credited.name)
                }
            }
            let push = attack.push + result.modifierPush
            let pull = attack.pull + result.modifierPull
            if push > 0, let origin = boardState.piecePositions[attacker] {
                await performPushPull(target: target, attackerPos: origin, steps: push, isPush: true)
            }
            if pull > 0, let origin = boardState.piecePositions[attacker] {
                await performPushPull(target: target, attackerPos: origin, steps: pull, isPush: false)
            }
        }

        // Retaliate: after the attack, only if the retaliating figure survived (p.24).
        if !died && retaliate > 0 && isOnBoard(target) && isOnBoard(attacker) {
            log("\(name(target)) retaliates for \(retaliate)", category: .damage)
            await sufferDamageWithMitigation(retaliate, to: attacker,
                                             source: "\(name(target))\u{2019}s retaliate", killer: target)
        }
        return died
    }
}
