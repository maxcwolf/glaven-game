import Foundation

/// A doomed enemy that died, its dooms still to resolve: what they do on death, Rain of Arrows'
/// attack, and whether they move to another enemy or their cards are discarded.
struct PendingDoomDeath {
    let piece: PieceID
    let position: HexCoord
    let dooms: [Doom]
}

/// The Doomstalker's dooms on the board (Engine/Doom.swift has what each does).
extension BoardCoordinator {

    // MARK: - Where the dooms are

    /// Every doom on a monster on the board, in figure order.
    var activeDooms: [(piece: PieceID, doom: Doom)] {
        guard let game = gameManager?.game else { return [] }
        var result: [(PieceID, Doom)] = []
        for monster in game.monsters {
            for entity in monster.entities where !entity.dead {
                let piece = PieceID.monster(name: monster.name, standee: entity.number)
                guard boardState.piecePositions[piece] != nil else { continue }
                for doom in Doom.dooms(in: entity.markers) { result.append((piece, doom)) }
            }
        }
        return result.sorted { $0.0 < $1.0 }.map { (piece: $0.0, doom: $0.1) }
    }

    func dooms(on piece: PieceID) -> [Doom] {
        guard case .monster(let name, let standee) = piece, let entity = monsterEntity(name: name, standee: standee) else { return [] }
        return Doom.dooms(in: entity.markers)
    }

    func isDoomed(_ piece: PieceID) -> Bool { !dooms(on: piece).isEmpty }

    private func setDooms(_ dooms: [Doom], on piece: PieceID) {
        guard case .monster(let name, let standee) = piece, let entity = monsterEntity(name: name, standee: standee) else { return }
        entity.markers.removeAll { $0.hasPrefix(Doom.prefix) }
        entity.markers.append(contentsOf: dooms.map(\.marker))
        boardScene?.refreshStatus(of: piece)
    }

    private func character(_ id: String) -> GameCharacter? {
        gameManager?.game.characters.first { $0.id == id }
    }

    // MARK: - Placing a doom

    /// The enemies a doom can go on: any enemy on the board; Inescapable Fate's only a normal or
    /// elite one.
    func doomCandidates(for character: GameCharacter, normalOrEliteOnly: Bool) -> [PieceID] {
        let me = PieceID.character(character.id)
        return boardState.piecePositions.keys.filter { piece in
            guard case .monster(let name, let standee) = piece, areEnemies(me, piece),
                  let entity = monsterEntity(name: name, standee: standee), !entity.dead else { return false }
            return !normalOrEliteOnly || entity.type == .normal || entity.type == .elite
        }.sorted()
    }

    /// Put a doom on `target`. Without Inescapable Fate a character has one doom: playing another
    /// discards the first. With it, two may share one target; a third on that target discards the
    /// older of the two, and one on a different target discards both.
    func placeDoom(cardId: Int, by character: GameCharacter, on target: PieceID) {
        let mine = activeDooms.filter { $0.doom.characterID == character.id && $0.doom.cardId != cardId }
        let twoAllowed = chargedBonuses(of: character).contains { $0.bonus == .twoDooms }
        var keep: [(piece: PieceID, doom: Doom)] = []
        if twoAllowed, mine.allSatisfy({ $0.piece == target }) {
            keep = Array(mine.suffix(1))   // the newest stays beside the new one
        }
        for old in mine where !keep.contains(where: { $0.doom == old.doom }) {
            endDoom(old.doom, on: old.piece, reason: "another Doom is played")
        }
        setDooms(dooms(on: target) + [Doom(characterID: character.id, cardId: cardId)], on: target)
        let cardName = gameManager?.characterManager.abilities(for: character).first { $0.cardId == cardId }?.name ?? "Doom"
        log("\(name(.character(character.id))) dooms \(name(target)) (\(cardName))", category: .condition)
        // Cloak of the Hunter: the doom's target is muddled.
        if character.carriedItems.contains(PassiveItems.cloakOfTheHunter) {
            applyCondition(.muddle, to: target)
        }
    }

