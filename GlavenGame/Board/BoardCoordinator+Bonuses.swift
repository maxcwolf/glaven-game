import Foundation

/// Persistent bonuses with charges (GH p.24): "on the next six sources of damage…", "on your
/// next four ranged attack actions…". The card stays in the active area and a charge is marked
/// each time the bonus applies (some slots give experience); when every charge is marked the
/// card leaves the active area, to the lost pile if it has the lost icon.
///
/// Played so far: the charged cards whose effect needs no extra choice.
enum ChargedBonus: Equatable {
    /// Shield N against each attack that would damage the character.
    case shieldAgainstAttacks(Int)
    /// Suffer no damage, from any source.
    case negateDamage
    /// Suffer no damage from an attack, and retaliate against the attacker within range.
    case negateAttackAndRetaliate(Int, range: Int)
    /// Retaliate N against each melee attack targeting the character.
    case retaliateAgainstMelee(Int)
    /// One more target on each of the character's ranged attack actions.
    case extraTargetOnRanged
    /// On each of the character's attack actions: +N, added conditions, advantage.
    case attackPackage(bonus: Int, conditions: [ConditionName], advantage: Bool)
    /// A condition added to each attack made while invisible.
    case conditionWhileInvisible(ConditionName)
    /// +N each time the character is healed.
    case healedBonus(Int)
    /// The character's heals first remove the healed figure's negative conditions.
    case healCleanses
    /// Suffer no damage that would bring the character below 1 hit point.
    case negateLethal
    /// At the end of the character's turn, infuse the element unless it is already strong.
    case endOfTurnInfuse(ElementType)
    /// At the end of the character's turn, heal every adjacent ally.
    case endOfTurnHealAdjacent(Int)

    // Round bonuses (no charges: they last until the card leaves at the end of the round).
    enum Reach: Equatable { case any, melee, ranged }
    /// +N on every attack of that reach this round (Wall of Doom, Heaving Swing, Forceful Storm).
    case roundAttackBonus(Int, Reach)
    /// +N on every attack this round, for the character and allies beside them (Enhancement Field).
    case roundAttackBonusWithAdjacentAllies(Int)
    /// 1 experience each time the character retaliates this round (Eye for an Eye).
    case experiencePerRetaliate
    /// The next damage this round is negated (Trickster's Reversal: a single use).
    case negateNextDamage
    /// Enemies attacking an ally beside the character attack the character instead (Provoking Roar).
    case drawAttacksFromAdjacentAllies

    /// Round bonuses don't use charges; every use leaves them in place.
    var isUnlimited: Bool {
        switch self {
        case .roundAttackBonus, .roundAttackBonusWithAdjacentAllies, .experiencePerRetaliate,
             .drawAttacksFromAdjacentAllies: return true
        default: return false
        }
    }
    /// +N on each of the character's heal actions.
    case healBonus(Int)
    /// +N on an attack against an enemy adjacent to none of its allies.
    case bonusAgainstIsolated(Int)
    /// +N on an attack against an enemy that is disarmed, immobilized or stunned.
    case bonusAgainstDisabled(Int)
    /// Double the attack while the character is invisible.
    case doubleWhileInvisible
    /// Double the attack against an enemy adjacent to none of its allies but to one of the character's.
    case doubleAgainstFlanked

