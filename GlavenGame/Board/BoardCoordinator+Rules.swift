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

    /// The objective a piece is one of.
    func objectiveContainer(of pieceID: PieceID) -> GameObjectiveContainer? {
        guard case .objective(let number) = pieceID else { return nil }
        return gameManager?.game.objectives.first { $0.entities.contains { $0.number == number } }
    }

    /// An objective that isn't an escort: a thing on the map (an altar, a barred door, a
    /// captive). It is no one's ally, takes no conditions and is never moved. With hit points it
    /// is there to be destroyed — an enemy of the players' side — or, one the scenario has the
    /// party protect, of the monsters.
    func isScenery(_ pieceID: PieceID) -> Bool {
        objectiveContainer(of: pieceID).map { !$0.escort } ?? false
    }

    /// Scenery without hit points (a water pump): nothing attacks it.
    private func isUntouchable(_ pieceID: PieceID) -> Bool {
        // An ally only to be healed is no one's enemy either, and nothing affects an inactive monster.
        if objectiveContainer(of: pieceID)?.isSheltered == true || isInactive(pieceID) { return true }
        guard isScenery(pieceID) else { return false }
        return (entity(for: pieceID)?.maxHealth ?? 0) <= 0
    }

    /// Whether two pieces are on opposing sides.
    func areEnemies(_ a: PieceID, _ b: PieceID) -> Bool {
        side(of: a) != side(of: b) && !isUntouchable(a) && !isUntouchable(b)
    }

    /// The side a piece fights on. Monsters that stand apart are a third, against both others.
    func side(of pieceID: PieceID) -> MonsterAI.Side {
        if case .monster(let name, _) = pieceID, let monster = gameManager?.game.monsters.first(where: { $0.name == name }) {
            return MonsterAI.side(of: monster)
        }
        return isPlayerSide(pieceID) ? .party : .monsters
    }

    /// Whether two pieces fight on the same side. Scenery is on no side, and what the party only
    /// protects (a captive, a crystal, the villagers) is no one's ally: it isn't healed or helped.
    func areAllies(_ a: PieceID, _ b: PieceID) -> Bool {
        side(of: a) == side(of: b) && !isScenery(a) && !isScenery(b) && !isProtected(a) && !isProtected(b)
            && !isInactive(a) && !isInactive(b)
    }

    /// A monster of a type that sits this round out, or hasn't woken yet.
    func isInactive(_ pieceID: PieceID) -> Bool {
        guard case .monster(let name, _) = pieceID, let game = gameManager?.game else { return false }
        return MonsterAI.inactiveMonsters(game).contains(name)
    }

    /// An objective the party is to keep from harm without its being an ally.
    func isProtected(_ pieceID: PieceID) -> Bool {
        objectiveContainer(of: pieceID)?.isProtected ?? false
    }

    /// Characters, their summons, escorts and allied monsters fight on the players' side; what
    /// the party protects stands on it.
    func isPlayerSide(_ pieceID: PieceID) -> Bool {
        switch pieceID {
        case .character, .summon:
            return true
        case .objective:
            return objectiveContainer(of: pieceID).map { $0.escort || $0.isProtected } ?? true
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
        if let source, healCleanses(by: source) {
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

    /// A condition one figure gives another with an ability of its own. Unending Chant: "the
    /// next five times you Curse an enemy, Curse them an additional time" — by an attack or by
    /// any other ability, a charge for each enemy cursed.
    func applyCondition(_ condition: ConditionName, to target: PieceID, by source: PieceID) {
        applyCondition(condition, to: target)
        if condition == .curse, areEnemies(source, target), useFirstCharge(of: source, where: { $0 == .doubleCurses }) != nil {
            applyCondition(.curse, to: target)
        }
    }

    /// Apply a condition to a figure. Curse and Bless shuffle a card into the figure's attack
    /// modifier deck instead of placing a token (monsters share the monster deck; summons use
    /// their owner's deck; allied monsters use the ally deck).
    func applyCondition(_ condition: ConditionName, to pieceID: PieceID) {
        guard let gameManager, let entity = entity(for: pieceID) else { return }
        // An objective on the map (an altar, a door) is immune to every condition.
        guard !isScenery(pieceID) else {
            boardScene?.floatText("Immune", over: pieceID, style: .info)
            log("\(name(pieceID)) is immune to \(GameText.conditionName(condition))", category: .condition)
            return
        }
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
        guard !entity.immunities.contains(condition), !itemImmunity, !scenarioWardsOff(condition, from: pieceID) else {
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
        // What the scenario lets nothing damage (Chained Isle's Living Spirits).
        if isUndamageable(pieceID) {
            log("\(name(pieceID)) can\u{2019}t be damaged", category: .damage)
            boardScene?.pieceUnharmed(id: pieceID, missed: false)
            return false
        }
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
        await resolveDamage(amount, to: pieceID, source: source, killer: killer).died
    }

    /// The same, saying also whether the damage was prevented by losing cards. Where a bonus
    /// would take the damage (Frost Armor, Juggernaut), the player may still lose cards first
    /// and keep its charge (FAQ); left alone, the charge takes it.
    @MainActor func resolveDamage(_ amount: Int, to pieceID: PieceID, source: String,
                                  killer: PieceID? = nil) async -> (died: Bool, prevented: Bool) {
        guard amount > 0 else { return (false, false) }
        if case .character(let id) = pieceID,
           let character = gameManager?.game.characters.first(where: { $0.id == id }),
           await promptDamageMitigation(character: character, damage: amount, source: source,
                                        absorbedBy: negatingBonusName(pieceID, amount: amount)) {
            if isOnBoard(pieceID) { boardScene?.floatText("Prevented", over: pieceID, style: .info) }
            return (false, true)
        }
        // What the party protects: a card lost from a hand spares it this source of damage.
        if await promptSave(of: pieceID, damage: amount, source: source) {
            if isOnBoard(pieceID) { boardScene?.floatText("Spared", over: pieceID, style: .info) }
            return (false, true)
        }
        return (sufferDamage(amount, to: pieceID, killer: killer), false)
    }

    /// Damage a character brings on themself in their turn — a printed "suffer 2 damage", an
    /// item's cost, the Berserker's "suffer up to N" — may be negated by losing cards like damage
    /// from any other source (GH p.22, FAQ). With cards to lose the player is asked, and `then`
    /// runs once they have answered (true is returned); otherwise the damage is taken now.
    @discardableResult
    func sufferOwnDamage(_ amount: Int, characterID: String, source: String, then: (() -> Void)? = nil) -> Bool {
        let piece = PieceID.character(characterID)
        guard amount > 0, !autoResolvePrompts,
              let character = gameManager?.game.characters.first(where: { $0.id == characterID }),
              !losableHandCards(of: character).isEmpty || character.discardedCards.count >= 2 else {
            sufferDamage(amount, to: piece)
            return false
        }
        let generation = boardGeneration
        Task { @MainActor in
            await self.sufferDamageWithMitigation(amount, to: piece, source: source)
            guard self.isCurrentBoard(generation) else { return }
            then?()
        }
        return true
    }

    /// Hand cards a character can lose to negate damage. The two cards played this round are no
    /// longer in the hand (GH p.22), even before they are put away at the end of the turn.
    func losableHandCards(of character: GameCharacter) -> [Int] {
        let played = selectedCardPairs[character.id].map { [$0.top.cardId, $0.bottom.cardId] } ?? []
        return character.handCards.filter { !played.contains($0) }
    }

    /// Offer the "lose 1 hand card or 2 discards to negate the damage" choice.
    /// Returns true if the damage was negated.
    @MainActor func promptDamageMitigation(character: GameCharacter, damage: Int, source: String,
                                           absorbedBy: String? = nil) async -> Bool {
        let canLoseHand = !losableHandCards(of: character).isEmpty
        let canLoseDiscard = character.discardedCards.count >= 2
        guard canLoseHand || canLoseDiscard, !autoResolvePrompts else { return false }

        let generation = boardGeneration
        let choice = await withCheckedContinuation { (continuation: CheckedContinuation<DamageMitigationChoice, Never>) in
            teach(.preventingDamage)
            pendingDamage = PendingDamage(characterID: character.id, damage: damage,
                                          sourceDescription: source, continuation: continuation, absorbedBy: absorbedBy)
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
            boardScene?.play(.lose)
            log("\(characterName(character.id)) loses a card from hand to prevent \(damage) damage", category: .damage)
            return true
        case .loseDiscardCards(let indices):
            guard indices.count >= 2 else { return false }
            for idx in indices.sorted(by: >) where idx < character.discardedCards.count {
                character.lostCards.append(character.discardedCards.remove(at: idx))
            }
            boardScene?.play(.lose)
            log("\(characterName(character.id)) loses 2 discarded cards to prevent \(damage) damage", category: .damage)
            return true
        }
    }

    /// Resolve a figure reaching 0 HP: monsters die (a money token for an enemy monster that was
    /// not summoned or spawned), summons are removed, characters become exhausted.
    /// `overkill` and `fromFullHealth` describe the blow that killed it, for battle goals.
    func handleDeath(of pieceID: PieceID, killer: PieceID? = nil, overkill: Int = 0, fromFullHealth: Bool = false) {
        guard let gameManager else { return }
        // A character going down is exhaustion, with its own cue.
        if case .character = pieceID {} else { boardScene?.play(.death) }
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
            let fellAt = boardState.piecePositions[pieceID]
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
            // GH p.21: a money token drops where a monster dies unless it was summoned or spawned —
            // a boss set up with the room like any other. An allied monster drops none (FAQ).
            if entity.summonState == nil && !MonsterAI.isAllyFaction(monster) {
                dropLoot(for: pieceID)
            }
            noteDoomedDeath(pieceID)
            removePieceFromBoard(pieceID)
            recordMonsterKill(name: name)
            grantReprieve(forDeathOf: name, killer: killer)
            if entity.type == .elite, !MonsterAI.isAllyFaction(monster) { boardState.eliteKills += 1 }
            if let character = creditedCharacter(for: killer) {
                gameManager.scenarioStatsManager.recordKill(by: character.name, monster: name, elite: entity.type == .elite,
                                                           overkill: max(0, overkill), fromFullHealth: fromFullHealth)
            }
            if case .character(let id) = killer, activePlayerTurn?.characterID == id,
               let character = gameManager.game.characters.first(where: { $0.id == id }) {
                rewardKillOnOwnTurn(character)
            }
            // What its death brings appears where it fell (the Infiltrator, in the place of the
            // guard marked for it).
            fallenFigure = fellAt.map { (markers: entity.markers, hex: $0) }
            gameManager.scenarioRulesManager.evaluateRules()
            fallenFigure = nil
            updateLocks()
        case .summon(let id):
            if let owner = summonOwner(of: pieceID),
               let summon = owner.summons.first(where: { $0.id == id }) {
                summon.dead = true
                log("\(name(pieceID)) dies", category: .death)
                retireSummonCard(of: summon, owner: owner)
            }
            removePieceFromBoard(pieceID)
        case .objective(let number):
            for container in gameManager.game.objectives {
                if let entity = container.entities.first(where: { $0.number == number }) {
                    entity.dead = true
                }
            }
            log("\(name(pieceID)) is \(isScenery(pieceID) && !isPlayerSide(pieceID) ? "destroyed" : "killed")", category: .death)
            // What its destruction spawns appears where it stood (a corpse from a dug-up grave).
            fallenFigure = boardState.piecePositions[pieceID].flatMap { hex in
                (entity(for: pieceID) as? GameObjectiveEntity).map { (markers: [$0.marker] + $0.markers, hex: hex) }
            }
            let stood = boardState.piecePositions[pieceID]
            let index = objectiveContainer(of: pieceID)?.objectiveIndex
            removePieceFromBoard(pieceID)
            clearObjectiveSite(number)
            // What the scenario has appear in its place (a Living Corpse from a dug-up grave).
            if let stood, let index, let risen = scenarioData?.placements?.whenDestroyed?[String(index)],
               let type = risen.monsterType(forPlayerCount: gameManager.game.characterCount),
               let piece = spawnMonster(name: risen.name, type: type, at: stood, origin: .spawned) {
                log("\(name(piece)) appears", category: .setup, trace: "at \(stood)")
            }
            gameManager.scenarioRulesManager.evaluateRules()
            fallenFigure = nil
        }
        checkVictoryDefeat()
    }

    /// A summon's card stays in the active area only while its summon lives (GH p.26): with the
    /// last of a card's summons dead, the card leaves — to the lost pile if its action has the
    /// lost icon.
    func retireSummonCard(of summon: GameSummon, owner: GameCharacter) {
        guard let gameManager else { return }
        let deck = gameManager.characterManager.abilities(for: owner)
        for cardId in owner.activeCards {
            guard let card = deck.first(where: { $0.cardId == cardId }) else { continue }
            let top = isTopHalfInPlay(cardId, of: owner)
            let names = Self.summonNames(in: (top ? card.actions : card.bottomActions) ?? [])
            guard names.contains(summon.name),
                  !owner.summons.contains(where: { !$0.dead && $0.uuid != summon.uuid && names.contains($0.name) }) else { continue }
            owner.removeFromActiveArea(cardId)
            log("\(card.name ?? "The card") leaves \(name(.character(owner.id)))\u{2019}s active area", category: .info)
            return
        }
    }

    /// The summons a half of a card brings, by name.
    static func summonNames(in actions: [ActionModel]) -> Set<String> {
        var names = Set<String>()
        for action in actions {
            if action.type == .summon, let name = action.summonValueObject?.name ?? action.value?.stringValue {
                names.insert(name)
            }
            names.formUnion(summonNames(in: action.subActions ?? []))
        }
        return names
    }

    /// Exhaust a character: all its cards go to the lost pile, its figure and summons leave the
    /// board, and it takes no further part in the scenario (GH p.27).
    func exhaust(_ character: GameCharacter, reason: String) {
        guard !character.exhausted || boardState.piecePositions[.character(character.id)] != nil else { return }
        // Where a scenario is lost by a character's exhaustion (away from the exit, before the
        // treasure is looted), it is judged where they stood.
        let loss = exhaustionLoss(of: character, at: boardState.piecePositions[.character(character.id)])
        log("\(characterName(character.id)) is exhausted", category: .death, trace: reason)
        gameManager?.scenarioStatsManager.recordExhausted(character.name)
        leaveScenario(character)
        updateLocks()
        if let loss, scenarioResult == nil, pendingResult == nil {
            pendingResult = .defeat
            endReason = .ruleLost(loss)
            log("Scenario failed — the scenario ends at the end of this round.", category: .death)
        }
        checkVictoryDefeat()
    }

    /// A character takes no further part in the scenario: its figure and summons leave the
    /// board. Exhausted, all its cards are lost (GH p.27). Gone through the exit it is marked the
    /// same way, so that no turn or choice comes to it again, but it isn't exhausted
    /// (`ScenarioStatsManager.wasExhausted`): it keeps its hand and discards as they were, and
    /// only its cards in play are put away.
    func leaveScenario(_ character: GameCharacter, exhausted: Bool = true) {
        character.exhausted = true
        if exhausted {
            boardScene?.play(.exhaust)
            character.lostCards.append(contentsOf: character.handCards + character.discardedCards + character.activeCards)
            character.handCards = []
            character.discardedCards = []
            character.activeCards = []
            character.roundBonusCards = []
            character.lostWhenRemoved = []
            character.bottomHalvesInPlay = []
        } else {
            for cardId in character.activeCards { character.removeFromActiveArea(cardId) }
        }
        removePieceFromBoard(.character(character.id))
        if let turn = activePlayerTurn, turn.characterID == character.id {
            turn.endForExhaustion()
            interactionMode = .idle
        }
        for summon in character.summons where !summon.dead {
            summon.dead = true
            removePieceFromBoard(.summon(id: summon.id))
        }
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
                // One without hit points (a water pump) isn't destroyed by having none.
                if let objective = entity(for: pieceID) as? GameObjectiveEntity,
                   objective.dead || (objective.health <= 0 && objective.maxHealth > 0) {
                    handleDeath(of: pieceID)
                }
            }
        }
    }
}