    /// A doom ends: its token comes off the enemy, and its card leaves the active area.
    func endDoom(_ doom: Doom, on piece: PieceID?, reason: String) {
        if let piece { setDooms(dooms(on: piece).filter { $0 != doom }, on: piece) }
        guard let owner = character(doom.characterID) else { return }
        discardDoomCard(doom.cardId, of: owner)
        log("\(name(.character(owner.id)))\u{2019}s Doom ends: \(reason)", category: .info)
    }

    private func discardDoomCard(_ cardId: Int, of owner: GameCharacter) {
        if owner.activeCards.contains(cardId) {
            owner.removeFromActiveArea(cardId)
        } else if let turn = activePlayerTurn, turn.characterID == owner.id, turn.persistentCardsThisTurn.contains(cardId) {
            // Still being played: it goes to the discard pile instead of the active area.
            turn.usedUpThisTurn.insert(cardId)
        }
    }

    /// Lead to Slaughter: every doom moves to one enemy.
    func transferAllDooms(of character: GameCharacter, to target: PieceID) {
        for (piece, doom) in activeDooms where doom.characterID == character.id && piece != target {
            setDooms(dooms(on: piece).filter { $0 != doom }, on: piece)
            setDooms(dooms(on: target) + [doom], on: target)
        }
        log("\(name(.character(character.id))) moves their Dooms to \(name(target))", category: .condition)
    }

    // MARK: - Attacks against a doomed enemy

    /// The doom bonuses for one attack: +Attack, Pierce, advantage, Curse (Rain of Arrows,
    /// Multi-Pronged Assault, The Hunt Begins, Predator and Prey, Expose, Singular Focus,
    /// Crashing Wave), the round bonuses against doomed enemies, and Expose's advantage.
    func applyDoomBonuses(to attack: inout AttackParameters, attacker: PieceID, target: PieceID, distance: Int) {
        let targetDooms = dooms(on: target)
        guard !targetDooms.isEmpty, areEnemies(attacker, target) else { return }
        var bonus = 0
        for doom in targetDooms {
            let owner = PieceID.character(doom.characterID)
            let isAlly = attacker != owner && areAllies(attacker, owner)
            let isSummon: Bool = { if case .summon = attacker { return true }; return false }()
            switch doom.effect {
            case .attackBonus(let n, let who)? where DoomEffect.benefits(who, attacker: attacker, owner: owner, isAlly: isAlly, isSummon: isSummon):
                bonus += n
            case .rangeGapBonus? where attacker == owner || isAlly:
                bonus += max(0, attack.range - distance)
            case .pierce(let n, let who)? where DoomEffect.benefits(who, attacker: attacker, owner: owner, isAlly: isAlly, isSummon: isSummon):
                attack.pierce += n
            case .advantage(let who)? where DoomEffect.benefits(who, attacker: attacker, owner: owner, isAlly: isAlly, isSummon: isSummon):
                attack.advantage = true
            case .curse(let who)? where DoomEffect.benefits(who, attacker: attacker, owner: owner, isAlly: isAlly, isSummon: isSummon):
                if !attack.conditions.contains(.curse) { attack.conditions.append(.curse) }
            default:
                break
            }
        }
        // The attacker's own bonuses against doomed enemies.
        if case .character(let id) = attacker, let attackerCharacter = character(id) {
            for (_, charged) in chargedBonuses(of: attackerCharacter) {
                switch charged {
                case .roundAttackBonusVsDoomed(let n):
                    bonus += n
                case .advantageOncePerTurnVsDoomed where !exposeUsedThisTurn.contains(id) && activePlayerTurn?.characterID == id:
                    attack.advantage = true
                    exposeUsedThisTurn.insert(id)
                default:
                    break
                }
            }
        }
        if bonus > 0 {
            attack.value += bonus
            log("\(name(attacker)) gains +\(bonus) Attack against the doomed \(name(target))", category: .attack)
        }
    }

    /// Expose: while it's in play, enemies can't be invisible.
    var invisibilityExposed: Bool {
        gameManager?.game.characters.contains { !$0.exhausted && chargedBonuses(of: $0).contains { $0.bonus == .advantageOncePerTurnVsDoomed } } ?? false
    }

    // MARK: - Turns and damage

    /// Race to the Grave: a doomed enemy suffers damage as each of its turns starts.
    @MainActor func applyDoomTurnStart(_ piece: PieceID) async {
        for doom in dooms(on: piece) {
            guard case .damageAtTurnStart(let n)? = doom.effect, isOnBoard(piece) else { continue }
            log("\(name(piece)) suffers \(n) damage from its Doom", category: .damage)
            sufferDamage(n, to: piece, killer: .character(doom.characterID))
        }
        await resolveDoomDeaths()
    }