    /// By edition and card id.
    static let byCard: [String: ChargedBonus] = [
        "gh-7": .shieldAgainstAttacks(1),                       // Warding Strength
        "gh-15": .negateDamage,                                 // Juggernaut
        "gh-116": .retaliateAgainstMelee(2),                    // Opposing Strike
        "gh-121": .extraTargetOnRanged,                         // Backup Ammunition
        "gh-88": .bonusAgainstIsolated(2),                      // Single Out
        "gh-90": .doubleWhileInvisible,                         // Smoke Bomb
        "gh-106": .bonusAgainstDisabled(2),                     // Cull the Weak
        "gh-111": .doubleAgainstFlanked,                        // Spring the Trap
        "gh-66": .negateDamage,                                 // Frost Armor
        "gh-69": .attackPackage(bonus: 1, conditions: [], advantage: false), // Crackling Air
        "gh-79": .retaliateAgainstMelee(3),                     // Engulfed in Flames
        "gh-85": .negateAttackAndRetaliate(3, range: 3),        // Cold Front
        "gh-44": .healBonus(2),                                 // Potent Potables
        "gh-346": .negateDamage,                                // Immortality
        "gh-175": .retaliateAgainstMelee(2),                    // Purifying Aura
        "gh-203": .attackPackage(bonus: 3, conditions: [.wound], advantage: true), // Angelic Ascension
        "gh-288": .conditionWhileInvisible(.stun),              // Voice of the Night
        "gh-325": .healedBonus(2),                              // Cauterize
        "gh-441": .healCleanses,                                // Master Physician
        "gh-322": .negateLethal,                                // Defiance of Death
        "gh-277": .endOfTurnInfuse(.dark),                      // Nightfall
        "gh-187": .endOfTurnInfuse(.light),                     // Beacon of Light
        "gh-230": .endOfTurnHealAdjacent(2),                    // Fortified Position
        "gh-13": .roundAttackBonus(1, .any),                    // Wall of Doom
        "gh-127": .roundAttackBonus(1, .ranged),                // Heaving Swing
        "gh-128": .roundAttackBonus(2, .melee),                 // Forceful Storm
        "gh-40": .roundAttackBonusWithAdjacentAllies(1),        // Enhancement Field
        "gh-2": .experiencePerRetaliate,                        // Eye for an Eye
        "gh-98": .negateNextDamage,                             // Trickster's Reversal
        "gh-4": .drawAttacksFromAdjacentAllies,                 // Provoking Roar
    ]

    /// The experience each charge slot gives, in order (0 for a plain slot).
    static func slots(of card: AbilityModel) -> [Int] {
        var result: [Int] = []
        func walk(_ actions: [ActionModel]) {
            for action in actions {
                if action.type == .card, let value = action.value?.stringValue {
                    if value == "slot" { result.append(0) }
                    else if value.hasPrefix("slotXp:") { result.append(Int(value.dropFirst("slotXp:".count)) ?? 0) }
                }
                walk(action.subActions ?? [])
            }
        }
        walk((card.actions ?? []) + (card.bottomActions ?? []))
        return result
    }
}

extension BoardCoordinator {

    /// The character's charged bonuses in effect: cards in the active area, and a card whose
    /// persistent half was performed this turn (before it is put away).
    func chargedBonuses(of character: GameCharacter) -> [(cardId: Int, bonus: ChargedBonus)] {
        var cards = character.activeCards
        if let turn = activePlayerTurn, turn.characterID == character.id {
            cards += turn.persistentCardsThisTurn.filter { !cards.contains($0) }
            cards.removeAll { turn.usedUpThisTurn.contains($0) }
        }
        return cards.compactMap { id in
            ChargedBonus.byCard["\(character.edition)-\(id)"].map { (id, $0) }
        }
    }

    func chargedBonuses(of piece: PieceID) -> [(cardId: Int, bonus: ChargedBonus)] {
        guard case .character(let id) = piece,
              let character = gameManager?.game.characters.first(where: { $0.id == id }) else { return [] }
        return chargedBonuses(of: character)
    }

    /// Mark one charge of a bonus: experience for an XP slot, and the card leaves the active
    /// area once every charge is marked.
    func useCharge(_ cardId: Int, of character: GameCharacter) {
        if ChargedBonus.byCard["\(character.edition)-\(cardId)"]?.isUnlimited == true { return }
        guard let card = gameManager?.characterManager.abilities(for: character).first(where: { $0.cardId == cardId }) else { return }
        let slots = ChargedBonus.slots(of: card)
        let used = character.bonusChargesUsed[cardId, default: 0]
        if used < slots.count, slots[used] > 0 {
            character.experience += slots[used]
            log("\(name(.character(character.id))) gains \(slots[used]) XP", category: .info)
        }
        let nowUsed = used + 1
        guard nowUsed >= slots.count else {
            character.bonusChargesUsed[cardId] = nowUsed
            return
        }
        character.bonusChargesUsed[cardId] = nil
        log("\(card.name ?? "The card")\u{2019}s bonus is used up", category: .info)
        if character.activeCards.contains(cardId) {
            character.removeFromActiveArea(cardId)
        } else if let turn = activePlayerTurn, turn.characterID == character.id {
            turn.usedUpThisTurn.insert(cardId)
        }
    }

