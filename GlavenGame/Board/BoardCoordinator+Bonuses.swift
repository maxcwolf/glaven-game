import Foundation

/// Persistent bonuses with charges (GH p.24): "on the next six sources of damage…", "on your
/// next four ranged attack actions…". The card stays in the active area and a charge is marked
/// each time the bonus applies (some slots give experience); when every charge is marked the
/// card leaves the active area, to the lost pile if it has the lost icon.
///
/// Played so far: the starting classes' charged cards whose effect needs no extra choice.
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
    /// +N on each of the character's attack actions.
    case attackBonus(Int)
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
        "gh-69": .attackBonus(1),                               // Crackling Air
        "gh-79": .retaliateAgainstMelee(3),                     // Engulfed in Flames
        "gh-85": .negateAttackAndRetaliate(3, range: 3),        // Cold Front
        "gh-44": .healBonus(2),                                 // Potent Potables
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

    /// Whether the character would suffer no damage (Juggernaut, Frost Armor), without using a charge.
    func negatesDamage(_ piece: PieceID) -> Bool {
        chargedBonuses(of: piece).contains { $0.bonus == .negateDamage }
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
