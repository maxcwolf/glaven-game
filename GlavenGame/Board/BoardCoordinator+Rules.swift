import Foundation

/// Shared rule helpers used by every turn controller, so damage, healing, conditions and deaths
/// are resolved the same way regardless of their source.
extension BoardCoordinator {

    // MARK: - Lookup

    /// The entity behind a board piece (nil for objectives without an entity or unknown pieces).
    func entity(for pieceID: PieceID) -> (any Entity)? {
        guard let game = gameManager?.game else { return nil }
        switch pieceID {
        case .character(let id):
            return game.characters.first { $0.id == id }
        case .monster(let name, let standee):
            return monsterEntity(name: name, standee: standee)
        case .summon(let id):
            for character in game.characters {
                if let summon = character.summons.first(where: { $0.id == id }) { return summon }
            }
            return nil
        case .objective(let number):
            for container in game.objectives {
                if let entity = container.entities.first(where: { $0.number == number }) { return entity }
            }
            return nil
        }
    }

    /// The current entity for a monster standee — the most recent one with that number, since
    /// a standee number can be reused after its previous monster died.
    func monsterEntity(name: String, standee: Int) -> GameMonsterEntity? {
        gameManager?.game.monsters.first { $0.name == name }?
            .entities.last { $0.number == standee }
    }

    /// The character that owns a summon piece.
    func summonOwner(of pieceID: PieceID) -> GameCharacter? {
        guard case .summon(let id) = pieceID else { return nil }
        return gameManager?.game.characters.first { $0.summons.contains { $0.id == id } }
    }

    /// The character credited for an action by `pieceID` (a summon's kills go to its owner).
    func creditedCharacter(for pieceID: PieceID?) -> GameCharacter? {
        guard let pieceID, let game = gameManager?.game else { return nil }
        if case .character(let id) = pieceID { return game.characters.first { $0.id == id } }
        return summonOwner(of: pieceID)
    }

    /// Whether two pieces are on opposing sides.
    func areEnemies(_ a: PieceID, _ b: PieceID) -> Bool {
        isPlayerSide(a) != isPlayerSide(b)
    }

    /// Characters, their summons, objectives (escorts) and allied monsters fight on the players' side.
    func isPlayerSide(_ pieceID: PieceID) -> Bool {
        switch pieceID {
        case .character, .summon, .objective:
            return true
        case .monster(let name, _):
            guard let monster = gameManager?.game.monsters.first(where: { $0.name == name }) else { return false }
            return MonsterAI.isAllyFaction(monster)
        }
    }

    func isConditionActive(_ condition: ConditionName, on pieceID: PieceID) -> Bool {
        guard let entity = entity(for: pieceID) else { return false }
        // Expose: "All enemies lose Invisible and may no longer gain Invisible."
        if condition == .invisible, case .monster = pieceID, !isPlayerSide(pieceID), invisibilityExposed { return false }
        return entity.entityConditions.contains { $0.name == condition && !$0.expired }
    }

    // MARK: - Healing

    /// Heal a figure following GH p.23: Poison is removed and blocks the healing; Wound is removed
    /// and the heal continues normally.
    @discardableResult
    func heal(_ pieceID: PieceID, amount: Int, source: PieceID? = nil) -> Int {
        guard let gameManager, let entity = entity(for: pieceID) else { return 0 }
        var amount = amount
        // Master Physician: the healer's heals first remove the healed figure's negative conditions.
        if let source, useFirstCharge(of: source, where: { $0 == .healCleanses }) != nil {
            entity.entityConditions.removeAll { $0.name.isNegative && !$0.permanent }
        }
        // Cauterize: +2 each time the character is healed.
        if case .healedBonus(let extra)? = useFirstCharge(of: pieceID, where: {
            if case .healedBonus = $0 { return true }; return false }) {
            amount += extra
        }
        let before = Set(entity.entityConditions.map(\.name))
        let healed = gameManager.entityManager.heal(entity, amount: amount)
        lastHealRemoved = before.subtracting(entity.entityConditions.map(\.name)).sorted { $0.rawValue < $1.rawValue }
        if healed > 0 { boardScene?.pieceHeal(id: pieceID, amount: healed) }
        boardScene?.refreshStatus(of: pieceID)
        return healed
    }

    /// The log line for a heal just made: "Spellweaver heals Cragheart for 3", "… and removes
    /// Wound", or "Spellweaver removes Cragheart's Poison" when the heal only removed Poison.
    func healLine(_ healer: PieceID, healed target: PieceID, for amount: Int) -> String {
        let removed = GameText.list(lastHealRemoved.map(GameText.conditionName))
        if amount == 0 && !lastHealRemoved.isEmpty {
            return "\(name(healer)) removes \(name(target))\u{2019}s \(removed)"
        }
        return "\(name(healer)) heals \(name(target)) for \(amount)" + (lastHealRemoved.isEmpty ? "" : " and removes \(removed)")
    }