    /// Mark a charge of the first bonus matching `matches`, returning it.
    @discardableResult
    func useFirstCharge(of piece: PieceID, where matches: (ChargedBonus) -> Bool) -> ChargedBonus? {
        guard case .character(let id) = piece,
              let character = gameManager?.game.characters.first(where: { $0.id == id }),
              let found = chargedBonuses(of: character).first(where: { matches($0.bonus) }) else { return nil }
        useCharge(found.cardId, of: character)
        return found.bonus
    }

    /// Whether the character would suffer no damage from `amount` (Juggernaut, Frost Armor,
    /// Trickster's Reversal; Defiance of Death when it would be lethal), without using a charge.
    func negatesDamage(_ piece: PieceID, amount: Int) -> Bool {
        let health = entity(for: piece)?.health ?? 0
        return chargedBonuses(of: piece).contains {
            $0.bonus == .negateDamage || $0.bonus == .negateNextDamage || ($0.bonus == .negateLethal && amount >= health)
        }
    }

    /// Provoking Roar: an enemy attacking an ally beside a provoking character attacks that
    /// character instead, whatever the range. Returns who is really attacked.
    func provokedTarget(of attacker: PieceID, aimingAt target: PieceID) -> PieceID {
        guard let game = gameManager?.game, let position = boardState.piecePositions[target] else { return target }
        for character in game.characters {
            let provoker = PieceID.character(character.id)
            guard provoker != target, areEnemies(attacker, provoker), !areEnemies(provoker, target),
                  let theirs = boardState.piecePositions[provoker], theirs.isAdjacent(to: position),
                  chargedBonuses(of: character).contains(where: { $0.bonus == .drawAttacksFromAdjacentAllies }) else { continue }
            log("\(name(provoker)) draws the attack meant for \(name(target))", category: .attack)
            return provoker
        }
        return target
    }

    /// This round's attack bonuses for an attack by `attacker` (its own, and Enhancement Field
    /// from an ally beside it).
    func roundAttackBonus(for attacker: PieceID, ranged: Bool) -> Int {
        guard let game = gameManager?.game else { return 0 }
        var total = 0
        for (_, bonus) in chargedBonuses(of: attacker) {
            switch bonus {
            case .roundAttackBonus(let n, let reach) where reach == .any || (reach == .ranged) == ranged:
                total += n
            case .roundAttackBonusWithAdjacentAllies(let n):
                total += n
            default: break
            }
        }
        guard let position = boardState.piecePositions[attacker] else { return total }
        for character in game.characters where PieceID.character(character.id) != attacker {
            guard let theirs = boardState.piecePositions[.character(character.id)],
                  theirs.isAdjacent(to: position), !areEnemies(attacker, .character(character.id)) else { continue }
            for (_, bonus) in chargedBonuses(of: character) {
                if case .roundAttackBonusWithAdjacentAllies(let n) = bonus { total += n }
            }
        }
        return total
    }

