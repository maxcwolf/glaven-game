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
        var shield = CombatResolver.totalShield(shield: defender.shield, shieldPersistent: defender.shieldPersistent)
        var retaliate = CombatResolver.retaliateDamage(retaliate: defender.retaliate,
                                                       retaliatePersistent: defender.retaliatePersistent,
                                                       distance: distance)

        // Helm of the Mountain: attacking its wearer while Earth is strong immobilizes the attacker.
        if case .character(let id) = target, areEnemies(attacker, target),
           gameManager?.game.characters.first(where: { $0.id == id })?.items.contains(PassiveItems.helmOfTheMountain) == true,
           gameManager?.game.elementBoard.first(where: { $0.type == .earth })?.state == .strong {
            log("\(name(target))\u{2019}s Helm of the Mountain immobilizes \(name(attacker))", category: .condition)
            applyCondition(.immobilize, to: attacker)
        }

        // Chain Hood: Shield 1 while the wearer is beside three or more monsters.
        if case .character(let id) = target,
           gameManager?.game.characters.first(where: { $0.id == id })?.items.contains(PassiveItems.chainHood) == true,
           targetPos.neighbors.compactMap({ boardState.piece(at: $0) })
               .filter({ if case .monster = $0 { return true }; return false }).count >= 3 {
            shield += 1
        }

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

        // Show who attacks whom before the cards are drawn.
        if let scene = boardScene {
            scene.showAttack(from: attacker, to: target, ranged: attack.isRanged || distance > 1)
            if turnDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: turnDelayNanoseconds / 2) }
        }
        // Leather Armor, Studded Leather: the attacker gains disadvantage.
        for item in DefenseItem.beforeDraw where !disadvantage && areEnemies(attacker, target) {
            if await offerDefenseItem(item, to: target, from: attacker) {
                disadvantage = true
                shield += item.shield
            }
        }

        var preDrawn = await performModifierDraw(
            attacker: attacker, defender: target, baseAttack: attack.value,
            advantage: advantage, disadvantage: disadvantage,
            drawCard: drawCard ?? modifierDrawer(for: attacker)
        )

        // Iron Helmet: an enemy's ×2 against the wearer counts as +0 (always on, by the data).
        if case .character(let id) = target, areEnemies(attacker, target),
           let wearer = gameManager?.game.characters.first(where: { $0.id == id }),
           wearer.items.contains(DefenseItem.ironHelmet), preDrawn.contains(where: { $0.type == .double_ }) {
            preDrawn = preDrawn.map { $0.type == .double_ ? AttackModifier.standard(.plus0) : $0 }
            log("\(name(target))\u{2019}s Iron Helmet turns the \u{00D7}2 into +0", category: .attack)
        }
        func resolve() -> AttackResult {
            CombatResolver.resolveAttack(
                attacker: attacker, defender: target, baseAttack: attack.value,
                advantage: advantage, disadvantage: disadvantage,
                isPoisoned: isPoisoned, shield: shield, pierce: attack.pierce,
                conditions: attack.conditions,
                attackerDefenderDistance: distance,
                preDrawnCards: preDrawn, drawModifier: { nil },
                defenderHealth: defender.health
            )
        }
        var result = resolve()
        // Shields and armour: a shield for an attack that would damage (pierce still applies).
        var negated = false
        // Charged bonuses on the target: Warding Strength (Shield 1), Cold Front (no damage, and
        // Retaliate 3, Range 3), Opposing Strike (Retaliate against melee attacks).
        if areEnemies(attacker, target) {
            if !attack.isRanged && distance <= 1, case .retaliateAgainstMelee(let amount)? = useFirstCharge(of: target, where: {
                if case .retaliateAgainstMelee = $0 { return true }; return false }) {
                retaliate += amount
            }
            if result.damage > 0, case .shieldAgainstAttacks(let amount)? = useFirstCharge(of: target, where: {
                if case .shieldAgainstAttacks = $0 { return true }; return false }) {
                shield += amount
                result = resolve()
            }
            if result.damage > 0, case .negateAttackAndRetaliate(let amount, let range)? = useFirstCharge(of: target, where: {
                if case .negateAttackAndRetaliate = $0 { return true }; return false }) {
                negated = true
                if distance <= range { retaliate += amount }
            }
        }
        for item in DefenseItem.onDamage where result.damage > 0 && !negated && areEnemies(attacker, target) {
            if await offerDefenseItem(item, to: target, from: attacker) {
                shield += item.shield
                if distance <= 1 { retaliate += item.retaliate }
                negated = item.negates
                result = resolve()
            }
        }
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

        if result.damage == 0 {
            boardScene?.pieceUnharmed(id: target, missed: result.isMiss)
        }

        var died = false
        if negated {
            log("\(name(target)) suffers no damage", category: .damage)
            boardScene?.pieceUnharmed(id: target, missed: false)
        } else if result.damage > 0 {
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
            // Eye for an Eye: 1 experience for each retaliation this round.
            if chargedBonuses(of: target).contains(where: { $0.bonus == .experiencePerRetaliate }),
               case .character(let id) = target, let character = gameManager?.game.characters.first(where: { $0.id == id }) {
                character.experience += 1
                log("\(name(target)) gains 1 XP", category: .info)
            }
            await sufferDamageWithMitigation(retaliate, to: attacker,
                                             source: "\(name(target))\u{2019}s retaliate", killer: target)
        }
        return died
    }
}
