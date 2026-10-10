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
    /// How far the attack reaches (Heart of the Betrayer turns it on an ally within it).
    var range: Int = 1
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
    @MainActor func performAttack(attacker: PieceID, target aimedAt: PieceID, attack printedAttack: AttackParameters,
                       drawCard: (() -> AttackModifier?)? = nil, from origin: HexCoord? = nil) async -> Bool {
        var attack = printedAttack
        // Every await below may come back to a board that was left or restarted meanwhile.
        let generation = boardGeneration
        let target = await attackTarget(of: attacker, aimingAt: aimedAt, range: attack.range)
        guard isCurrentBoard(generation), let attackerPos = origin ?? boardState.piecePositions[attacker],
              let targetPos = boardState.piecePositions[target],
              let defender = entity(for: target) else { return false }
        // Drawn onto another figure (Provoking Roar), the attack lands whatever the range.
        attackWasRedirected = target != aimedAt
        attackObserver?(attacker, target)

        let distance = attackerPos.distance(to: targetPos)
        // The Doomstalker's dooms on the target: +Attack, Pierce, advantage, Curse.
        applyDoomBonuses(to: &attack, attacker: attacker, target: target, distance: distance)
        let isPoisoned = defender.entityConditions.contains { $0.name == .poison && !$0.expired }
        var shield = CombatResolver.totalShield(shield: defender.shield, shieldPersistent: defender.shieldPersistent)
        var retaliate = CombatResolver.retaliateDamage(retaliate: defender.retaliate,
                                                       retaliatePersistent: defender.retaliatePersistent,
                                                       distance: distance)

        // Helm of the Mountain: attacking its wearer while Earth is strong immobilizes the attacker.
        if case .character(let id) = target, areEnemies(attacker, target),
           gameManager?.game.characters.first(where: { $0.id == id })?.carriedItems.contains(PassiveItems.helmOfTheMountain) == true,
           gameManager?.game.elementBoard.first(where: { $0.type == .earth })?.state == .strong {
            log("\(name(target))\u{2019}s Helm of the Mountain immobilizes \(name(attacker))", category: .condition)
            applyCondition(.immobilize, to: attacker)
        }

        // Chain Hood: Shield 1 while the wearer is beside three or more monsters.
        if case .character(let id) = target,
           gameManager?.game.characters.first(where: { $0.id == id })?.carriedItems.contains(PassiveItems.chainHood) == true,
           targetPos.neighbors.compactMap({ boardState.piece(at: $0) })
               .filter({ if case .monster = $0 { return true }; return false }).count >= 3 {
            shield += 1
        }

        var advantage = attack.advantage
        // Giant Viper: "All attacks targeting it this round gain disadvantage."
        var disadvantage = (attack.isRanged && attackerPos.isAdjacent(to: targetPos)) || disadvantagedThisRound.contains(target)
        // Some monsters' stat cards give every attack against them disadvantage (e.g. Night Demon).
        if case .monster(let name, _) = target, let monsterEntity = defender as? GameMonsterEntity,
           let stat = gameManager?.game.monsters.first(where: { $0.name == name })?.stat(for: monsterEntity.type),
           stat.attackersGainDisadvantage {
            disadvantage = true
        }
        // Dancing Shadows, Terror Blade: attacks targeting the character have disadvantage this round.
        if chargedBonuses(of: target).contains(where: { $0.bonus == .attackersGainDisadvantage }) {
            disadvantage = true
        }
        if let attackerEntity = entity(for: attacker) {
            advantage = advantage || CombatResolver.hasAdvantage(attacker: attackerEntity)
            disadvantage = CombatResolver.hasDisadvantage(attacker: attackerEntity, isRangedAdjacent: disadvantage)
        }

        // Show who attacks whom before the cards are drawn.
        if let scene = boardScene {
            scene.showAttack(from: attacker, to: target, ranged: attack.isRanged || distance > 1)
            await beat(0.5)
            guard isCurrentBoard(generation) else { return false }
        }
        // Leather Armor, Studded Leather: the attacker gains disadvantage.
        for item in DefenseItem.beforeDraw where !disadvantage && areEnemies(attacker, target) {
            if await offerDefenseItem(item, to: target, from: attacker) {
                disadvantage = true
                shield += item.shield
            }
            guard isCurrentBoard(generation) else { return false }
        }

        var preDrawn = await performModifierDraw(
            attacker: attacker, defender: target, baseAttack: attack.value,
            comparedAttack: attack.value + (isPoisoned ? 1 : 0),
            advantage: advantage, disadvantage: disadvantage,
            drawCard: drawCard ?? modifierDrawer(for: attacker)
        )
        guard isCurrentBoard(generation) else { return false }

        // Iron Helmet: an enemy's ×2 against the wearer counts as +0 (always on, by the data).
        if case .character(let id) = target, areEnemies(attacker, target),
           let wearer = gameManager?.game.characters.first(where: { $0.id == id }),
           wearer.carriedItems.contains(DefenseItem.ironHelmet), preDrawn.contains(where: { $0.type == .double_ }) {
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
            guard isCurrentBoard(generation) else { return false }
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
            lastModifierReveal?.chips = CombatResolver.sumChips(
                base: attack.value, isPoisoned: isPoisoned, cards: preDrawn, shield: shield, pierce: attack.pierce,
                isMiss: result.isMiss, finalDamage: result.damage, conditions: result.allConditions)
            if let reveal = lastModifierReveal {
                let drew = GameText.list(reveal.selected.map(Self.modifierName))
                teach(.modifiers, "Here \(name(attacker)) drew \(drew): \(sum).", at: .modifierTray)
                if reveal.advantage != reveal.disadvantage {
                    teach(.advantage, "\(name(attacker)) attacked with \(reveal.advantage ? "advantage" : "disadvantage").",
                          at: .modifierTray)
                }
            }
        }
        if shield > 0 || retaliate > 0 { teach(.shieldAndRetaliate, at: .piece(target)) }

        if result.damage == 0 {
            boardScene?.pieceUnharmed(id: target, missed: result.isMiss)
        }

        applyModifierSelfEffects(result.attackerEffects, to: attacker)
        // "+1 Target": the character's attack ability may take in one more enemy (offered when it ends).
        if result.attackerEffects.extraTargets > 0, case .character(let id) = attacker, activePlayerTurn?.characterID == id {
            extraTargetsEarned += result.attackerEffects.extraTargets
            log("\(name(attacker)) may add a target to this attack", category: .attack)
        }

        var died = false
        if negated {
            log("\(name(target)) suffers no damage", category: .damage)
            boardScene?.pieceUnharmed(id: target, missed: false)
        } else if result.damage > 0 {
            // Shield took some of it (a fully absorbed attack is "Blocked", above).
            if shield > attack.pierce { boardScene?.play(.shield) }
            died = await sufferDamageWithMitigation(result.damage, to: target,
                                                    source: pieceLabel(attacker), killer: attacker)
            guard isCurrentBoard(generation) else { return died }
        }

        // Added effects apply even when no damage was dealt, but not to a dead target (p.19).
        if !died && isOnBoard(target) {
            for condition in result.allConditions {
                applyCondition(condition, to: target)
                // Unending Chant: a Curse the character gives is given twice.
                if condition == .curse, useFirstCharge(of: attacker, where: { $0 == .doubleCurses }) != nil {
                    applyCondition(.curse, to: target)
                }
                if let credited = creditedCharacter(for: attacker) {
                    gameManager?.scenarioStatsManager.recordConditionApplied(by: credited.name)
                }
            }
            let push = attack.push + result.modifierPush
            let pull = attack.pull + result.modifierPull
            if push > 0, let origin = boardState.piecePositions[attacker] {
                await performPushPull(target: target, attackerPos: origin, steps: push, isPush: true)
                guard isCurrentBoard(generation) else { return died }
            }
            if pull > 0, let origin = boardState.piecePositions[attacker] {
                await performPushPull(target: target, attackerPos: origin, steps: pull, isPush: false)
                guard isCurrentBoard(generation) else { return died }
            }
        }

        // Blood Hunger: after its attack, the summon heals itself.
        if case .summon = attacker, isOnBoard(attacker), let owner = summonOwner(of: attacker),
           case .summonHealsAfterAttack(let amount)? = useFirstCharge(of: .character(owner.id), where: {
               if case .summonHealsAfterAttack = $0 { return true }; return false }) {
            let healed = heal(attacker, amount: amount, source: attacker)
            log("\(name(attacker)) heals for \(healed)", category: .heal)
        }

        // Retaliate: after the attack, only if the retaliating figure survived (p.24).
        if !died && retaliate > 0 && isOnBoard(target) && isOnBoard(attacker) {
            log("\(name(target)) retaliates for \(retaliate)", category: .damage)
            boardScene?.play(.retaliate)
            // Eye for an Eye: 1 experience for each retaliation this round.
            if chargedBonuses(of: target).contains(where: { $0.bonus == .experiencePerRetaliate }),
               case .character(let id) = target, let character = gameManager?.game.characters.first(where: { $0.id == id }) {
                character.experience += 1
                log("\(name(target)) gains 1 XP", category: .info)
            }
            await sufferDamageWithMitigation(retaliate, to: attacker,
                                             source: "\(name(target))\u{2019}s retaliate", killer: target)
            guard isCurrentBoard(generation) else { return died }
        }
        await resolveDeathAttacks()
        await resolveDoomDeaths()
        return died
    }

    /// What the drawn modifier cards give the attacker, whatever happens to the target (p.19).
    func applyModifierSelfEffects(_ effects: ModifierSelfEffects, to attacker: PieceID) {
        guard !effects.isEmpty, isOnBoard(attacker), let gameManager else { return }
        for condition in effects.conditions {
            applyCondition(condition, to: attacker)
        }
        if effects.heal > 0 {
            let healed = heal(attacker, amount: effects.heal, source: attacker)
            log("\(name(attacker)) heals for \(healed)", category: .heal)
        }
        if effects.shield > 0, let entity = entity(for: attacker) {
            // Shield X, self: until the end of the round.
            let total = (entity.shield?.value?.intValue ?? 0) + effects.shield
            entity.shield = ActionModel(type: .shield, value: .int(total))
            log("\(name(attacker)) gains Shield \(effects.shield) this round", category: .info)
        }
        for element in effects.infusions {
            gameManager.game.infuseElement(element)
            log("\(name(attacker)) infuses \(GameText.elementName(element))", category: .element)
        }
        // "Refresh an item": the attacker's spent or lost item, picked when there's a choice.
        if effects.itemsToRefresh > 0, case .character(let id) = attacker,
           let character = gameManager.game.characters.first(where: { $0.id == id }) {
            let options = refreshableItems(of: character, excluding: "", consumedSmallOnly: false)
            if options.count <= effects.itemsToRefresh || autoResolvePrompts {
                refreshItems(options.prefix(effects.itemsToRefresh).map(\.itemKey), for: character)
            } else {
                pendingItemRefresh = PendingItemRefresh(characterID: character.id, count: effects.itemsToRefresh,
                                                        options: options.map(\.itemKey), itemName: "Attack modifier")
            }
        }
    }

    /// Make the "on death" attacks of monsters that fell (Cultists: Attack +2 on the figures
    /// around where it fell), each from its last hex.
    @MainActor func resolveDeathAttacks() async {
        let generation = boardGeneration
        while !pendingDeathAttacks.isEmpty, isCurrentBoard(generation) {
            let death = pendingDeathAttacks.removeFirst()
            guard let gameManager, let monster = gameManager.game.monsters.first(where: { $0.name == death.monster }) else { continue }
            let game = gameManager.game
            let characterCount = max(2, game.characters.filter { !$0.absent }.count)
            let stat = monster.attackStat(for: death.type)
            let base = stat?.attackValue(characterCount: characterCount, level: monster.level,
                                         variables: MonsterAI.attackVariables(for: monster, gameState: game)) ?? 0
            let spec = MonsterAbility.attack(death.action, stat: stat, baseAttack: base, baseRange: 0)
            // Every enemy next to where it fell that the area can reach (the pattern turned to hit most).
            let pattern = death.action.subActions?.first { $0.type == .area }?.value?.stringValue
            let enemies = boardState.piecePositions.keys.filter { areEnemies(death.attacker, $0) }.sorted()
            var victims: [PieceID] = []
            if let pattern {
                for focus in enemies where boardState.piecePositions[focus].map({ $0.isAdjacent(to: death.position) }) == true {
                    let hit = AoEResolver.resolveTargets(pattern: pattern, attackerPos: death.position, focusTarget: focus,
                                                         enemies: enemies, board: boardState)
                    if hit.count > victims.count { victims = hit }
                }
            } else {
                victims = enemies.filter { boardState.piecePositions[$0].map { $0.isAdjacent(to: death.position) } == true }
            }
            guard !victims.isEmpty else { continue }
            log("\(name(death.attacker)) attacks as it dies", category: .attack)
            deathAttackInProgress = death
            for victim in victims where isOnBoard(victim) && isCurrentBoard(generation) {
                await performAttack(attacker: death.attacker, target: victim,
                                    attack: AttackParameters(value: spec.value, conditions: spec.conditions),
                                    from: death.position)
            }
            deathAttackInProgress = nil
        }
    }
}