    // MARK: - Conditions

    /// Apply a condition to a figure. Curse and Bless shuffle a card into the figure's attack
    /// modifier deck instead of placing a token (monsters share the monster deck; summons use
    /// their owner's deck; allied monsters use the ally deck).
    func applyCondition(_ condition: ConditionName, to pieceID: PieceID) {
        guard let gameManager, let entity = entity(for: pieceID) else { return }
        if let topic = LearnTopic.id(for: condition) {
            teach(topic, "\(name(pieceID)) has \(GameText.conditionName(condition)).", at: .piece(pieceID))
        }
        if condition == .muddle, let character = entity as? GameCharacter,
           character.carriedItems.contains(PassiveItems.muddleToStrengthen) {
            log("\(name(pieceID))\u{2019}s Drakescale Helm turns Muddle into Strengthen", category: .condition)
            applyCondition(.strengthen, to: pieceID)
            return
        }
        let itemImmunity = (entity as? GameCharacter).map { PassiveItems.immune($0.carriedItems, to: condition) } ?? false
        guard !entity.immunities.contains(condition), !itemImmunity else {
            boardScene?.floatText("Immune", over: pieceID, style: .info)
            log("\(name(pieceID)) is immune to \(GameText.conditionName(condition))", category: .condition)
            return
        }
        if condition == .curse || condition == .bless {
            let type: AttackModifierType = condition == .curse ? .curse : .bless
            let monsterDeck: Bool = { if case .monster = pieceID { return !isPlayerSide(pieceID) }; return false }()
            guard gameManager.game.hasSpecialCardLeft(type, forMonsterDeck: monsterDeck) else {
                log("No \(GameText.conditionName(condition)) cards are left for \(name(pieceID))", category: .condition)
                return
            }
            switch pieceID {
            case .character(let id):
                gameManager.game.characters.first { $0.id == id }?.attackModifierDeck.addCard(type: type)
            case .summon:
                summonOwner(of: pieceID)?.attackModifierDeck.addCard(type: type)
            case .monster:
                if isPlayerSide(pieceID) {
                    gameManager.game.allyAttackModifierDeck.addCard(type: type)
                } else {
                    gameManager.game.monsterAttackModifierDeck.addCard(type: type)
                }
            case .objective:
                gameManager.game.allyAttackModifierDeck.addCard(type: type)
            }
            // Curse and bless go into a deck, not onto the token: say so over the figure.
            boardScene?.announce(condition, on: pieceID, gained: true)
        } else {
            gameManager.entityManager.addCondition(condition, to: entity)
        }
        boardScene?.refreshStatus(of: pieceID)
        log("\(name(pieceID)) gains \(GameText.conditionName(condition))", category: .condition)
    }

    // MARK: - Damage & Death

    /// Apply damage to a figure without the character card-loss option, then resolve its death.
    /// Returns true if the figure died.
    @discardableResult
    func sufferDamage(_ amount: Int, to pieceID: PieceID, killer: PieceID? = nil) -> Bool {
        guard amount > 0, let gameManager, let entity = entity(for: pieceID) else { return false }
        // Intervening Apparitions: the owner's summons suffer no damage.
        if case .summon = pieceID, let owner = summonOwner(of: pieceID),
           useFirstCharge(of: .character(owner.id), where: { $0 == .summonsNegateDamage }) != nil {
            log("\(name(pieceID)) suffers no damage", category: .damage)
            boardScene?.pieceUnharmed(id: pieceID, missed: false)
            return false
        }
        // Juggernaut, Frost Armor: "suffer no damage instead", a charge each time. Defiance of
        // Death: only damage that would bring the character below 1 hit point.
        if useFirstCharge(of: pieceID, where: { $0 == .negateDamage || $0 == .negateNextDamage }) != nil
            || (amount >= entity.health && useFirstCharge(of: pieceID, where: { $0 == .negateLethal }) != nil) {
            log("\(name(pieceID)) suffers no damage", category: .damage)
            boardScene?.pieceUnharmed(id: pieceID, missed: false)
            return false
        }
        let (healthBefore, maxHealth) = (entity.health, entity.maxHealth)
        gameManager.entityManager.changeHealth(entity, amount: -amount)
        boardScene?.pieceDamage(id: pieceID, amount: amount)
        doomEnemyDamaged(pieceID)   // Sap Life
        // Vengeful Barrage: the character attacks back once the damage is done.
        if case .character(let id) = pieceID, entity.health > 0, let character = gameManager.game.characters.first(where: { $0.id == id }),
           let found = chargedBonuses(of: character).first(where: { if case .attackOnDamage = $0.bonus { return true }; return false }),
           case .attackOnDamage(let value) = found.bonus {
            useCharge(found.cardId, of: character)
            pendingDamageAttacks.append((characterID: id, value: value))
        }
        boardScene?.refreshStatus(of: pieceID)
        if let dealer = creditedCharacter(for: killer), killer != pieceID {
            gameManager.scenarioStatsManager.recordDamageDealt(by: dealer.name, amount: amount)
            if activePlayerTurn?.characterID == dealer.id, killer == .character(dealer.id) {
                activePlayerTurn?.damageInflicted += amount
            }
        }
        if entity.health <= 0 {
            handleDeath(of: pieceID, killer: killer, overkill: amount - healthBefore,
                        fromFullHealth: healthBefore == maxHealth)
            return true
        }
        return false
    }