    /// Bonuses printed in the text of the attack being made, judged per target: "+2 when the
    /// target is adjacent to any of your allies", "+1 for each negative condition on the target",
    /// "XP +1 for each enemy targeted" (Backstab, Submissive Affliction, Net Shooter…).
    func attackTextBonus(_ texts: [String], attacker: PieceID, target: PieceID) -> (attack: Int, experience: Int) {
        guard let targetPos = boardState.piecePositions[target], let defender = entity(for: target) else { return (0, 0) }
        let neighbours = targetPos.neighbors.compactMap { boardState.piece(at: $0) }
        let attackersAllies = neighbours.filter { $0 != attacker && !areEnemies($0, attacker) }.count
        let isolated = !neighbours.contains { $0 != target && !areEnemies($0, target) }
        let negatives = defender.entityConditions.filter { $0.name.isNegative && !$0.expired }.count
        func number(_ pattern: String, in text: String) -> Int {
            guard let match = text.firstMatch(of: try! Regex(pattern)), let value = match.output[1].substring else { return 0 }
            return Int(value) ?? 0
        }
        var attack = 0, experience = 0
        for text in texts {
            let bonus = number(#"\+(\d+) attack"#, in: text), xp = number(#"xp \+(\d+)"#, in: text)
            if text.contains("adjacent to any of your allies") {
                if attackersAllies > 0 { attack += bonus; experience += xp }
            } else if text.contains("adjacent to none of its allies") {
                if isolated { attack += bonus; experience += xp }
            } else if text.contains("for each of your allies adjacent to the target") {
                attack += bonus * attackersAllies
            } else if text.contains("double the shield value of the target") {
                attack += 2 * CombatResolver.totalShield(shield: defender.shield, shieldPersistent: defender.shieldPersistent)
            } else if text.contains("for each negative condition on the target") {
                attack += bonus * negatives
                experience += xp * negatives
            } else if text.contains("for each enemy targeted") {
                experience += max(1, xp)
            }
        }
        return (attack, experience)
    }

    /// End-of-turn bonuses: Nightfall and Beacon of Light infuse, Fortified Position heals.
    func applyEndOfTurnBonuses(_ turn: PlayerTurnController) {
        guard let character = gameManager?.game.characters.first(where: { $0.id == turn.characterID }),
              let game = gameManager?.game else { return }
        let me = PieceID.character(character.id)
        for (cardId, bonus) in chargedBonuses(of: character) {
            switch bonus {
            case .endOfTurnInfuse(let element):
                guard game.elementBoard.first(where: { $0.type == element })?.state != .strong else { continue }
                game.infuseElement(element)
                log("\(name(me)) infuses \(GameText.elementName(element))", category: .element)
                useCharge(cardId, of: character)
            case .endOfTurnHealAdjacent(let amount):
                for ally in alliesInRange(of: me, range: 1, includeSelf: false).sorted() {
                    let healed = heal(ally, amount: amount, source: me)
                    log("\(name(me)) heals \(name(ally)) for \(healed)", category: .heal)
                }
                useCharge(cardId, of: character)
            default:
                continue
            }
        }
    }

    /// The attack value against `target` with the attacker's conditional bonuses (Single Out,
    /// Cull the Weak, Smoke Bomb, Spring the Trap), marking a charge of each that applies.
    func attackValueWithBonuses(_ value: Int, attacker: PieceID, target: PieceID) -> Int {
        guard case .character = attacker, let targetPos = boardState.piecePositions[target] else { return value }
        let neighbours = targetPos.neighbors.compactMap { boardState.piece(at: $0) }
        // The target's allies are the figures on its side; the attacker's, those on theirs.
        let isolated = !neighbours.contains { $0 != target && !areEnemies($0, target) }
        let flanked = isolated && neighbours.contains { $0 != attacker && !areEnemies($0, attacker) }
        let disabled = [.disarm, .immobilize, .stun].contains { isConditionActive($0, on: target) }
        var result = value
        for (_, bonus) in chargedBonuses(of: attacker) {
            switch bonus {
            case .bonusAgainstIsolated(let n) where isolated:
                result += n
                useFirstCharge(of: attacker) { $0 == bonus }
            case .bonusAgainstDisabled(let n) where disabled:
                result += n
                useFirstCharge(of: attacker) { $0 == bonus }
            case .doubleWhileInvisible where isConditionActive(.invisible, on: attacker):
                result *= 2
                useFirstCharge(of: attacker) { $0 == bonus }
            case .doubleAgainstFlanked where flanked:
                result *= 2
                useFirstCharge(of: attacker) { $0 == bonus }
            default:
                break
            }
        }
        if result != value { log("\(name(attacker))\u{2019}s bonus: Attack \(result)", category: .attack) }
        return result
    }
}