// MARK: - Attack preview

extension BoardCoordinator {
    /// What the character's attack will do to `target` before its card is drawn: "2 − 1 shield
    /// = 1 + draw · Stun", with "+1 poison", "advantage" or "disadvantage" where they apply.
    /// Charged bonuses that would be used up (Single Out, Stone Pummel…) aren't counted, so a
    /// preview never spends a charge.
    func attackPreview(attacker: PieceID, target: PieceID) -> String? {
        guard let turn = activePlayerTurn, case .character(let id) = attacker, turn.characterID == id,
              let defender = entity(for: target),
              let from = boardState.piecePositions[attacker], let to = boardState.piecePositions[target] else { return nil }
        var value = turn.currentAttackValue() + attackTextBonus(turn.attackTexts, attacker: attacker, target: target).attack
        if case .monster(let monsterName, _) = target { value += turn.attackBonusAgainst[monsterName] ?? 0 }
        let poisoned = isConditionActive(.poison, on: target)
        let shield = max(0, CombatResolver.totalShield(shield: defender.shield, shieldPersistent: defender.shieldPersistent)
                         - turn.pendingPierce)
        let ranged = turn.currentAttackRange() > 1
        var disadvantage = (ranged && from.isAdjacent(to: to)) || disadvantagedThisRound.contains(target)
        if case .monster(let name, _) = target, let monsterEntity = defender as? GameMonsterEntity,
           gameManager?.game.monsters.first(where: { $0.name == name })?.stat(for: monsterEntity.type)?.attackersGainDisadvantage == true {
            disadvantage = true
        }
        var advantage = turn.pendingAdvantage
        if let attackerEntity = entity(for: attacker) {
            advantage = advantage || CombatResolver.hasAdvantage(attacker: attackerEntity)
            disadvantage = CombatResolver.hasDisadvantage(attacker: attackerEntity, isRangedAdjacent: disadvantage)
        }

        var text = "\(value)"
        if poisoned { text += " + 1 poison" }
        if shield > 0 { text += " \u{2212} \(shield) shield" }
        let expected = max(0, value + (poisoned ? 1 : 0) - shield)
        if poisoned || shield > 0 { text += " = \(expected)" }
        text += " + draw"
        if advantage != disadvantage { text += advantage ? " · advantage" : " · disadvantage" }
        for condition in turn.pendingConditions { text += " · \(GameText.conditionName(condition))" }
        return text
    }