    /// Damage a character may negate by losing cards (GH p.22). Prompts the player when they have
    /// cards to lose; other figures simply take the damage. Returns true if the figure died.
    @discardableResult
    @MainActor func sufferDamageWithMitigation(_ amount: Int, to pieceID: PieceID, source: String,
                                    killer: PieceID? = nil) async -> Bool {
        guard amount > 0 else { return false }
        if case .character(let id) = pieceID, !negatesDamage(pieceID, amount: amount),
           let character = gameManager?.game.characters.first(where: { $0.id == id }),
           await promptDamageMitigation(character: character, damage: amount, source: source) {
            if isOnBoard(pieceID) { boardScene?.floatText("Prevented", over: pieceID, style: .info) }
            return false
        }
        return sufferDamage(amount, to: pieceID, killer: killer)
    }

    /// Hand cards a character can lose to negate damage. The two cards played this round are no
    /// longer in the hand (GH p.22), even before they are put away at the end of the turn.
    func losableHandCards(of character: GameCharacter) -> [Int] {
        let played = selectedCardPairs[character.id].map { [$0.top.cardId, $0.bottom.cardId] } ?? []
        return character.handCards.filter { !played.contains($0) }
    }

    /// Offer the "lose 1 hand card or 2 discards to negate the damage" choice.
    /// Returns true if the damage was negated.
    @MainActor func promptDamageMitigation(character: GameCharacter, damage: Int, source: String) async -> Bool {
        let canLoseHand = !losableHandCards(of: character).isEmpty
        let canLoseDiscard = character.discardedCards.count >= 2
        guard canLoseHand || canLoseDiscard, !autoResolvePrompts else { return false }

        let generation = boardGeneration
        let choice = await withCheckedContinuation { (continuation: CheckedContinuation<DamageMitigationChoice, Never>) in
            teach(.preventingDamage)
            pendingDamage = PendingDamage(characterID: character.id, damage: damage,
                                          sourceDescription: source, continuation: continuation)
        }
        // The board was left while the player chose: nothing is lost and no damage is taken.
        guard isCurrentBoard(generation) else { return true }

        switch choice {
        case .takeDamage:
            return false
        case .loseHandCard(let cardId):
            guard losableHandCards(of: character).contains(cardId),
                  let index = character.handCards.firstIndex(of: cardId) else { return false }
            character.lostCards.append(character.handCards.remove(at: index))
            log("\(characterName(character.id)) loses a card from hand to prevent \(damage) damage", category: .damage)
            return true
        case .loseDiscardCards(let indices):
            guard indices.count >= 2 else { return false }
            for idx in indices.sorted(by: >) where idx < character.discardedCards.count {
                character.lostCards.append(character.discardedCards.remove(at: idx))
            }
            log("\(characterName(character.id)) loses 2 discarded cards to prevent \(damage) damage", category: .damage)
            return true
        }
    }