    /// Inescapable Fate: the marker advances as the owner's turn starts; after three the enemy dies.
    @MainActor func advanceDoomCountdowns(for character: GameCharacter) async {
        for (piece, doom) in activeDooms where doom.characterID == character.id {
            guard case .countdown(let turns)? = doom.effect else { continue }
            var next = doom
            next.marks += 1
            setDooms(dooms(on: piece).map { $0 == doom ? next : $0 }, on: piece)
            log("\(name(.character(character.id)))\u{2019}s Inescapable Fate: \(next.marks) of \(turns)", category: .condition)
            if next.marks >= turns, let entity = entity(for: piece) {
                log("Inescapable Fate kills \(name(piece))", category: .death)
                entity.health = 0
                handleDeath(of: piece, killer: .character(character.id))
            }
        }
        await resolveDoomDeaths()
    }

    /// Sap Life: the owner heals each time the doomed enemy suffers damage.
    func doomEnemyDamaged(_ piece: PieceID) {
        for doom in dooms(on: piece) {
            guard case .healOwnerWhenDamaged(let n)? = doom.effect else { continue }
            let owner = PieceID.character(doom.characterID)
            guard isOnBoard(owner) else { continue }
            let healed = heal(owner, amount: n, source: owner)
            log("\(name(owner)) heals \(healed) from Sap Life", category: .heal)
        }
    }

    // MARK: - Deaths

    /// A doomed enemy died: its dooms are resolved once the action that killed it is done.
    func noteDoomedDeath(_ piece: PieceID) {
        let dooms = dooms(on: piece)
        guard !dooms.isEmpty, let position = boardState.piecePositions[piece] else { return }
        pendingDoomDeaths.append(PendingDoomDeath(piece: piece, position: position, dooms: dooms))
    }

    /// Resolve the dooms of enemies that died: each doom's death effect, then Rain of Arrows'
    /// attack, then the dooms move to another enemy (Rising Momentum, Frightening Curse) or end.
    @MainActor func resolveDoomDeaths() async {
        let generation = boardGeneration
        while !pendingDoomDeaths.isEmpty || !pendingDamageAttacks.isEmpty, isCurrentBoard(generation), scenarioResult == nil {
            // Vengeful Barrage: "On the next five sources of damage to you, perform Attack 3."
            if !pendingDamageAttacks.isEmpty {
                let reaction = pendingDamageAttacks.removeFirst()
                if let owner = character(reaction.characterID) {
                    await reactionAttack(by: owner, value: reaction.value, range: 1, targets: 1)
                }
                continue
            }
            let death = pendingDoomDeaths.removeFirst()
            for doom in death.dooms {
                guard let owner = character(doom.characterID) else { continue }
                if case .onDeath(let effect)? = doom.effect {
                    await performDoomDeath(effect, owner: owner, at: death.position)
                    guard isCurrentBoard(generation) else { return }
                }
                // Rain of Arrows' top: "The next four times a Doomed enemy dies, perform Attack 2, Range 5."
                if isOnBoard(.character(owner.id)), let found = chargedBonuses(of: owner).first(where: {
                    if case .attackOnDoomedDeath = $0.bonus { return true }; return false }),
                   case .attackOnDoomedDeath(let value, let range) = found.bonus {
                    useCharge(found.cardId, of: owner)
                    await reactionAttack(by: owner, value: value, range: range, targets: 1)
                    guard isCurrentBoard(generation) else { return }
                }
            }
            await moveOrEndDooms(death)
        }
    }