    /// Put the preview under every enemy the character may attack (not area attacks: there the
    /// placement decides who is hit).
    func showAttackPreviews(attacker: PieceID, targets: Set<PieceID>) {
        guard activePlayerTurn?.pendingAreaPattern == nil else { return }
        var previews: [PieceID: String] = [:]
        for target in targets {
            if let damage = expectedDamage(attacker: attacker, target: target) { previews[target] = "\(damage) dmg" }
        }
        boardScene?.showTargetPreviews(previews)
    }

    /// The damage before the draw (attack, poison, shield and pierce), for the small chip on the board.
    func expectedDamage(attacker: PieceID, target: PieceID) -> Int? {
        guard let turn = activePlayerTurn, case .character(let id) = attacker, turn.characterID == id,
              let defender = entity(for: target) else { return nil }
        var value = turn.currentAttackValue() + attackTextBonus(turn.attackTexts, attacker: attacker, target: target).attack
        if case .monster(let monsterName, _) = target { value += turn.attackBonusAgainst[monsterName] ?? 0 }
        if isConditionActive(.poison, on: target) { value += 1 }
        let shield = max(0, CombatResolver.totalShield(shield: defender.shield, shieldPersistent: defender.shieldPersistent)
                         - turn.pendingPierce)
        return max(0, value - shield)
    }