    /// Resolve a figure reaching 0 HP: monsters die (money token for normal/elite monsters that
    /// were not summoned or spawned), summons are removed, characters become exhausted.
    /// `overkill` and `fromFullHealth` describe the blow that killed it, for battle goals.
    func handleDeath(of pieceID: PieceID, killer: PieceID? = nil, overkill: Int = 0, fromFullHealth: Bool = false) {
        guard let gameManager else { return }
        boardScene?.play(.death)
        switch pieceID {
        case .character(let id):
            if let character = gameManager.game.characters.first(where: { $0.id == id }) {
                exhaust(character, reason: "0 HP")
            }
        case .monster(let name, let standee):
            guard let monster = gameManager.game.monsters.first(where: { $0.name == name }),
                  let entity = monsterEntity(name: name, standee: standee),
                  boardState.piecePositions[pieceID] != nil else {
                removePieceFromBoard(pieceID)
                return
            }
            entity.dead = true
            log("\(self.name(pieceID)) dies", category: .death)
            // Cultists: "On death: Attack +2" on this round's card, made from where it fell.
            if let position = boardState.piecePositions[pieceID],
               let ability = gameManager.monsterManager.currentAbility(for: monster),
               let onDeath = (ability.actions ?? []).first(where: {
                   $0.type == .custom && $0.value?.stringValue.contains("ondeath") == true }),
               let attack = onDeath.subActions?.first(where: { $0.type == .attack }) {
                pendingDeathAttacks.append(DeathAttack(attacker: pieceID, monster: name, type: entity.type,
                                                       position: position, action: attack))
            }
            // GH p.19: a money token drops where a monster dies unless it was summoned or spawned;
            // bosses and named monsters drop none either.
            if entity.summonState == nil && entity.type != .boss && !monster.isBoss {
                dropLoot(for: pieceID)
            }
            noteDoomedDeath(pieceID)
            removePieceFromBoard(pieceID)
            recordMonsterKill(name: name)
            if let character = creditedCharacter(for: killer) {
                gameManager.scenarioStatsManager.recordKill(by: character.name, monster: name, elite: entity.type == .elite,
                                                           overkill: max(0, overkill), fromFullHealth: fromFullHealth)
            }
            if case .character(let id) = killer, activePlayerTurn?.characterID == id,
               let character = gameManager.game.characters.first(where: { $0.id == id }) {
                rewardKillOnOwnTurn(character)
            }
            gameManager.scenarioRulesManager.evaluateRules()
        case .summon(let id):
            if let owner = summonOwner(of: pieceID),
               let summon = owner.summons.first(where: { $0.id == id }) {
                summon.dead = true
                log("\(name(pieceID)) dies", category: .death)
            }
            removePieceFromBoard(pieceID)
        case .objective(let number):
            for container in gameManager.game.objectives {
                if let entity = container.entities.first(where: { $0.number == number }) {
                    entity.dead = true
                }
            }
            log("\(name(pieceID)) is destroyed", category: .death)
            removePieceFromBoard(pieceID)
            gameManager.scenarioRulesManager.evaluateRules()
        }
        checkVictoryDefeat()
    }

    /// Exhaust a character: all its cards go to the lost pile, its figure and summons leave the
    /// board, and it takes no further part in the scenario (GH p.27).
    func exhaust(_ character: GameCharacter, reason: String) {
        guard !character.exhausted || boardState.piecePositions[.character(character.id)] != nil else { return }
        character.exhausted = true
        character.lostCards.append(contentsOf: character.handCards + character.discardedCards + character.activeCards)
        character.handCards = []
        character.discardedCards = []
        character.activeCards = []
        character.roundBonusCards = []
        character.lostWhenRemoved = []
        log("\(characterName(character.id)) is exhausted", category: .death, trace: reason)
        gameManager?.scenarioStatsManager.recordExhausted(character.name)
        removePieceFromBoard(.character(character.id))
        if let turn = activePlayerTurn, turn.characterID == character.id {
            turn.endForExhaustion()
            interactionMode = .idle
        }
        for summon in character.summons where !summon.dead {
            summon.dead = true
            removePieceFromBoard(.summon(id: summon.id))
        }
        checkVictoryDefeat()
    }

    func removePieceFromBoard(_ pieceID: PieceID) {
        boardState.removePiece(pieceID)
        boardScene?.removePieceSprite(id: pieceID)
    }

    /// Resolve any figure that dropped to 0 HP outside an attack (wound, bane, self-damage…).
    func sweepDeadFigures() {
        guard let gameManager else { return }
        for pieceID in boardState.piecePositions.keys.sorted() {
            // Earlier deaths in this sweep may already have removed it (e.g. an exhausted owner's summons).
            guard isOnBoard(pieceID) else { continue }
            switch pieceID {
            case .character(let id):
                if let c = gameManager.game.characters.first(where: { $0.id == id }), c.health <= 0 || c.exhausted {
                    exhaust(c, reason: "0 HP")
                }
            case .monster(let name, let standee):
                let entity = monsterEntity(name: name, standee: standee)
                if entity == nil || entity!.dead || entity!.health <= 0 {
                    handleDeath(of: pieceID)
                }
            case .summon:
                if let summon = entity(for: pieceID) as? GameSummon {
                    if summon.health <= 0 || summon.dead { handleDeath(of: pieceID) }
                } else {
                    removePieceFromBoard(pieceID)
                }
            case .objective:
                if let objective = entity(for: pieceID) as? GameObjectiveEntity, objective.health <= 0 || objective.dead {
                    handleDeath(of: pieceID)
                }
            }
        }
    }
}