    private func performDoomDeath(_ effect: DoomDeath, owner: GameCharacter, at hex: HexCoord) async {
        let me = PieceID.character(owner.id)
        switch effect {
        case .teleportOwner:
            guard isOnBoard(me), boardState.piece(at: hex) == nil, boardState.movePiece(me, to: hex) else { return }
            syncPieceVisuals()
            log("\(name(me)) teleports to where the doomed enemy fell", category: .move)
        case .healOwner(let n):
            guard isOnBoard(me) else { return }
            log("\(name(me)) heals \(heal(me, amount: n, source: me)) as the doomed enemy dies", category: .heal)
        case .healOwnerAndAllies(let n):
            let party = boardState.piecePositions.keys.filter { $0 == me || (areAllies(me, $0) && isFigure($0)) }.sorted()
            for figure in party {
                log("\(name(figure)) heals \(heal(figure, amount: n, source: figure))", category: .heal)
            }
        case .damageAdjacent(let n):
            for victim in hex.neighbors.compactMap({ boardState.piece(at: $0) }).filter({ areEnemies(me, $0) && isFigure($0) }).sorted() {
                log("\(name(victim)) suffers \(n) damage from the Doom", category: .damage)
                sufferDamage(n, to: victim, killer: me)
            }
        case .moveAdjacent(let n):
            // "Force all enemies adjacent to the hex in which it died to perform Move 1, with you
            // controlling the actions": moved away from that hex.
            for victim in hex.neighbors.compactMap({ boardState.piece(at: $0) }).filter({ areEnemies(me, $0) && isFigure($0) }).sorted() {
                await performPushPull(target: victim, attackerPos: hex, steps: n, isPush: true)
            }
        case .attack(let value, let range, let targets):
            await reactionAttack(by: owner, value: value, range: range, targets: targets)
        }
    }

    /// An attack a character performs in reaction (a doomed enemy dying, damage suffered), at
    /// enemies they choose.
    func reactionAttack(by owner: GameCharacter, value: Int, range: Int, targets: Int) async {
        let me = PieceID.character(owner.id)
        guard isOnBoard(me), !isConditionActive(.disarm, on: me) else { return }
        var chosen: [PieceID] = []
        for _ in 0..<targets {
            let options = targetableEnemies(of: me, range: range).filter { !chosen.contains($0) }.sorted()
            guard !options.isEmpty,
                  let target = await chooseFigure(options, title: "Attack \(value), Range \(range)",
                                                  question: "Which enemy does \(name(me)) attack?") else { break }
            chosen.append(target)
        }
        guard !chosen.isEmpty else { return }
        log("\(name(me)): Attack \(value)\(range > 1 ? ", Range \(range)" : "")", category: .attack)
        for target in chosen where isOnBoard(target) {
            await performAttack(attacker: me, target: target, attack: AttackParameters(value: value, isRanged: range > 1, range: range))
        }
    }

    /// After the death effects: the dooms move to an enemy within range of where it fell
    /// (Rising Momentum moves them all; Frightening Curse one, a charge each time), or end.
    private func moveOrEndDooms(_ death: PendingDoomDeath) async {
        var remaining = death.dooms
        let nearby: (Int) -> [PieceID] = { range in
            self.boardState.piecePositions.compactMap { piece, hex in
                guard case .monster = piece, piece != death.piece, !self.isPlayerSide(piece),
                      hex.distance(to: death.position) <= range else { return nil }
                return piece
            }.sorted()
        }
        if let momentum = remaining.first(where: { if case .transferOnDeath = $0.effect { return true }; return false }),
           case .transferOnDeath(let range)? = momentum.effect {
            let options = nearby(range)
            if !options.isEmpty, let target = await chooseFigure(options, title: "Rising Momentum",
                                                                 question: "Which enemy do the Dooms move to?") {
                setDooms(dooms(on: target) + remaining, on: target)
                log("The Dooms move to \(name(target))", category: .condition)
                return
            }
        }
        // Frightening Curse: one doom moves, a charge each time.
        if let ownerID = remaining.first?.characterID, let owner = character(ownerID),
           let curse = chargedBonuses(of: owner).first(where: { if case .transferDoomOnDeath = $0.bonus { return true }; return false }),
           case .transferDoomOnDeath(let range) = curse.bonus {
            let options = nearby(range)
            if !options.isEmpty, let target = await chooseFigure(options, title: "Frightening Curse",
                                                                 question: "Which enemy does the Doom move to?") {
                let moved = remaining.removeFirst()
                setDooms(dooms(on: target) + [moved], on: target)
                useCharge(curse.cardId, of: owner)
                log("The Doom moves to \(name(target))", category: .condition)
            }
        }
        for doom in remaining { endDoom(doom, on: nil, reason: "its enemy died") }
    }
}