    /// The previews for the instruction, nearest target first: "Bandit Guard 1: 2 − 1 shield = 1 + draw".
    func attackPreviewLines(attacker: PieceID, targets: Set<PieceID>) -> [String] {
        let origin = boardState.piecePositions[attacker]
        return targets.sorted { a, b in
            let da = origin.flatMap { o in boardState.piecePositions[a].map { o.distance(to: $0) } } ?? 0
            let db = origin.flatMap { o in boardState.piecePositions[b].map { o.distance(to: $0) } } ?? 0
            return (da, a) < (db, b)
        }.compactMap { target in
            attackPreview(attacker: attacker, target: target).map { "\(name(target)): \($0)" }
        }
    }
}

// MARK: - Turning an attack

extension BoardCoordinator {

    /// Whom an attack aimed at `aimedAt` hits: a character with Provoking Roar beside the target
    /// draws it, and Heart of the Betrayer turns an adjacent normal enemy's attack on one of its
    /// own allies.
    @MainActor func attackTarget(of attacker: PieceID, aimingAt aimedAt: PieceID, range: Int) async -> PieceID {
        let target = provokedTarget(of: attacker, aimingAt: aimedAt)
        return await betrayedTarget(of: attacker, aimingAt: target, range: range) ?? target
    }

    /// Heart of the Betrayer: "When attacked by an adjacent normal enemy, force the enemy to
    /// attack one of its allies within its range instead." The wearer chooses that ally.
    @MainActor private func betrayedTarget(of attacker: PieceID, aimingAt target: PieceID, range: Int) async -> PieceID? {
        guard case .character = target, case .monster = attacker, areEnemies(attacker, target),
              (entity(for: attacker) as? GameMonsterEntity)?.type == .normal,
              let from = boardState.piecePositions[attacker], let at = boardState.piecePositions[target],
              from.isAdjacent(to: at) else { return nil }
        let allies = alliesInRange(of: attacker, range: max(1, range), includeSelf: false)
            .filter { entity(for: $0) != nil && areEnemies($0, target) }.sorted()
        guard !allies.isEmpty else { return nil }
        let generation = boardGeneration
        guard await offerDefenseItem(DefenseItem.heartOfTheBetrayer, to: target, from: attacker),
              isCurrentBoard(generation) else { return nil }
        let ally = allies.count == 1 ? allies[0] : await chooseFigure(
            allies, title: "Heart of the Betrayer",
            question: "Which of its allies does \(name(attacker)) attack?")
        guard let ally, isCurrentBoard(generation) else { return nil }
        log("\(name(attacker)) turns on \(name(ally))", category: .attack)
        return ally
    }

    /// A figure the player picks from a list, while a monster's turn waits.
    struct PendingFigureChoice: Identifiable {
        let id = UUID()
        let title: String
        let question: String
        let options: [PieceID]
        /// The answer for none of them ("No one"), when the choice may be declined.
        var declineTitle: String? = nil
        var continuation: CheckedContinuation<PieceID?, Never>?
    }

    /// Ask which of `options`; with a `declineTitle` the player may choose none (nil).
    @MainActor func chooseFigure(_ options: [PieceID], title: String, question: String,
                                 declineTitle: String? = nil) async -> PieceID? {
        guard !autoResolvePrompts else { return options.first }
        return await withCheckedContinuation { continuation in
            pendingFigureChoice = PendingFigureChoice(title: title, question: question, options: options,
                                                      declineTitle: declineTitle, continuation: continuation)
        }
    }

    /// The figure chosen; nil declines a choice that may be declined, or takes the first otherwise.
    func resolveFigureChoice(_ piece: PieceID?) {
        guard let pending = pendingFigureChoice else { return }
        pendingFigureChoice = nil
        let chosen = piece.flatMap { pending.options.contains($0) ? $0 : nil }
        pending.continuation?.resume(returning: chosen ?? (pending.declineTitle == nil ? pending.options.first : nil))
    }

    // MARK: - Dampening Ring

    /// "Before an enemy would consume an element, consume that element instead for no effect."
    /// True when a character's ring took the elements first.
    @MainActor func dampenedConsume(_ elements: [ElementType], by monster: PieceID) async -> Bool {
        guard !autoResolvePrompts, !elements.contains(.wild), let gameManager,
              gameManager.game.canConsumeElements(elements) else { return false }
        let key = "gh-92"
        guard let holder = gameManager.game.characters.sorted(by: { $0.id < $1.id }).first(where: {
                  !$0.exhausted && !$0.absent && $0.carriedItems.contains(key)
                      && !$0.consumedItems.contains(key) && !$0.spentItems.contains(key)
              }),
              let item = itemData(key) else { return false }
        let generation = boardGeneration
        let names = GameText.list(elements.map(GameText.elementName))
        let use = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            pendingItemUse = PendingItemUse(characterID: holder.id, itemName: item.name,
                                            question: "Consume \(names) first, so \(name(monster)) can\u{2019}t?",
                                            attacker: name(monster), continuation: continuation,
                                            headline: "\(name(monster)) is about to consume \(names)")
        }
        guard use, isCurrentBoard(generation), gameManager.game.consumeElements(elements) != nil else { return false }
        gameManager.characterManager.onBeforeMutate?()
        holder.consumedItems.insert(key)
        gameManager.scenarioStatsManager.recordItemUse(by: holder.name)
        log("\(name(.character(holder.id)))\u{2019}s Dampening Ring consumes \(names) before \(name(monster)) can", category: .element)
        return true
    }
}
